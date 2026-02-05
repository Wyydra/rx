const std = @import("std");
const rx = @import("rx");
const ConsolePort = @import("console.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const allocator = gpa.allocator();

    var heap = try rx.memory.Heap.init(allocator, 1024 * 1024);
    defer heap.deinit();

    var sched = rx.vm.Scheduler.init(allocator, 0);
    defer sched.deinit();

    // 1. CONSOLE (PID 1)
    var console = ConsolePort.create();
    _ = try sched.spawnReceiver(console.asReceiver());

    // 2. RECEIVER (PID 2)
    var asm_recv = rx.vm.Assembler.init(allocator);
    defer asm_recv.deinit();

    try asm_recv.loadConstant(1, rx.memory.Value.integer(1));
    try asm_recv.recv(0);
    try asm_recv.send(1, 0); // print
    try asm_recv.ret(0);

    const closure_recv = try asm_recv.compileToClosure(&heap);
    _ = try sched.spawn(closure_recv); 


    // 3. SENDER (PID 3)
    var asm_send = rx.vm.Assembler.init(allocator);
    defer asm_send.deinit();

    try asm_send.loadConstant(0, rx.memory.Value.integer(2));  
    try asm_send.loadConstant(1, rx.memory.Value.integer(99)); 
    try asm_send.send(0, 1);                         
    try asm_send.ret(0);

    const closure_send = try asm_send.compileToClosure(&heap);
    _ = try sched.spawn(closure_send); 

    // Run
    try sched.execute();
}
