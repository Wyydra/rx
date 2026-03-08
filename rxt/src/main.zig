const std = @import("std");
const rx = @import("rx");
const Lexer = @import("lexer.zig").Lexer;
const ast = @import("ast.zig");
const compiler = @import("compiler.zig");

pub fn main(init: std.process.Init) !void {
    const gpa_alloc = init.gpa;
    const arena_alloc = init.arena.allocator();
    const io = init.io;

    const args = try init.minimal.args.toSlice(arena_alloc);

    if (args.len < 2) {
        std.debug.print("Usage: {s} <filename.rxt>\n", .{args[0]});
        return;
    }

    const path = args[1];

    const file = try std.Io.Dir.cwd().openFile(io, path, .{});
    defer file.close(io);

    const fileStat = try file.stat(io);
    const fileSize = fileStat.size;

    const content: []u8 = try arena_alloc.alloc(u8, @as(usize, @intCast(fileSize)) + 1);
    content[@as(usize, @intCast(fileSize))] = 0;
    _ = try file.readPositionalAll(io, content, 0);

    const source = content[0..@as(usize, @intCast(fileSize)) :0];

    var module = try ast.parse(arena_alloc, source);

    const function = try compiler.compile(arena_alloc, &module);

    var vm = try rx.init(gpa_alloc);
    defer vm.deinit();

    _ = try vm.spawn(function, &.{});

    try vm.execute();
}
