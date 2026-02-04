pub const memory = struct {
    pub const Value = @import("memory/value.zig").Value;
    pub const Heap = @import("memory/heap.zig").Heap;
    pub const Function = @import("memory/function.zig");
    pub const Closure = @import("memory/closure.zig");
};

pub const vm = struct {
    pub const Instruction = @import("vm/opcode.zig").Instruction;
    pub const Opcode = @import("vm/opcode.zig").Opcode;
    pub const Scheduler = @import("vm/scheduler.zig").Scheduler;
    pub const Port = @import("vm/port.zig").Port;
};
