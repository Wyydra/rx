const std = @import("std");
const c = @cImport(@cInclude("rx_api.h"));

fn echoHandler(ctx: ?*anyopaque, msg: c.rx_value_t, sched: ?*anyopaque) callconv(.c) void {
    _ = ctx;
    _ = sched;
    std.debug.print("Echo (Zig) port received a message! bits=0x{x}\n", .{msg.bits});
}

export fn rx_load(sched: ?*anyopaque) void {
    const pid = c.rx_spawn_port(sched, null, echoHandler, null);
    if (pid != 0) c.rx_register_port(sched, "echo", pid);
}
