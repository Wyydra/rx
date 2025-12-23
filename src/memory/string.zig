const std = @import("std");
const Heap = @import("heap.zig").Heap;
const HeapError = @import("heap.zig").HeapError;
const ObjectError = @import("heap.zig").ObjectError;
const HeapObject = @import("value.zig").HeapObject;
const Value = @import("value.zig").Value;

const FLAG_FROZEN: u8 = 0x04;

pub fn alloc(heap: *Heap, bytes: []const u8) HeapError!*HeapObject {
    const obj = try heap.allocAndInitHeader(.string, @intCast(bytes.len));
    obj.flags |= FLAG_FROZEN; // Strings are immutable

    if (bytes.len > 0) {
        const data_ptr = @as([*]u8, @ptrCast(obj)) + @sizeOf(HeapObject);
        @memcpy(data_ptr[0..bytes.len], bytes);
    }

    return obj;
}

pub fn getBytes(obj: *const HeapObject) []const u8 {
    std.debug.assert(obj.kind == .string);
    if (obj.size == 0) {
        return &[_]u8{};
    }
    const data_ptr = @as([*]const u8, @ptrCast(obj)) + @sizeOf(HeapObject);
    return data_ptr[0..obj.size];
}

pub fn getLength(obj: *const HeapObject) u48 {
    std.debug.assert(obj.kind == .string);
    return obj.size;
}

test "string: basic allocation" {
    const Heap_module = @import("heap.zig");
    var heap = try Heap.init(std.testing.allocator, Heap_module.Heap.DEFAULT_SIZE);
    defer heap.deinit();

    const obj = try alloc(&heap, "hello");
    try std.testing.expectEqual(HeapObject.Kind.string, obj.kind);
    try std.testing.expectEqual(@as(u48, 5), obj.size);
    try std.testing.expectEqual(@as(u48, 5), getLength(obj));
    try std.testing.expect((obj.flags & FLAG_FROZEN) != 0);
    try std.testing.expectEqualStrings("hello", getBytes(obj));
}

test "string: empty string" {
    const Heap_module = @import("heap.zig");
    var heap = try Heap.init(std.testing.allocator, Heap_module.Heap.DEFAULT_SIZE);
    defer heap.deinit();

    const obj = try alloc(&heap, "");
    try std.testing.expectEqual(@as(u48, 0), obj.size);
    try std.testing.expectEqual(@as(u48, 0), getLength(obj));
    try std.testing.expectEqualStrings("", getBytes(obj));
    try std.testing.expect((obj.flags & FLAG_FROZEN) != 0);
}

test "string: UTF-8 content" {
    const Heap_module = @import("heap.zig");
    var heap = try Heap.init(std.testing.allocator, Heap_module.Heap.DEFAULT_SIZE);
    defer heap.deinit();

    const obj = try alloc(&heap, "Hello, 世界! 🌍");
    const bytes = getBytes(obj);
    try std.testing.expectEqualStrings("Hello, 世界! 🌍", bytes);
    // Byte length, not character count
    try std.testing.expectEqual(@as(u48, 19), getLength(obj));
}

test "string: long string" {
    const Heap_module = @import("heap.zig");
    var heap = try Heap.init(std.testing.allocator, Heap_module.Heap.DEFAULT_SIZE);
    defer heap.deinit();

    const long_str = "a" ** 1000;
    const obj = try alloc(&heap, long_str);
    try std.testing.expectEqual(@as(u48, 1000), getLength(obj));
    try std.testing.expectEqualStrings(long_str, getBytes(obj));
}

test "string: alignment verification" {
    const Heap_module = @import("heap.zig");
    var heap = try Heap.init(std.testing.allocator, Heap_module.Heap.DEFAULT_SIZE);
    defer heap.deinit();

    const obj = try alloc(&heap, "test");
    const addr = @intFromPtr(obj);
    try std.testing.expectEqual(@as(usize, 0), addr % 8);
}

test "string: multiple allocations" {
    const Heap_module = @import("heap.zig");
    var heap = try Heap.init(std.testing.allocator, Heap_module.Heap.DEFAULT_SIZE);
    defer heap.deinit();

    const strings = [_][]const u8{ "first", "second", "third", "fourth" };
    var objects: [4]*HeapObject = undefined;

    for (strings, 0..) |str, i| {
        objects[i] = try alloc(&heap, str);
    }

    for (strings, 0..) |expected, i| {
        try std.testing.expectEqualStrings(expected, getBytes(objects[i]));
    }
}

test "string: special characters" {
    const Heap_module = @import("heap.zig");
    var heap = try Heap.init(std.testing.allocator, Heap_module.Heap.DEFAULT_SIZE);
    defer heap.deinit();

    const obj = try alloc(&heap, "line1\nline2\ttab\r\n");
    try std.testing.expectEqualStrings("line1\nline2\ttab\r\n", getBytes(obj));
}
