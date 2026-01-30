pub const memory = struct {
    pub const Value = @import("memory/value.zig").Value;
};

pub const vm = struct {
    pub const Instruction = @import("vm/opcode.zig").Instruction;
    pub const Opcode = @import("vm/opcode.zig").Opcode;
};
