const std = @import("std");
const rx = @import("rx");
const Lexer = @import("lexer.zig").Lexer;
const ast = @import("ast.zig");
const compiler = @import("compiler.zig");

pub fn main(init: std.process.Init) !void {
    const gpa_alloc = init.gpa;
    const arena_alloc = init.arena.allocator();

    const args = try init.minimal.args.toSlice(arena_alloc);

    if (args.len < 2) {
        std.debug.print("Usage: {s} <filename.rxt>\n", .{args[0]});
        return;
    }

    const path = args[1];

    const io = init.io;

    const file = try std.Io.Dir.cwd().openFile(io, path, .{});
    defer file.close(io);

    const fileStat = try file.stat(io);
    const fileSize = fileStat.size;

    const content: []u8 = try arena_alloc.alloc(u8, @as(usize, @intCast(fileSize)) + 1);
    content[@as(usize, @intCast(fileSize))] = 0;
    _ = try file.readPositionalAll(io, content[0..@as(usize, @intCast(fileSize))], 0);

    const source = content[0..@as(usize, @intCast(fileSize)) :0];

    var module = try ast.parse(arena_alloc, source);
    // No explicit deinit needed the arena handles it.

    // try writer.print("{f}", .{module});

    var heap = try rx.memory.Heap.init(gpa_alloc, 1024 * 1024);
    defer heap.deinit();

    // `closure` is a pointer into `heap`, which outlives the arena — safe.
    const closure = try compiler.compile(arena_alloc, &heap, &module);
    // ── End of compilation phase ────────────────────────────────────────────

    // var writer = std.fs.File.stdout().writer(&.{}).interface;

    // try rx.memory.Closure.dump(closure, &writer);
    // const func = rx.memory.Closure.getFunction(closure);
    // const fib_val = rx.memory.Function.getConstants(func)[0];
    // const fib = try fib_val.asClosure();
    // try rx.memory.Closure.dump(fib, &writer);

    var system = rx.vm.System.init(gpa_alloc);
    var scheduler = rx.vm.Scheduler.init(gpa_alloc, 0, &system, io);
    defer scheduler.deinit();

    _ = try scheduler.spawn(closure, &.{});

    try scheduler.execute();
}
