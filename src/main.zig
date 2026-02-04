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

    // ---------------------------------------------------------
    // ACTOR 1: CONSOLE PORT (PID will be <0:1> / Raw: 1)
    // ---------------------------------------------------------
    // Dynamic loading of C console port
    var lib = try std.DynLib.open("src/libc_console.so");
    // defer lib.close();

    const create_fn = lib.lookup(*const fn (*rx.vm.Port) callconv(.c) void, "create_console_port") orelse return error.SymbolNotFound;
    var console: rx.vm.Port = undefined;
    create_fn(&console);

    // var console = ConsolePort.create();
    const console_id = try sched.spawnReceiver(console.asReceiver());
    std.debug.print("Spawned Console (Dynamic) -> PID {f}\n", .{console_id});

    // ---------------------------------------------------------
    // ACTOR 2: THE RECEIVER (PID will be <0:2> / Raw: 2)
    // Logic:
    //   RECV  R0       (Wait for mail from Sender)
    //   LOADK R1, 0    (Load Console PID)
    //   SEND  R1, R0   (Forward mail to Console)
    //   RET
    // ---------------------------------------------------------

    var constants_recv = [_]rx.memory.Value{
        // K0: The Console's PID (Raw integer 1)
        rx.memory.Value.integer(1),
    };

    var code_recv = [_]u8{
        // RECV R0
        @intFromEnum(rx.vm.Opcode.RECV),  0x00, 0x00, 0x00,

        // LOADK R1 = K[0] (Console PID)
        @intFromEnum(rx.vm.Opcode.LOADK), 0x01, 0x00, 0x00,

        // SEND R1, R0 (Send R0's content to R1 target)
        // Format: [OP] [Target:R1] [Msg:R0] [00]
        @intFromEnum(rx.vm.Opcode.SEND),  0x01, 0x00, 0x00,

        // RET
        @intFromEnum(rx.vm.Opcode.RET),   0x00, 0x00, 0x00,
    };

    const func_recv = try rx.memory.Function.alloc(&heap, 0, 0, &code_recv, &constants_recv);
    const closure_recv = try rx.memory.Closure.alloc(&heap, func_recv, 0);

    const pid_recv = try sched.spawn(closure_recv);
    std.debug.print("Spawned Receiver -> PID {f}\n", .{pid_recv});

    // ---------------------------------------------------------
    // ACTOR 3: THE SENDER (PID will be <0:3> / Raw: 3)
    // Logic:
    //   LOADK R0, 0   (Target: Receiver PID 2)
    //   LOADK R1, 1   (Message: 99)
    //   SEND  R0, R1
    //   RET
    // ---------------------------------------------------------

    var constants_send = [_]rx.memory.Value{
        rx.memory.Value.integer(2), // K0: Receiver PID
        rx.memory.Value.integer(99),
    };

    var code_send = [_]u8{
        // LOADK R0 = K[0] (Receiver PID)
        @intFromEnum(rx.vm.Opcode.LOADK), 0x00, 0x00, 0x00,

        // LOADK R1 = K[1] (Message 99)
        @intFromEnum(rx.vm.Opcode.LOADK), 0x01, 0x01, 0x00,

        // SEND R0, R1
        @intFromEnum(rx.vm.Opcode.SEND),  0x00, 0x01, 0x00,

        // RET
        @intFromEnum(rx.vm.Opcode.RET),   0x00, 0x00, 0x00,
    };

    const func_send = try rx.memory.Function.alloc(&heap, 0, 0, &code_send, &constants_send);
    const closure_send = try rx.memory.Closure.alloc(&heap, func_send, 0);

    const pid_send = try sched.spawn(closure_send);
    std.debug.print("Spawned Sender   -> PID {f}\n", .{pid_send});

    std.debug.print("--------------------------------\n", .{});

    try sched.execute();
}
