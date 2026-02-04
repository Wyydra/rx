const std = @import("std");
const rx = @import("rx");

fn consoleHandler(ctx: ?*anyopaque, msg: rx.memory.Value) void {
    _ = ctx;
    std.debug.print("{f}\n", .{msg});
}
pub fn create() rx.vm.Port {
    return .{
        .context = null,
        .handler = consoleHandler,
    };
}
