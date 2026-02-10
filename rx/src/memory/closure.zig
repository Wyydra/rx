const std = @import("std");
const Heap = @import("heap.zig").Heap;
const HeapError = @import("heap.zig").HeapError;
const HeapObject = @import("value.zig").HeapObject;
const Value = @import("value.zig").Value;

// Layout:
// 1. [HeapObject Header] (8 bytes)
// 2. [Function Pointer]  (8 bytes) points to the ObjFunction
// 3. [Upvalues...]       (N * 8 bytes) captured variables

pub fn alloc(heap: *Heap, function: *HeapObject, env_count: u32) HeapError!*HeapObject {
    // strict check: ensure we are actually wrapping a Function object
    std.debug.assert(function.kind == .function);

    const payload_size = @sizeOf(u64) + (env_count * @sizeOf(Value));

    const obj = try heap.alloc(.closure, payload_size);

    const payload_ptr = @as([*]u8, @ptrCast(obj)) + @sizeOf(HeapObject);
    const func_slot = @as(* *HeapObject, @ptrCast(@alignCast(payload_ptr)));

    func_slot.* = function;

    if (env_count > 0) {
        const env_offset = @sizeOf(HeapObject) + @sizeOf(*HeapObject);
        const env_ptr = @as([*]Value, @ptrCast(@alignCast(@as([*]u8, @ptrCast(obj)) + env_offset)));

        for (0..env_count) |i| {
            env_ptr[i] = Value.nil();
        }
    }

    return obj;
}

pub fn getFunction(obj: *const HeapObject) *HeapObject {
    std.debug.assert(obj.kind == .closure);

    const payload_ptr = @as([*]const u8, @ptrCast(obj)) + @sizeOf(HeapObject);
    const func_slot = @as(*const *HeapObject, @ptrCast(@alignCast(payload_ptr)));

    return func_slot.*;
}

pub fn getEnv(obj: *HeapObject) []Value {
    std.debug.assert(obj.kind == .closure);
    if (obj.size == 0) {
        return &[_]Value{};
    }

    const env_offset = @sizeOf(HeapObject) + @sizeOf(*HeapObject);
    const env_ptr = @as([*]Value, @ptrCast(@alignCast(@as([*]u8, @ptrCast(obj)) + env_offset)));
    return env_ptr[0..obj.size];
}

pub fn getEnvValue(obj: *HeapObject, index: u32) Value {
    const env = getEnv(obj);
    std.debug.assert(index < env.len);
    return env[index];
}

pub fn setEnvValue(obj: *HeapObject, index: u32, value: Value) void {
    const env = getEnv(obj);
    std.debug.assert(index < env.len);
    env[index] = value;
}

pub fn getEnvCount(obj: *const HeapObject) u32 {
    std.debug.assert(obj.kind == .closure);
    return @intCast(obj.size);
}
