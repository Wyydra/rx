const std = @import("std");
const Heap = @import("heap.zig").Heap;
const HeapObject = @import("value.zig").HeapObject;
const Value = @import("value.zig").Value;
const Instruction = @import("../bytecode/opcode.zig").Instruction;

const FunctionMeta = packed struct {
    arity: u8,
    upvalue_count: u8,
    max_regs: u8,
    _pad: u8 = 0,
    const_count: u16,
    code_len: u16, // u16 = max 65535 bytes ≈ 16K instructions per function
};

pub fn alloc(
    heap: *Heap,
    arity: u8,
    upvalue_count: u8,
    max_regs: u8,
    code: []const u8,
    constants: []const Value
) !*HeapObject {
    const meta_size = @sizeOf(FunctionMeta);
    const consts_size = constants.len * @sizeOf(Value);
    const code_size = code.len;

    const total_size = meta_size + consts_size + code_size;

    const obj = try heap.alloc(.function, @intCast(total_size));

    const payload_ptr = @as([*]u8, @ptrCast(obj)) + @sizeOf(HeapObject);

    const meta_ptr = @as(*FunctionMeta, @ptrCast(@alignCast(payload_ptr)));

    const consts_ptr = @as([*]Value, @ptrCast(@alignCast(payload_ptr + meta_size)));

    const code_ptr = payload_ptr + meta_size + consts_size;

    meta_ptr.* = FunctionMeta{
        .arity = arity,
        .upvalue_count = upvalue_count,
        .max_regs = max_regs,
        .const_count = @intCast(constants.len),
        .code_len = @intCast(code.len),
    };

    @memcpy(consts_ptr[0..constants.len], constants);

    @memcpy(code_ptr[0..code.len], code);

    return obj;
}

pub fn getMeta(obj: *const HeapObject) FunctionMeta {
    std.debug.assert(obj.kind == .function);
    const payload_ptr = @as([*]const u8, @ptrCast(obj)) + @sizeOf(HeapObject);
    const meta_ptr = @as(*const FunctionMeta, @ptrCast(@alignCast(payload_ptr)));
    return meta_ptr.*;
}

pub fn getMaxRegs(obj: *const HeapObject) u8 {
    return getMeta(obj).max_regs;
}

pub fn getConstants(obj: *const HeapObject) []const Value {
    const meta = getMeta(obj);
    const offset = @sizeOf(HeapObject) + @sizeOf(FunctionMeta);
    
    const ptr = @as([*]const Value, @ptrCast(@alignCast(@as([*]const u8, @ptrCast(obj)) + offset)));
    return ptr[0..meta.const_count];
}

pub fn getCode(obj: *const HeapObject) []const u8 {
    const meta = getMeta(obj);
    const offset = @sizeOf(HeapObject) + @sizeOf(FunctionMeta) + (meta.const_count * @sizeOf(Value));
    
    const ptr = @as([*]const u8, @ptrCast(obj)) + offset;
    return ptr[0..meta.code_len];
}

pub fn dump(obj: *const HeapObject, writer: *std.Io.Writer) std.Io.Writer.Error!void {
    std.debug.assert(obj.kind == .function);

    const meta = getMeta(obj);
    const constants = getConstants(obj);
    const code = getCode(obj);

    try writer.print("arity:         {d}\n", .{meta.arity});
    try writer.print("upvalue_count: {d}\n", .{meta.upvalue_count});

    try writer.print("\n-- constants ({d}) --\n", .{constants.len});
    for (constants, 0..) |c, i| {
        try writer.print("  K{d:>3}  {f}\n", .{ i, c });
    }

    try writer.print("\n-- bytecode ({d} bytes) --\n", .{code.len});
    var offset: usize = 0;
    var idx: usize = 0;
    while (offset + 4 <= code.len) : ({
        offset += 4;
        idx += 1;
    }) {
        const raw = std.mem.readInt(u32, code[offset..][0..4], .little);
        const instr = Instruction.decode(raw);
        try writer.print("  {d:>4}  {f}\n", .{ idx, instr });
    }
}
