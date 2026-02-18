const std = @import("std");

pub const Opcode = enum(u8) {
    // MOVE,       // R(A) = R(B)
    LOADK, // R(A) = K(Bx)
    // LOADNIL,    // R(A) = nil
    // LOADBOOL,   // R(A) = bool(B)

    SEND, // SEND R(A) MSG: R(B)
    RECV, // R(A) = RECV()

    ADD, // R(A) = R(B) + R(C)
    SUB, // R(A) = R(B) - R(C)

    LT, // R(A) = R(B) < R(C)
    GT, // R(A) = R(B) > R(C)

    JF, // IF NOT R(A) JMP += Bx

    CALL, // CALL R(A) B
    RET, // RETURN R(A)

    PRINT, // PRINT R(A)
};

pub const Instruction = packed struct {
    opcode: u8,
    A: u8,
    B: u8,
    C: u8,

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

    pub fn getBx(self: Instruction) u16 {
        return (@as(u16, self.C) << 8) | @as(u16, self.B);
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
        try writer.print("{s} ", .{@tagName(op)});

        switch (op) {
            .LOADK => {
                try writer.print("R{d} K{d}", .{ self.A, self.getBx() });
            },
            .RET, .RECV, .PRINT => {
                try writer.print("R{d}", .{self.A});
            },
            .SEND => {
                try writer.print("R{d} R{d}", .{ self.A, self.B });
            },
            .JF => {
                try writer.print("R{d} +{d}", .{ self.A, self.getBx() });
            },
            .CALL => {
                try writer.print("R{d} {d}", .{ self.A, self.B });
            },
            // .MOVE => {
            //     try writer.print("R\x1b[32m{d}\x1b[0m R\x1b[32m{d}\x1b[0m", .{ self.A, self.B });
            // },
            else => {
                // ABC format
                try writer.print("R{d}  R{d}  R{d}", .{ self.A, self.B, self.C });
            },
        }
    }
};
