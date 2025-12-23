const std = @import("std");
const Heap = @import("heap.zig").Heap;
const HeapError = @import("heap.zig").HeapError;
const ObjectError = @import("heap.zig").ObjectError;
const HeapObject = @import("value.zig").HeapObject;
const Value = @import("value.zig").Value;

pub fn alloc(heap: *Heap, function_index: u64, env_count: u32) HeapError!*HeapObject {
    // Size field stores the environment count (number of Value slots)
    const obj = try heap.allocAndInitHeader(.closure, env_count);

    // Write function_index immediately after header
    const func_idx_ptr = @as(*u64, @ptrCast(@alignCast(@as([*]u8, @ptrCast(obj)) + @sizeOf(HeapObject))));
    func_idx_ptr.* = function_index;

    // Zero-initialize environment slots (GC-safe)
    if (env_count > 0) {
        const env_ptr = @as([*]Value, @ptrCast(@alignCast(@as([*]u8, @ptrCast(obj)) + @sizeOf(HeapObject) + @sizeOf(u64))));
        for (0..env_count) |i| {
            env_ptr[i] = Value.nil();
        }
    }

    return obj;
}

pub fn getFunctionIndex(obj: *const HeapObject) u64 {
    std.debug.assert(obj.kind == .closure);
    const func_idx_ptr = @as(*const u64, @ptrCast(@alignCast(@as([*]const u8, @ptrCast(obj)) + @sizeOf(HeapObject))));
    return func_idx_ptr.*;
}

pub fn getEnv(obj: *HeapObject) []Value {
    std.debug.assert(obj.kind == .closure);
    if (obj.size == 0) {
        return &[_]Value{};
    }
    const env_ptr = @as([*]Value, @ptrCast(@alignCast(@as([*]u8, @ptrCast(obj)) + @sizeOf(HeapObject) + @sizeOf(u64))));
    return env_ptr[0..obj.size];
}

pub fn getEnvValue(obj: *HeapObject, index: u32) Value {
    std.debug.assert(obj.kind == .closure);
    std.debug.assert(index < obj.size);
    const env = getEnv(obj);
    return env[index];
}

pub fn setEnvValue(obj: *HeapObject, index: u32, value: Value) void {
    std.debug.assert(obj.kind == .closure);
    std.debug.assert(index < obj.size);
    const env = getEnv(obj);
    env[index] = value;
}

pub fn getEnvCount(obj: *const HeapObject) u32 {
    std.debug.assert(obj.kind == .closure);
    return @intCast(obj.size);
}

test "closure: basic allocation" {
    const Heap_module = @import("heap.zig");
    var heap = try Heap.init(std.testing.allocator, Heap_module.Heap.DEFAULT_SIZE);
    defer heap.deinit();

    const obj = try alloc(&heap, 42, 3);
    try std.testing.expectEqual(HeapObject.Kind.closure, obj.kind);
    try std.testing.expectEqual(@as(u48, 3), obj.size);
    try std.testing.expectEqual(@as(u64, 42), getFunctionIndex(obj));
    try std.testing.expectEqual(@as(u32, 3), getEnvCount(obj));
}

test "closure: zero environment" {
    const Heap_module = @import("heap.zig");
    var heap = try Heap.init(std.testing.allocator, Heap_module.Heap.DEFAULT_SIZE);
    defer heap.deinit();

    const obj = try alloc(&heap, 123, 0);
    try std.testing.expectEqual(@as(u64, 123), getFunctionIndex(obj));
    try std.testing.expectEqual(@as(u32, 0), getEnvCount(obj));
    const env = getEnv(obj);
    try std.testing.expectEqual(@as(usize, 0), env.len);
}

test "closure: environment initialization" {
    const Heap_module = @import("heap.zig");
    var heap = try Heap.init(std.testing.allocator, Heap_module.Heap.DEFAULT_SIZE);
    defer heap.deinit();

    const obj = try alloc(&heap, 100, 5);

    // All environment slots should be initialized to nil
    for (0..5) |i| {
        const val = getEnvValue(obj, @intCast(i));
        try std.testing.expect(val.isNil());
    }
}

test "closure: set and get environment values" {
    const Heap_module = @import("heap.zig");
    var heap = try Heap.init(std.testing.allocator, Heap_module.Heap.DEFAULT_SIZE);
    defer heap.deinit();

    const obj = try alloc(&heap, 200, 3);

    setEnvValue(obj, 0, Value.integer(42));
    setEnvValue(obj, 1, Value.boolean(true));
    setEnvValue(obj, 2, Value.nil());

    try std.testing.expectEqual(@as(i64, 42), try getEnvValue(obj, 0).asInteger());
    try std.testing.expectEqual(true, try getEnvValue(obj, 1).asBoolean());
    try std.testing.expect(getEnvValue(obj, 2).isNil());
}

test "closure: environment with heap objects" {
    const Heap_module = @import("heap.zig");
    var heap = try Heap.init(std.testing.allocator, Heap_module.Heap.DEFAULT_SIZE);
    defer heap.deinit();

    const tuple = @import("tuple.zig");
    const tuple_obj = try tuple.alloc(&heap, 2);

    const closure_obj = try alloc(&heap, 300, 2);
    setEnvValue(closure_obj, 0, Value.pointer(tuple_obj));
    setEnvValue(closure_obj, 1, Value.integer(999));

    const retrieved = getEnvValue(closure_obj, 0);
    try std.testing.expect(!retrieved.isNil());
    const ptr = try retrieved.asPointer();
    try std.testing.expectEqual(HeapObject.Kind.tuple, ptr.kind);
}

test "closure: alignment verification" {
    const Heap_module = @import("heap.zig");
    var heap = try Heap.init(std.testing.allocator, Heap_module.Heap.DEFAULT_SIZE);
    defer heap.deinit();

    const obj = try alloc(&heap, 1, 1);
    const addr = @intFromPtr(obj);
    try std.testing.expectEqual(@as(usize, 0), addr % 8);
}

test "closure: multiple allocations" {
    const Heap_module = @import("heap.zig");
    var heap = try Heap.init(std.testing.allocator, Heap_module.Heap.DEFAULT_SIZE);
    defer heap.deinit();

    const configs = [_]struct { func_idx: u64, env_count: u32 }{
        .{ .func_idx = 10, .env_count = 0 },
        .{ .func_idx = 20, .env_count = 1 },
        .{ .func_idx = 30, .env_count = 5 },
        .{ .func_idx = 40, .env_count = 10 },
    };

    var objects: [4]*HeapObject = undefined;

    for (configs, 0..) |config, i| {
        objects[i] = try alloc(&heap, config.func_idx, config.env_count);
    }

    for (configs, 0..) |expected, i| {
        try std.testing.expectEqual(expected.func_idx, getFunctionIndex(objects[i]));
        try std.testing.expectEqual(expected.env_count, getEnvCount(objects[i]));
    }
}

test "closure: large environment" {
    const Heap_module = @import("heap.zig");
    var heap = try Heap.init(std.testing.allocator, Heap_module.Heap.DEFAULT_SIZE);
    defer heap.deinit();

    const obj = try alloc(&heap, 999, 100);
    try std.testing.expectEqual(@as(u32, 100), getEnvCount(obj));

    // Set and verify all environment values
    for (0..100) |i| {
        setEnvValue(obj, @intCast(i), Value.integer(@intCast(i * 10)));
    }

    for (0..100) |i| {
        const val = getEnvValue(obj, @intCast(i));
        try std.testing.expectEqual(@as(i64, @intCast(i * 10)), try val.asInteger());
    }
}
