const Receiver = @import("interface.zig").Receiver;
const Value = @import("../memory/value.zig").Value;
const deepCopyAlloc = @import("../memory/value.zig").deepCopyAlloc;
const freeValue = @import("../memory/value.zig").freeValue;
const Scheduler = @import("scheduler.zig").Scheduler;
const Mailbox = @import("mailbox.zig").Mailbox;

pub const HandlerFn = *const fn (
    ctx: ?*anyopaque,
    msg: Value,
    sched: *anyopaque,
) callconv(.c) void;

pub const DeinitFn = *const fn (ctx: ?*anyopaque) callconv(.c) void;

pub const Port = extern struct {
    context: ?*anyopaque,
    handler: HandlerFn,
    deinit: ?DeinitFn,
};

fn portReceiveImpl(ptr: *anyopaque, msg: Value, sched: *Scheduler) bool {
    const self: *Port = @ptrCast(@alignCast(ptr));
    self.handler(self.context, msg, @ptrCast(sched));
    return false;
}

pub fn asReceiver(port: *Port) Receiver {
    return .{ .ptr = port, .sendFn = portReceiveImpl };
}
pub const AsyncPort = struct {
    context: ?*anyopaque,
    handler: HandlerFn,
    deinit: ?DeinitFn,
    mailbox: Mailbox,
};

pub fn asyncPortLoop(self: *AsyncPort, sched: *Scheduler) void {
    while (self.mailbox.get(sched.io)) |msg| {
        self.handler(self.context, msg, @ptrCast(sched));
        // Free the deep-copied message now that the handler is done with it.
        freeValue(sched.allocator, msg);
    }
}

fn asyncPortReceiveImpl(ptr: *anyopaque, msg: Value, sched: *Scheduler) bool {
    const self: *AsyncPort = @ptrCast(@alignCast(ptr));
    // Deep-copy the message so it outlives the sender's process heap // TODO this might clash with the gc
    const owned = deepCopyAlloc(sched.allocator, msg) catch return false;
    self.mailbox.put(sched.io, owned);
    // Wake up the scheduler just in case the port sends an immediate reply to a sleeping process.
    sched.io_event.set(sched.io);
    return false;
}

pub fn asAsyncReceiver(port: *AsyncPort) Receiver {
    return .{ .ptr = port, .sendFn = asyncPortReceiveImpl };
}
