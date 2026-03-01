const std = @import("std");
const Heap = @import("heap.zig");
const HeapError = @import("heap.zig").HeapError;
const HeapObject = @import("value.zig").HeapObject;
const Value = @import("value.zig").Value;

pub fn alloc(heap: *Heap, items: []const Value) HeapError!*HeapObject {
    const payload_size = items.len * @sizeOf(Value);
    const obj = try heap.allocUnsafe(.tuple, payload_size);
    @memcpy(items.ptr, items);
    return obj;
}

pub fn getCount(obj: *const HeapObject) u32 {
    std.debug.assert(obj.kind == .tuple);
    return @intCast(obj.size / @sizeOf(Value));
}

pub fn slice(obj: *HeapObject) []Value {
    std.debug.assert(obj.kind == .tuple);
    if (obj.size == 0) return &.{};
    const ptr = @as([*]Value, @ptrCast(@alignCast(@as([*]u8, @ptrCast(obj)) + @sizeOf(HeapObject))));
    return ptr[0..getCount(obj)];
}

pub fn getValue(obj: *const HeapObject, index: u32) Value {
    const elements = slice(obj);
    std.debug.assert(index < elements.len);
    return elements[index];
}
