const std = @import("std");
const Value = @import("../memory/value.zig").Value;
const HeapObject = @import("../memory/value.zig").HeapObject;
const Function = @import("../memory/function.zig");
const Closure = @import("../memory/closure.zig");
const Tuple = @import("../memory/tuple.zig");
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
    mailbox_head: usize = 0,

    stack: std.ArrayList(Value),
    frames: std.ArrayList(CallFrame),

    saved_ip: usize,

    allocator: std.mem.Allocator,

    const INITIAL_STACK_SIZE: usize = 16;
    const INITIAL_FRAME_CAPACITY: usize = 8;

    pub fn init(allocator: std.mem.Allocator, pid: ActorId, main_closure: *HeapObject, args: []const Value) !*Process {
        const self = try allocator.create(Process);

        self.node = .{ .prev = null, .next = null };
        self.pid = pid;
        self.mailbox = .empty;
        self.mailbox_head = 0;

        self.heap = try allocator.create(Heap); // TODO: right way to do this?
        self.heap.* = try Heap.init(allocator, Heap.DEFAULT_SIZE);

        self.stack = .empty;
        self.frames = .empty;
        self.saved_ip = 0;

        self.allocator = allocator;

        const max_initial_stack = @max(INITIAL_STACK_SIZE, args.len + 1); // +1 because closure is index 0
        try self.stack.ensureTotalCapacity(allocator, max_initial_stack);
        try self.frames.ensureTotalCapacity(allocator, INITIAL_FRAME_CAPACITY);

        self.stack.appendAssumeCapacity(Value.pointer(main_closure));
        for (args) |arg_val| {
            // we must copy the values into the new process heap because they currently live in another process memory
            const local_val = try self.heap.deepCopyValue(arg_val);
            self.stack.appendAssumeCapacity(local_val);
        }
        for (0..(max_initial_stack - 1 - args.len)) |_| self.stack.appendAssumeCapacity(Value.nil());

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
        const local_msg = try self.heap.deepCopyValue(msg);
        try self.mailbox.append(self.allocator, local_msg);
    }

    pub fn pop(self: *Process) ?Value {
        if (self.mailbox_head >= self.mailbox.items.len) return null;

        const msg = self.mailbox.items[self.mailbox_head];
        self.mailbox_head += 1;

        // Periodic compaction: slide remaining items to front every 64 pops
        if (self.mailbox_head >= 64) {
            const remaining = self.mailbox.items[self.mailbox_head..];
            std.mem.copyForwards(Value, self.mailbox.items[0..remaining.len], remaining);
            self.mailbox.items.len = remaining.len;
            self.mailbox_head = 0;
        }

        return msg;
    }

    pub fn collectGarbage(self: *Process) !void {
        const heap = self.heap;

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
                .tuple => {
                    const elems = Tuple.slice(currentObj);
                    for (elems) |*val| {
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
                const newStringObj = oldStringObj.getForwardingPointer();

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

    pub fn alloc(self: *Process, kind: HeapObject.Kind, payload_size: usize) !*HeapObject {
        if (self.heap.allocUnsafe(kind, payload_size)) |obj| {
            return obj;
        } else |err| {
            if (err != error.OutOfMemory) return err;
        }

        try self.collectGarbage();

        return self.heap.allocUnsafe(kind, payload_size);
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
