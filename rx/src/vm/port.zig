const Receiver = @import("interface.zig").Receiver;
const Value = @import("../memory/value.zig").Value;
const Scheduler = @import("scheduler.zig").Scheduler;

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
