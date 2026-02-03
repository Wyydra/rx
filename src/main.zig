const std = @import("std");
const rx = @import("rx");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const allocator = gpa.allocator();

    var heap = try rx.memory.Heap.init(allocator, 1024 * 1024); // 1MB Heap
    defer heap.deinit();

    var constants = [_]rx.memory.Value{ rx.memory.Value.integer(10), rx.memory.Value.integer(20) };

    var code = [_]u8{
        // 1. Load constants
        // LOADK R0 0 (10)
        @intFromEnum(rx.vm.Opcode.LOADK), 0x00, 0x00, 0x00, 

        // LOADK R1 1 (20)
        @intFromEnum(rx.vm.Opcode.LOADK), 0x01, 0x01, 0x00, 

        // 2. Add
        // ADD R2 R0 R1
        @intFromEnum(rx.vm.Opcode.ADD), 0x02, 0x00, 0x01, 

        // 3. Print R2
        @intFromEnum(rx.vm.Opcode.PRINT), 0x02, 0x00, 0x00, 

        @intFromEnum(rx.vm.Opcode.RET), 0x02, 0x00, 0x00,
    };

    const func_obj = try rx.memory.Function.alloc(&heap, 0, 0, &code, &constants);

    const main_closure = try rx.memory.Closure.alloc(&heap, func_obj, 0);

    var sched = rx.vm.Scheduler.init(allocator);
    defer sched.deinit();

    try sched.spawn(main_closure);
    try sched.execute(allocator);
}
