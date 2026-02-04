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

    pub fn init(allocator: std.mem.Allocator, pid: ActorId, main_closure: *HeapObject) !*Process {
        // TODO: same allocator as vm heap ??
        const self = try allocator.create(Process);

        self.node = .{ .prev = null, .next = null };
        self.pid = pid;
        self.mailbox = .empty;

        self.stack = .empty;
        self.frames = .empty;
        self.saved_ip = 0;

        self.allocator = allocator;

        try self.stack.append(allocator,Value.pointer(main_closure));
        try self.stack.appendNTimes(allocator, Value.nil(), 20); 

        try self.frames.append(allocator, .{
            .base = 1,
            .return_ip = 0,
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
        try self.mailbox.append(self.allocator,msg);
    }

    pub fn pop(self: *Process) ?Value {
        if(self.mailbox.items.len == 0) {
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
