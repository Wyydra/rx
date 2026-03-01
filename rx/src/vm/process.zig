const std = @import("std");
const Value = @import("../memory/value.zig").Value;
const HeapObject = @import("../memory/value.zig").HeapObject;
const Function = @import("../memory/function.zig");
const Closure = @import("../memory/closure.zig");
const Receiver = @import("interface.zig").Receiver;
const ActorId = @import("actor.zig").ActorId;
const Heap = @import("../memory/heap.zig").Heap;
const StringMeta = @import("../memory/string.zig").StringMeta;

pub const CallFrame = struct {
    base: usize,
    caller_ip: usize,
    closure: *HeapObject,
};
pub const Process = struct {
    pub const Status = enum {
        running,
        waiting,
    };

    node: std.DoublyLinkedList.Node = .{},

    pid: ActorId,
    status: Status = .running,

    heap: *Heap,

    mailbox: std.ArrayList(Value),

    stack: std.ArrayList(Value),
    frames: std.ArrayList(CallFrame),

    saved_ip: usize,

    allocator: std.mem.Allocator,

    /// Initial register-window capacity. 16 should be enough for shallow programs;
    /// ArrayList will grow automatically if deeper frames need more.
    const INITIAL_STACK_SIZE: usize = 16;
    const INITIAL_FRAME_CAPACITY: usize = 8;

    pub fn init(allocator: std.mem.Allocator, pid: ActorId, main_closure: *HeapObject) !*Process {
        const self = try allocator.create(Process);

        self.node = .{ .prev = null, .next = null };
        self.pid = pid;
        self.mailbox = .empty;

        self.heap = try allocator.create(Heap); // TODO: right way to do this?
        self.heap.* = try Heap.init(allocator, Heap.DEFAULT_SIZE);

        self.stack = .empty;
        self.frames = .empty;
        self.saved_ip = 0;

        self.allocator = allocator;

        // Pre-allocate to avoid reallocs during the hot dispatch loop.
        try self.stack.ensureTotalCapacity(allocator, 1 + INITIAL_STACK_SIZE);
        try self.frames.ensureTotalCapacity(allocator, INITIAL_FRAME_CAPACITY);

        self.stack.appendAssumeCapacity(Value.pointer(main_closure));
        for (0..INITIAL_STACK_SIZE) |_| self.stack.appendAssumeCapacity(Value.nil());

        self.frames.appendAssumeCapacity(.{
            .base = 1,
            .caller_ip = 0,
            .closure = main_closure,
        });

        return self;
    }

    pub fn deinit(self: *Process) void {
        self.stack.deinit(self.allocator);
        self.frames.deinit(self.allocator);
        self.mailbox.deinit(self.allocator);
        self.heap.deinit();
        self.allocator.destroy(self.heap);
        self.allocator.destroy(self);
    }

    pub fn push(self: *Process, msg: Value) !void {
        try self.mailbox.append(self.allocator, msg);
    }

    pub fn pop(self: *Process) ?Value {
        if (self.mailbox.items.len == 0) {
            return null;
        }
        return self.mailbox.orderedRemove(0);
    }

    pub fn collectGarbage(self: *Process) !void {
        const heap = &self.heap;

        heap.copy_offset = 0;
        heap.scanned_offset = 0;

        for (self.stack.items) |*value| {
            try heap.copyValue(value);
        }

        for (self.frames.items) |*frame| {
            frame.closure = try heap.copyObject(frame.closure);
        }

        for (self.mailbox.items) |*value| { // TODO: is this needed ?
            try heap.copyValue(value);
        }

        while (heap.scanned_offset < heap.copy_offset) {
            const currentObjPtr = @intFromPtr(heap.to_space.ptr) + heap.scanned_offset;
            const currentObj: *HeapObject = @ptrFromInt(currentObjPtr);

            switch (currentObj.kind) {
                .string => {},
                .closure => {
                    const env = Closure.getEnv(currentObj);
                    for (env) |*val| {
                        try heap.copyValue(val);
                    }

                    const func = Closure.getFunction(currentObj);
                    const newFunc = try heap.copyObject(func);
                    Closure.setFunction(currentObj, newFunc);
                },
                .function => {
                    const constsConst = Function.getConstants(currentObj);
                    const consts = @as([*]Value, @ptrCast(@constCast(constsConst.ptr)))[0..constsConst.len];
                    for (consts) |*val| {
                        try heap.copyValue(val);
                    }
                },
            }

            const totalSize = @sizeOf(HeapObject) + currentObj.size;
            heap.scanned_offset += std.mem.alignForward(usize, totalSize, 8);
        }

        var newStrings = std.StringHashMap(*HeapObject).init(heap.allocator);

        var it = heap.strings.iterator();
        while (it.next()) |entry| {
            const oldStringObj = entry.value_ptr.*;

            if (oldStringObj.isMoved()) {
                const newStringObj = oldStringObj.getForwardingPointer().?;

                const newPayload_ptr = @as([*]const u8, @ptrCast(newStringObj)) + @sizeOf(HeapObject);
                const newMeta = @as(*const StringMeta, @ptrCast(@alignCast(newPayload_ptr)));
                const newChars_ptr = newPayload_ptr + @sizeOf(StringMeta);
                const newKey = newChars_ptr[0..newMeta.len];

                try newStrings.put(newKey, newStringObj);
            }
        }

        heap.strings.deinit();
        heap.strings = newStrings;

        const temp = heap.from_space;
        heap.from_space = heap.to_space;
        heap.to_space = temp;

        heap.offset = heap.copy_offset;
    }

    fn receiveImpl(ptr: *anyopaque, msg: Value) bool {
        const self = @as(*Process, @ptrCast(@alignCast(ptr)));
        self.push(msg) catch unreachable;
        if (self.status == .waiting) {
            self.status = .running;
            return true;
        }

        return false;
    }

    pub fn asReceiver(self: *Process) Receiver {
        return .{
            .ptr = self,
            .sendFn = receiveImpl,
        };
    }

    pub fn markWaiting(self: *Process) void {
        self.status = .waiting;
    }
};
