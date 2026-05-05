const std = @import("std");
const Value = @import("../memory/value.zig").Value;
const HeapObject = @import("../memory/value.zig").HeapObject;
const Function = @import("../memory/function.zig");
const Closure = @import("../memory/closure.zig");
const Receiver = @import("interface.zig").Receiver;
const Scheduler = @import("scheduler.zig").Scheduler;
const ActorId = @import("actor.zig").ActorId;
const TraceFlags = @import("../memory/heap.zig").TraceFlags;
const Heap = @import("../memory/heap.zig").Heap;
const Mailbox = @import("mailbox.zig").Mailbox;
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

    mailbox: Mailbox,
    mutex: std.Io.Mutex,

    stack: std.ArrayList(Value),
    frames: std.ArrayList(CallFrame),

    saved_ip: usize,

    allocator: std.mem.Allocator,
    io: std.Io,

    const INITIAL_STACK_SIZE: usize = 16;
    const INITIAL_FRAME_CAPACITY: usize = 8;

    pub fn init(allocator: std.mem.Allocator, io: std.Io, pid: ActorId, main_func: *HeapObject, args: []const Value) !*Process {
        std.debug.assert(main_func.kind == .function);
        const self = try allocator.create(Process);

        self.node = .{ .prev = null, .next = null };
        self.pid = pid;
        self.mailbox = try Mailbox.init(allocator, io);
        self.mutex = std.Io.Mutex.init;

        self.heap = try allocator.create(Heap); // TODO: right way to do this?
        self.heap.* = try Heap.init(allocator, Heap.DEFAULT_SIZE);

        self.stack = .empty;
        self.frames = .empty;
        self.saved_ip = 0;

        self.allocator = allocator;
        self.io = io;

        const min_stack_len = 1 + Function.getMaxRegs(main_func);
        const max_initial_stack = @max(@max(INITIAL_STACK_SIZE, args.len + 1), min_stack_len); // +1 because closure is index 0
        try self.stack.ensureTotalCapacity(allocator, max_initial_stack);
        try self.frames.ensureTotalCapacity(allocator, INITIAL_FRAME_CAPACITY);

        const main_closure = try Closure.alloc(self.heap.allocator(), main_func, 0);

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

    pub fn deinit(self: *Process, sched: *Scheduler) void {
        _ = sched;
        self.mailbox.deinit();
        self.stack.deinit(self.allocator);
        self.frames.deinit(self.allocator);
        self.heap.deinit();
        self.allocator.destroy(self.heap);
        self.allocator.destroy(self);
    }

    pub fn push(self: *Process, msg: Value, sched: *Scheduler) !void {
        // We MUST lock the heap to perform the deep copy because the heap is NOT thread-safe.
        self.mutex.lockUncancelable(self.io);
        const copied_msg = self.heap.deepCopyValue(msg) catch |err| {
            self.mutex.unlock(self.io);
            return err;
        };
        self.mutex.unlock(self.io);

        // Mailbox push is lock-free and safe to do outside the process mutex.
        try self.mailbox.put(copied_msg);

        // Notify the scheduler to wake up this process if it's currently waiting.
        if (self.status == .waiting) {
            self.mutex.lockUncancelable(self.io);
            defer self.mutex.unlock(self.io);
            if (self.status == .waiting) {
                self.status = .running;
                sched.mutex.lockUncancelable(sched.io);
                sched.waiting_queue.remove(&self.node);
                sched.run_queue.push(self) catch @panic("OOM in run_queue");
                sched.io_event.set(sched.io);
                sched.mutex.unlock(sched.io);
            }
        }
    }

    pub fn pop(self: *Process) !?Value {
        return self.mailbox.get();
    }

    pub fn collectGarbage(self: *Process) !void {
        var heap = self.heap;

        heap.copy_offset = 0;
        heap.scanned_offset = 0;

        var active_stack_len: usize = 0;
        if (self.frames.items.len > 0) {
            const top_frame = self.frames.items[self.frames.items.len - 1];
            const func = Closure.getFunction(top_frame.closure);
            active_stack_len = top_frame.base + Function.getMaxRegs(func);
        }

        for (self.stack.items[0..active_stack_len]) |*value| {
            try heap.copyValue(value);
        }

        for (self.frames.items) |*frame| {
            frame.closure = try heap.copyObject(frame.closure);
        }

        // We MUST lock during GC because even if the mailbox is lock-free,
        // a concurrent `push` would call `deepCopyValue` which modifies the heap
        // while we are moving objects!
        // We MUST lock during GC because even if the mailbox is lock-free,
        // a concurrent `push` would call `deepCopyValue` which modifies the heap
        // while we are moving objects!
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);

        if (!self.mailbox.isEmpty()) {
            var mailbox_it = self.mailbox.iterator();
            while (mailbox_it.next()) |data_ptr| {
                if (!data_ptr.is(.nil)) {
                    try heap.copyValue(data_ptr);
                }
            }
        }

        try heap.scan();

        var newStrings = std.StringHashMap(*HeapObject).init(heap.backing_allocator);

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

        var newAtoms = std.StringHashMap(*HeapObject).init(heap.backing_allocator);
        var it_atoms = heap.atoms.iterator();
        while (it_atoms.next()) |entry| {
            const oldAtomObj = entry.value_ptr.*;
            if (oldAtomObj.isMoved()) {
                const newAtomObj = oldAtomObj.getForwardingPointer();
                const newKey = @import("../memory/string.zig").getChars(newAtomObj);
                try newAtoms.put(newKey, newAtomObj);
            }
        }
        heap.atoms.deinit();
        heap.atoms = newAtoms;

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

    fn receiveImpl(ptr: *anyopaque, msg: Value, sched: *Scheduler) bool {
        const self = @as(*Process, @ptrCast(@alignCast(ptr)));
        // push handles moving from waiting_queue to run_queue safely
        self.push(msg, sched) catch return false;
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

    pub fn ensureStack(self: *Process, min_len: usize) !void {
        if (self.stack.items.len < min_len) {
            const old_len = self.stack.items.len;
            const target_len = @max(min_len, old_len + 128);
            try self.stack.resize(self.allocator, target_len);
            for (self.stack.items[old_len..]) |*slot| slot.* = Value.nil();
        }
    }
};
