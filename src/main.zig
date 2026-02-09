const std = @import("std");
const rx = @import("rx");
const ConsolePort = @import("console.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const allocator = gpa.allocator();

    var heap = try rx.memory.Heap.init(allocator, 1024 * 1024);
    defer heap.deinit();

    var system = rx.vm.System.init(allocator);
    defer system.deinit();

    var scheduler = rx.vm.Scheduler.init(allocator, 0, &system);
    defer scheduler.deinit();

    std.debug.print("--- CALL Opcode Test ---\n", .{});

    // 1. Define Callee: func(a, b) { return a + b }
    // Arity: 2
    // R0=a, R1=b
    // R2 = R0 + R1
    // RET R2

    var callee_code = std.ArrayList(u8){};
    defer callee_code.deinit(allocator);

    // ADD R2 R0 R1
    try callee_code.writer(allocator).writeInt(u32, rx.vm.Instruction.ABC(.ADD, 2, 0, 1).encode(), .little);
    // RET R2
    try callee_code.writer(allocator).writeInt(u32, rx.vm.Instruction.ABC(.RET, 2, 0, 0).encode(), .little);

    const callee_obj = try rx.memory.Function.alloc(&heap, 2, 0, callee_code.items, &[_]rx.memory.Value{});
    const callee_closure = try rx.memory.Closure.alloc(&heap, callee_obj, 0);

    // 2. Define Caller: calls callee(10, 20)
    // R0 = callee_closure (loaded from K0)
    // R1 = 10 (K1)
    // R2 = 20 (K2)
    // CALL R0 3 2
    // RET R0

    var caller_code = std.ArrayList(u8){};
    defer caller_code.deinit(allocator);

    // LOADK R0 K0
    try caller_code.writer(allocator).writeInt(u32, rx.vm.Instruction.ABC(.LOADK, 0, 0, 0).encode(), .little);
    // LOADK R1 K1
    try caller_code.writer(allocator).writeInt(u32, rx.vm.Instruction.ABC(.LOADK, 1, 1, 0).encode(), .little);
    // LOADK R2 K2
    try caller_code.writer(allocator).writeInt(u32, rx.vm.Instruction.ABC(.LOADK, 2, 2, 0).encode(), .little);

    // CALL R0 3 0
    try caller_code.writer(allocator).writeInt(u32, rx.vm.Instruction.ABC(.CALL, 0, 3, 0).encode(), .little);

    // RET R0
    try caller_code.writer(allocator).writeInt(u32, rx.vm.Instruction.ABC(.RET, 0, 0, 0).encode(), .little);

    const caller_consts = &[_]rx.memory.Value{
        rx.memory.Value.pointer(callee_closure),
        rx.memory.Value.integer(10),
        rx.memory.Value.integer(20),
    };

    const caller_obj = try rx.memory.Function.alloc(&heap, 0, 0, caller_code.items, caller_consts);
    const caller_closure = try rx.memory.Closure.alloc(&heap, caller_obj, 0);

    // 3. Setup Process and Run
    const pid = try scheduler.spawn(caller_closure);
    std.debug.print("Spawned Process {any}\n", .{pid});

    try scheduler.execute(); // This runs until all processes are done/waiting or deadlock

    std.debug.print("Scheduler finished.\n", .{});
    // We can't easily check the result here because execute() returns void and processes deinit on termination.
    // But we can check if it printed "Process Wrapped Terminated normally" in logs (from Scheduler.execute).
}
