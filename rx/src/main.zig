const std = @import("std");
const rx = @import("rx");
const log = std.log.scoped(.top);

pub const std_options = std.Options{
    .log_level = .debug,
};

pub fn main() !void {
    log.info("Hello World!", .{});
}
