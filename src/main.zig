const std = @import("std");
const rx = @import("rx");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);

    const int = rx.memory.Value.integer(42);
    std.debug.print("Integer : {f}\n", .{int});

    const instruction = rx.vm.Instruction.ABC(rx.vm.Opcode.ADD, 0, 2, 3);
    std.debug.print("Instruction : {f}\n", .{instruction});
}
