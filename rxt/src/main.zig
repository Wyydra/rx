const std = @import("std");
const rx = @import("rx");
const Lexer = @import("lexer.zig").Lexer;

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

    const content: []u8 = try allocator.alloc(u8, fileSize + 1);
    defer allocator.free(content);
    content[fileSize] = 0;
    _ = try file.readAll(content);

    const source = content[0..fileSize :0];

    var lexer = Lexer.init(source);

    const token = lexer.next();

    try writer.print("{any}", .{token});
    try writer.flush();
}
