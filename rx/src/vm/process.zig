const std = @import("std");
const Value = @import("../memory/value.zig").Value;
const HeapObject = @import("../memory/value.zig").HeapObject;
const Function = @import("../memory/function.zig");
const Receiver = @import("interface.zig").Receiver;
const ActorId = @import("actor.zig").ActorId;

pub const CallFrame = struct {
    base: usize,
    return_ip: usize,
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
            .caller_ip = 0, // initial frame — caller_ip unused (RET terminates)
            .closure = main_closure,
        });

        return self;
    }

    pub fn deinit(self: *Process) void {
        self.stack.deinit(self.allocator);
        self.frames.deinit(self.allocator);
        self.mailbox.deinit(self.allocator);
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
