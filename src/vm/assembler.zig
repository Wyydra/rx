const std = @import("std");
const Value = @import("../memory/value.zig").Value;
const Opcode = @import("opcode.zig").Opcode;
const Heap = @import("../memory/heap.zig").Heap;
const HeapObject = @import("../memory/value.zig").HeapObject;
const Function = @import("../memory/function.zig");
const Closure = @import("../memory/closure.zig");

pub const Assembler = struct {
    allocator: std.mem.Allocator,

    code: std.ArrayList(u8),

    heap: *Heap,
    constants: std.ArrayList(Value),

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

    pub fn add(self: *Assembler, dest: u8, lhs: u8, rhs: u8) !void {
        try self.emit(.ADD, dest, lhs, rhs);
    }

    pub fn compileToClosure(self: *Assembler, heap: *Heap) !*HeapObject {
        const func_obj = try Function.alloc(heap, 0, // Arity (params) - Default 0
            0, // Upvalues - Default 0
            self.code.items, self.constants.items);

        return try Closure.alloc(heap, func_obj, 0);
    }
};
