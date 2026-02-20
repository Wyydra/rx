const std = @import("std");
const Value = @import("../memory/value.zig").Value;
const Opcode = @import("opcode.zig").Opcode;
const Instruction = @import("opcode.zig").Instruction;
const Heap = @import("../memory/heap.zig").Heap;
const HeapObject = @import("../memory/value.zig").HeapObject;
const Function = @import("../memory/function.zig");
const Closure = @import("../memory/closure.zig");

pub const Assembler = struct {
    allocator: std.mem.Allocator,
    code: std.ArrayList(u8),
    heap: *Heap,
    constants: std.ArrayList(Value),
    max_reg: u8 = 0,

    pub fn init(allocator: std.mem.Allocator, heap: *Heap) Assembler {
        return .{
            .allocator = allocator,
            .heap = heap,
            .code = .empty,
            .constants = .empty,
        };
    }

    pub fn deinit(self: *Assembler) void {
        self.code.deinit(self.allocator);
        self.constants.deinit(self.allocator);
    }

    pub fn emit(self: *Assembler, op: Opcode, a: u8, b: u8, c: u8) !void {
        // Track the highest register index seen — used by compileToClosure for max_regs.
        const top = @max(a, @max(b, c)) + 1;
        if (top > self.max_reg) self.max_reg = top;
        try self.code.append(self.allocator, @intFromEnum(op));
        try self.code.append(self.allocator, a);
        try self.code.append(self.allocator, b);
        try self.code.append(self.allocator, c);
    }

    pub fn loadConstant(self: *Assembler, reg: u8, val: Value) !void {
        const len = self.constants.items.len;
        try self.constants.append(self.allocator, val);

        if (len > std.math.maxInt(u32)) return error.TooManyConstants;

        try self.emit(.LOADK, reg, @intCast(len), 0);
    }

    pub fn loadString(self: *Assembler, reg: u8, str: []const u8) !void {
        const String = @import("../memory/string.zig");
        const obj = try String.alloc(self.heap, str);
        try self.loadConstant(reg, Value.pointer(obj));
    }

    pub fn send(self: *Assembler, target_reg: u8, msg_reg: u8) !void {
        try self.emit(.SEND, target_reg, msg_reg, 0);
    }

    pub fn recv(self: *Assembler, dest_reg: u8) !void {
        try self.emit(.RECV, dest_reg, 0, 0);
    }

    pub fn ret(self: *Assembler, reg: u8) !void {
        try self.emit(.RET, reg, 0, 0);
    }

    pub fn move(self: *Assembler, src: u8, dest: u8) !void {
        try self.emit(.MOVE, src, dest, 0);
    }

    pub fn print(self: *Assembler, reg: u8) !void {
        try self.emit(.PRINT, reg, 0, 0);
    }

    pub fn add(self: *Assembler, dest: u8, lhs: u8, rhs: u8) !void {
        try self.emit(.ADD, dest, lhs, rhs);
    }

    pub fn call(self: *Assembler, closure_reg: u8, count_reg: u8) !void {
        try self.emit(.CALL, closure_reg, count_reg, 0);
    }

    pub fn patchJump(self: *Assembler, jump_instruction_index: usize) !void {
        const next_inst_index = jump_instruction_index + 4;
        const distance_bytes = self.code.items.len - next_inst_index;

        if (distance_bytes > std.math.maxInt(u16)) {
            return error.JumpTooFar;
        }

        const bx: u16 = @intCast(distance_bytes);

        const raw = std.mem.readInt(u32, self.code.items[jump_instruction_index..][0..4], .little);

        var inst = Instruction.decode(raw);

        inst.B = @truncate(bx & 0xFF);
        inst.C = @truncate(bx >> 8);

        std.mem.writeInt(u32, self.code.items[jump_instruction_index..][0..4], inst.encode(), .little);
    }

    pub fn dump(self: *Assembler, writer: *std.Io.Writer) !void {
        try writer.print("== Code Dump ==\n", .{});

        var i: usize = 0;
        while (i < self.code.items.len) : (i += 4) {
            const raw = std.mem.readInt(u32, self.code.items[i..][0..4], .little);
            const inst = Instruction.decode(raw);

            try writer.print("{x:0>4} ", .{i});
            try inst.format(writer);
            try writer.print("\n", .{});
            try writer.flush();
        }
    }

    pub fn compileToClosure(self: *Assembler) !*HeapObject {
        const func_obj = try Function.alloc(self.heap,
            0,              // arity
            0,              // upvalues
            self.max_reg,   // peak register count, tracked by emit()
            self.code.items, self.constants.items);

        return try Closure.alloc(self.heap, func_obj, 0);
    }
};
