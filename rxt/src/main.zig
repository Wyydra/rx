const std = @import("std");
const rx = @import("rx");
const Lexer = @import("lexer.zig").Lexer;
const ast = @import("ast.zig");
const compiler = @import("compiler.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        std.debug.print("Usage: {s} <filename.rxt>\n", .{args[0]});
        return;
    }

    const path = args[1];

    var writer  = std.fs.File.stdout().writer(&.{}).interface;

    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    const fileStat = try file.stat();
    const fileSize = fileStat.size;

    const content: []u8 = try allocator.alloc(u8, @as(usize, @intCast(fileSize)) + 1);
    defer allocator.free(content);
    content[@as(usize, @intCast(fileSize))] = 0;
    _ = try file.readAll(content);

    const source = content[0..@as(usize, @intCast(fileSize)) :0];

    const module = try ast.parse(allocator, source);
    for (module.functions) |func| {
        allocator.free(func.body);
    }
    defer allocator.free(module.functions);

    try writer.print("{f}", .{module});

    var heap = try rx.memory.Heap.init(allocator, 1024 * 1024);
    defer heap.deinit();

    const closure = try compiler.compile(allocator, &heap, &module);

    var system = rx.vm.System.init(allocator);
    var scheduler = rx.vm.Scheduler.init(allocator, 0, &system);
    defer scheduler.deinit();

    _ = try scheduler.spawn(closure);

    try scheduler.execute();
}
