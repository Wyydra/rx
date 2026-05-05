const std = @import("std");
const HeapObject = @import("value.zig").HeapObject;
const Value = @import("value.zig").Value;

pub fn alloc(allocator: std.mem.Allocator, items: []const Value) !*HeapObject {
    const payload_size = items.len * @sizeOf(Value);
    const obj = try HeapObject.allocate(allocator, .tuple, payload_size);
    if (items.len > 0) {
        @memcpy(slice(obj)[0..items.len], items);
    }
    return obj;
}

pub fn getCount(obj: *const HeapObject) u32 {
    std.debug.assert(obj.kind == .tuple);
    return @intCast(obj.size / @sizeOf(Value));
}

pub fn slice(obj: *HeapObject) []Value {
    std.debug.assert(obj.kind == .tuple);
    return obj.payload(Value)[0..getCount(obj)];
}

pub fn getValue(obj: *const HeapObject, index: u32) Value {
    std.debug.assert(obj.kind == .tuple);
    std.debug.assert(index < getCount(obj));
    return obj.payload(Value)[index];
}
