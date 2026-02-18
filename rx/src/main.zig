const std = @import("std");
const rx = @import("rx");
const log = std.log.scoped(.top);

pub const std_options = std.Options{
    .log_level = .debug,
};

pub fn main() !void {
    var stdout = std.fs.File.stdout().writer(&.{}).interface;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const allocator = gpa.allocator();

    var heap = try rx.memory.Heap.init(allocator, 1024 * 1024);
    defer heap.deinit();

    var system = rx.vm.System.init(allocator);
    defer system.deinit();

    var scheduler = rx.vm.Scheduler.init(allocator, 0, &system);
    defer scheduler.deinit();

    var asm_callee = rx.vm.Assembler.init(allocator, &heap);
    defer asm_callee.deinit();

    try asm_callee.print(0);
    try asm_callee.ret(0);

    try asm_callee.dump(&stdout);

    const closure_callee = try asm_callee.compileToClosure();

    var asm_caller = rx.vm.Assembler.init(allocator, &heap);
    defer asm_caller.deinit();

    try asm_caller.loadConstant(0, rx.memory.Value.pointer(closure_callee));
    try asm_caller.loadString(1, "Hello World");
    try asm_caller.call(0, 2); // args count + 1
    try asm_caller.print(0);
    try asm_caller.ret(0);

    try asm_caller.dump(&stdout);

    const closure_caller = try asm_caller.compileToClosure();
    _ = try scheduler.spawn(closure_caller);

    try scheduler.execute();
}
