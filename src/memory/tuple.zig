// [ HeapObject header: kind=tuple, size=element_count ]
// [ Value 0 ]
// [ Value 1 ]
// ...
// [ Value N-1 ]

pub fn alloc(heap: *Heap, element_count: u32) HeapError!*HeapObject {
    // Validate size fits in u48 (practically always true, but be safe)
    if (element_count > std.math.maxInt(u48)) {
        return error.InvalidSize;
    }
    // Use shared allocation helper
    const obj = try heap.allocAndInitHeader(.tuple, element_count);

    // Zero-initialize all element slots to nil for GC safety
    const elements = getElements(obj);
    for (elements) |*elem| {
        elem.* = Value.nil();
    }

    return obj;
}

pub fn getElements(obj: *HeapObject) []Value {
    std.debug.assert(obj.kind == .tuple);

    const data_ptr = @as([*]Value, @ptrCast(@alignCast(
                @as([*]u8, @ptrCast(obj)) + @sizeOf(HeapObject)
    )));

    return data_ptr[0..obj.size];
}

pub fn getElement(obj: *HeapObject, index: u32) Value {
    std.debug.assert(obj.kind == .tuple);
    std.debug.assert(index < obj.size);

    const elements = getElements(obj);
    return elements[index];
}

pub fn setElement(obj: *HeapObject, index: u32, value: Value) void {
    std.debug.assert(obj.kind == .tuple);
    std.debug.assert(index < obj.size);

    const elements = getElements(obj);
    elements[index] = value;
}

pub fn getLength(obj: *const HeapObject) u48 {
    std.debug.assert(obj.kind == .tuple);
    return obj.size;
}

const std = @import("std");
const Heap = @import("heap.zig").Heap;
const HeapError = @import("heap.zig").HeapError;
const ObjectError = @import("heap.zig").ObjectError;
const HeapObject = @import("value.zig").HeapObject;
const Value = @import("value.zig").Value;

const testing = std.testing;
test "tuple: allocate empty tuple" {
    var heap = try Heap.init(testing.allocator, Heap.DEFAULT_SIZE);
    defer heap.deinit();
    const obj = try alloc(&heap, 0);

    try testing.expectEqual(HeapObject.Kind.tuple, obj.kind);
    try testing.expectEqual(@as(u48, 0), obj.size);
    try testing.expectEqual(@as(u48, 0), getLength(obj));

    const elements = getElements(obj);
    try testing.expectEqual(@as(usize, 0), elements.len);
}
test "tuple: allocate and initialize to nil" {
    var heap = try Heap.init(testing.allocator, Heap.DEFAULT_SIZE);
    defer heap.deinit();
    const obj = try alloc(&heap, 3);

    try testing.expectEqual(HeapObject.Kind.tuple, obj.kind);
    try testing.expectEqual(@as(u48, 3), obj.size);

    const elements = getElements(obj);
    try testing.expectEqual(@as(usize, 3), elements.len);

    // All should be nil
    try testing.expect(elements[0].isNil());
    try testing.expect(elements[1].isNil());
    try testing.expect(elements[2].isNil());
}
test "tuple: set and get elements" {
    var heap = try Heap.init(testing.allocator, Heap.DEFAULT_SIZE);
    defer heap.deinit();
    const obj = try alloc(&heap, 3);

    // Set values
    setElement(obj, 0, Value.integer(42));
    setElement(obj, 1, Value.boolean(true));
    setElement(obj, 2, Value.pid(123));

    // Get values
    try testing.expectEqual(@as(i64, 42), try getElement(obj, 0).asInteger());
    try testing.expectEqual(true, try getElement(obj, 1).asBoolean());
    try testing.expectEqual(@as(u64, 123), try getElement(obj, 2).asPid());
}
test "tuple: nested tuples" {
    var heap = try Heap.init(testing.allocator, Heap.DEFAULT_SIZE);
    defer heap.deinit();
    const inner = try alloc(&heap, 2);
    setElement(inner, 0, Value.integer(1));
    setElement(inner, 1, Value.integer(2));

    const outer = try alloc(&heap, 2);
    setElement(outer, 0, Value.pointer(inner));
    setElement(outer, 1, Value.integer(3));

    // Access nested structure
    const inner_val = getElement(outer, 0);
    try testing.expect(inner_val.isPointer());

    const inner_obj = try inner_val.asPointer();
    try testing.expectEqual(HeapObject.Kind.tuple, inner_obj.kind);

    const inner_elements = getElements(inner_obj);
    try testing.expectEqual(@as(i64, 1), try inner_elements[0].asInteger());
    try testing.expectEqual(@as(i64, 2), try inner_elements[1].asInteger());
}
test "tuple: large tuple allocation" {
    var heap = try Heap.init(testing.allocator, Heap.DEFAULT_SIZE);
    defer heap.deinit();
    const large_count = 1000;
    const obj = try alloc(&heap, large_count);

    try testing.expectEqual(@as(u48, large_count), obj.size);

    // Set and verify all elements
    const elements = getElements(obj);
    for (elements, 0..) |*elem, i| {
        elem.* = Value.integer(@intCast(i));
    }

    for (elements, 0..) |elem, i| {
        try testing.expectEqual(@as(i64, @intCast(i)), try elem.asInteger());
    }
}
test "tuple: alignment verification" {
    var heap = try Heap.init(testing.allocator, Heap.DEFAULT_SIZE);
    defer heap.deinit();
    const obj = try alloc(&heap, 5);

    // Verify object is 8-byte aligned
    const obj_addr = @intFromPtr(obj);
    try testing.expect(obj_addr % 8 == 0);

    // Verify elements array is properly aligned
    const elements = getElements(obj);
    const elem_addr = @intFromPtr(elements.ptr);
    try testing.expect(elem_addr % 8 == 0);
}
