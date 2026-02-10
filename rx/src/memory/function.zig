const std = @import("std");
const Heap = @import("heap.zig").Heap;
const HeapObject = @import("value.zig").HeapObject;
const Value = @import("value.zig").Value;

const FunctionMeta = packed struct {
    arity: u8,
    upvalue_count: u8,
    const_count: u16,
    code_len: u32,
};

pub fn alloc(
    heap: *Heap, 
    arity: u8, 
    upvalue_count: u8, 
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

