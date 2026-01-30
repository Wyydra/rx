const std = @import("std");

pub const Opcode = enum (u8) {
    MOVE,       // R(A) = R(B)
    LOADK,      // R(A) = K(Bx)
    LOADNIL,    // R(A) = nil
    LOADBOOL,   // R(A) = bool(B)
    
    ADD,        // R(A) = R(B) + R(C)
    SUB,        // R(A) = R(B) - R(C)
};

pub const Instruction = packed struct {
    opcode: u8,
    A: u8,
    C: u8,
    B: u8,

    pub fn ABC(op: Opcode, a: u8, b: u8, c: u8) Instruction {
        return .{
            .opcode = @intFromEnum(op),
            .A = a,
            .B = b,
            .C = c,
        };
    }

    pub fn getOpcode(self: Instruction) Opcode {
        return @enumFromInt(self.opcode);
    }

    pub fn getBx(self:Instruction) u16 {
        return (@as(u16, self.B) << 8) | @as(u16, self.C);
    }

    pub fn encode(self: Instruction) u32 {
        return @bitCast(self);
    }

    pub fn decode(raw: u32) Instruction {
        return @bitCast(raw);
    }

    pub fn format(
        self: @This(),
        writer: *std.Io.Writer,
    ) std.Io.Writer.Error!void {
        const op = self.getOpcode();
        try writer.print("\x1b[36m{s}\x1b[0m ", .{@tagName(op)});

        switch (op) {
            .LOADK => {
                try writer.print("R\x1b[32m{d}\x1b[0m K\x1b[33m{d}\x1b[0m", .{self.A, self.getBx()});
            },
            .MOVE => {
                try writer.print("R\x1b[32m{d}\x1b[0m R\x1b[32m{d}\x1b[0m", .{self.A, self.B});
            },
            else => {
                // ABC format
                try writer.print("R\x1b[32m{d}\x1b[0m  R\x1b[32m{d}\x1b[0m  R\x1b[32m{d}\x1b[0m", .{self.A, self.B, self.C});
            }
        }
    }
};
