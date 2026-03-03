const std = @import("std");
const rx = @import("rx");

fn consoleHandler(ctx: ?*anyopaque, msg: rx.memory.Value, sched: ?*anyopaque) callconv(.c) void {
    _ = ctx;
    _ = sched;
    std.debug.print("{f}\n", .{msg});
}
pub fn spawn(sched: *rx.vm.Scheduler) !rx.vm.ActorId {
    return try sched.spawnPort(null, consoleHandler, null);
}
