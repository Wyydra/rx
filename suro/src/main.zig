const std = @import("std");
const Io = std.Io;
const log = std.log.scoped(.suro);
const Parser = @import("Parser.zig");

pub fn main(init: std.process.Init) !u8 {
    const arena: std.mem.Allocator = init.arena.allocator();
    const io = init.io;
    const args = try init.minimal.args.toSlice(arena);

    if (args.len != 2) {
        log.err("Usage: {s} <filename>\n", .{args[0]});
        return error.WrongArgument;
    }

    for (args) |arg| {
        std.log.info("arg: {s}", .{arg});
    }

    const path = args[1];

    const file = try std.Io.Dir.cwd().openFile(io, path, .{});
    defer file.close(io);

    const fileStat = try file.stat(io);
    const fileSize = fileStat.size;

    const content: []u8 = try arena.alloc(u8, @as(usize, @intCast(fileSize)) + 1);
    content[@as(usize, @intCast(fileSize))] = 0;
    _ = try file.readPositionalAll(io, content, 0);

    const source = content[0..@as(usize, @intCast(fileSize)) :0];

    const ast = Parser.parse(arena, source) catch |err| {
        std.log.err("Failed to parse source: {any}", .{err});
        return err;
    };

    std.debug.print("{any}", .{ast});

    return 0;
}
