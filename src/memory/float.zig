const std = @import("std");
const Heap = @import("heap.zig").Heap;
const HeapError = @import("heap.zig").HeapError;
const ObjectError = @import("heap.zig").ObjectError;
const HeapObject = @import("value.zig").HeapObject;
const Value = @import("value.zig").Value;

pub fn alloc(heap: *Heap, value: f64) HeapError!*HeapObject {
    const obj = try heap.allocAndInitHeader(.float, 1);
    const float_ptr = @as(*f64, @ptrCast(@alignCast(@as([*]u8, @ptrCast(obj)) + @sizeOf(HeapObject))));
    float_ptr.* = value;
    return obj;
}

pub fn getValue(obj: *const HeapObject) f64 {
    std.debug.assert(obj.kind == .float);
    const ptr = @as(*const f64, @ptrCast(@alignCast(@as([*]const u8, @ptrCast(obj)) + @sizeOf(HeapObject))));
    return ptr.*;
}

test "float: basic allocation and retrieval" {
    const Heap_module = @import("heap.zig");
    var heap = try Heap.init(std.testing.allocator, Heap_module.Heap.DEFAULT_SIZE);
    defer heap.deinit();

    const obj = try alloc(&heap, 3.14159);
    try std.testing.expectEqual(HeapObject.Kind.float, obj.kind);
    try std.testing.expectEqual(@as(u48, 1), obj.size);
    try std.testing.expectApproxEqAbs(3.14159, getValue(obj), 0.00001);
}

test "float: zero value" {
    const Heap_module = @import("heap.zig");
    var heap = try Heap.init(std.testing.allocator, Heap_module.Heap.DEFAULT_SIZE);
    defer heap.deinit();

    const obj = try alloc(&heap, 0.0);
    try std.testing.expectEqual(0.0, getValue(obj));
}

test "float: negative zero" {
    const Heap_module = @import("heap.zig");
    var heap = try Heap.init(std.testing.allocator, Heap_module.Heap.DEFAULT_SIZE);
    defer heap.deinit();

    const obj = try alloc(&heap, -0.0);
    const val = getValue(obj);
    try std.testing.expectEqual(-0.0, val);
    // Verify it's actually negative zero
    try std.testing.expect(std.math.signbit(val));
}

test "float: infinity" {
    const Heap_module = @import("heap.zig");
    var heap = try Heap.init(std.testing.allocator, Heap_module.Heap.DEFAULT_SIZE);
    defer heap.deinit();

    const pos_inf = std.math.inf(f64);
    const neg_inf = -std.math.inf(f64);

    const obj1 = try alloc(&heap, pos_inf);
    const obj2 = try alloc(&heap, neg_inf);

    try std.testing.expect(std.math.isInf(getValue(obj1)));
    try std.testing.expect(std.math.isInf(getValue(obj2)));
    try std.testing.expect(getValue(obj1) > 0);
    try std.testing.expect(getValue(obj2) < 0);
}

test "float: NaN" {
    const Heap_module = @import("heap.zig");
    var heap = try Heap.init(std.testing.allocator, Heap_module.Heap.DEFAULT_SIZE);
    defer heap.deinit();

    const nan = std.math.nan(f64);
    const obj = try alloc(&heap, nan);

    try std.testing.expect(std.math.isNan(getValue(obj)));
}

test "float: alignment verification" {
    const Heap_module = @import("heap.zig");
    var heap = try Heap.init(std.testing.allocator, Heap_module.Heap.DEFAULT_SIZE);
    defer heap.deinit();

    const obj = try alloc(&heap, 42.0);
    const addr = @intFromPtr(obj);
    try std.testing.expectEqual(@as(usize, 0), addr % 8);
}

test "float: multiple allocations" {
    const Heap_module = @import("heap.zig");
    var heap = try Heap.init(std.testing.allocator, Heap_module.Heap.DEFAULT_SIZE);
    defer heap.deinit();

    const values = [_]f64{ 1.1, 2.2, 3.3, 4.4, 5.5 };
    var objects: [5]*HeapObject = undefined;

    for (values, 0..) |val, i| {
        objects[i] = try alloc(&heap, val);
    }

    for (values, 0..) |expected, i| {
        try std.testing.expectApproxEqAbs(expected, getValue(objects[i]), 0.00001);
    }
}
