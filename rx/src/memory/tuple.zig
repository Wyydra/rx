const std = @import("std");
const Heap = @import("heap.zig");
const HeapError = @import("heap.zig").HeapError;
const HeapObject = @import("value.zig").HeapObject;
const Value = @import("value.zig").Value;
const Tuple = @import("tuple.zig");

pub fn alloc(allocator: std.mem.Allocator, items: []const Value) !*HeapObject {
    const payload_size = items.len * @sizeOf(Value);

    const obj = try HeapObject.allocate(allocator, .tuple, payload_size);

    const elements = Tuple.slice(obj);
    if (items.len > 0) {
        @memcpy(elements[0..items.len], items);
    }

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
