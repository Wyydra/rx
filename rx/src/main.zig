const std = @import("std");
const rx = @import("rx");
const log = std.log.scoped(.top);

pub const std_options = std.Options{
    .log_level = .debug,
};

comptime {
    _ = rx.api;
}

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    const io = init.io;

    var heap = try rx.memory.Heap.init(allocator, 1024 * 1024);
    defer heap.deinit();

    var system = rx.vm.System.init(allocator);
    defer system.deinit();

    var scheduler = rx.vm.Scheduler.init(allocator, 0, &system, io);
    defer scheduler.deinit();

    // Load the external dynamic plugin
    try scheduler.loadPlugin("/home/wydra/Documents/rx/examples/plugin_test.so");

    var asm_caller = rx.bytecode.Assembler.init(allocator, &heap);
    defer asm_caller.deinit();

    // R0 = port ID (assuming it is the first actor spawned, ID = 1)
    try asm_caller.loadConstant(0, rx.memory.Value.integer(1));
    // R1 = message
    try asm_caller.loadString(1, "Wake me up inside");

    // SEND msg(R1) to actor(R0)
    try asm_caller.send(0, 1);

    // After sending, the VM continues.
    try asm_caller.loadString(2, "[VM] I sent the message!");
    try asm_caller.print(2);
    try asm_caller.loadString(2, "[VM] Check me out, I'm not blocked at all!");
    try asm_caller.print(2);
    try asm_caller.loadString(2, "[VM] VM bytecode evaluation is now complete.");
    try asm_caller.print(2);
    try asm_caller.ret(0);

    var stderr_buf: [4096]u8 = undefined;
    var stderr_writer = std.Io.File.stderr().writer(io, &stderr_buf);
    const stderr = &stderr_writer.interface;
    try asm_caller.dump(stderr);

    const closure_caller = try asm_caller.compileToClosure();
    _ = try scheduler.spawn(closure_caller, &.{});

    try scheduler.execute();

    // Give the async port time to process the message before we shut down
    std.debug.print("VM finished executing bytecode. Waiting for 1s to let async ports finish...\n", .{});
    var counter: u64 = 0;
    while (counter < 200_000_000) : (counter += 1) {
        std.mem.doNotOptimizeAway(counter);
    }
}
