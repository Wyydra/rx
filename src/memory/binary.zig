const std = @import("std");
const Heap = @import("heap.zig").Heap;
const HeapError = @import("heap.zig").HeapError;
const ObjectError = @import("heap.zig").ObjectError;
const HeapObject = @import("value.zig").HeapObject;
const Value = @import("value.zig").Value;

const FLAG_FROZEN: u8 = 0x04;

pub fn alloc(heap: *Heap, bytes: []const u8) HeapError!*HeapObject {
    const obj = try heap.allocAndInitHeader(.binary, @intCast(bytes.len));
    obj.flags |= FLAG_FROZEN; // Binaries are immutable

    if (bytes.len > 0) {
        const data_ptr = @as([*]u8, @ptrCast(obj)) + @sizeOf(HeapObject);
        @memcpy(data_ptr[0..bytes.len], bytes);
    }

    return obj;
}

pub fn getBytes(obj: *const HeapObject) []const u8 {
    std.debug.assert(obj.kind == .binary);
    if (obj.size == 0) {
        return &[_]u8{};
    }
    const data_ptr = @as([*]const u8, @ptrCast(obj)) + @sizeOf(HeapObject);
    return data_ptr[0..obj.size];
}

pub fn getLength(obj: *const HeapObject) u48 {
    std.debug.assert(obj.kind == .binary);
    return obj.size;
}

test "binary: basic allocation" {
    const Heap_module = @import("heap.zig");
    var heap = try Heap.init(std.testing.allocator, Heap_module.Heap.DEFAULT_SIZE);
    defer heap.deinit();

    const data = [_]u8{ 0x01, 0x02, 0x03, 0x04, 0x05 };
    const obj = try alloc(&heap, &data);
    try std.testing.expectEqual(HeapObject.Kind.binary, obj.kind);
    try std.testing.expectEqual(@as(u48, 5), obj.size);
    try std.testing.expectEqual(@as(u48, 5), getLength(obj));
    try std.testing.expect((obj.flags & FLAG_FROZEN) != 0);
    try std.testing.expectEqualSlices(u8, &data, getBytes(obj));
}

test "binary: empty binary" {
    const Heap_module = @import("heap.zig");
    var heap = try Heap.init(std.testing.allocator, Heap_module.Heap.DEFAULT_SIZE);
    defer heap.deinit();

    const obj = try alloc(&heap, &[_]u8{});
    try std.testing.expectEqual(@as(u48, 0), obj.size);
    try std.testing.expectEqual(@as(u48, 0), getLength(obj));
    try std.testing.expectEqualSlices(u8, &[_]u8{}, getBytes(obj));
    try std.testing.expect((obj.flags & FLAG_FROZEN) != 0);
}

test "binary: all byte values" {
    const Heap_module = @import("heap.zig");
    var heap = try Heap.init(std.testing.allocator, Heap_module.Heap.DEFAULT_SIZE);
    defer heap.deinit();

    var data: [256]u8 = undefined;
    for (0..256) |i| {
        data[i] = @intCast(i);
    }

    const obj = try alloc(&heap, &data);
    try std.testing.expectEqual(@as(u48, 256), getLength(obj));
    try std.testing.expectEqualSlices(u8, &data, getBytes(obj));
}

test "binary: large binary" {
    const Heap_module = @import("heap.zig");
    var heap = try Heap.init(std.testing.allocator, Heap_module.Heap.DEFAULT_SIZE);
    defer heap.deinit();

    var data: [4096]u8 = undefined;
    @memset(&data, 0xAB);

    const obj = try alloc(&heap, &data);
    try std.testing.expectEqual(@as(u48, 4096), getLength(obj));
    const bytes = getBytes(obj);
    try std.testing.expectEqual(@as(usize, 4096), bytes.len);
    for (bytes) |byte| {
        try std.testing.expectEqual(@as(u8, 0xAB), byte);
    }
}

test "binary: alignment verification" {
    const Heap_module = @import("heap.zig");
    var heap = try Heap.init(std.testing.allocator, Heap_module.Heap.DEFAULT_SIZE);
    defer heap.deinit();

    const data = [_]u8{ 0xFF, 0xEE, 0xDD };
    const obj = try alloc(&heap, &data);
    const addr = @intFromPtr(obj);
    try std.testing.expectEqual(@as(usize, 0), addr % 8);
}

test "binary: multiple allocations" {
    const Heap_module = @import("heap.zig");
    var heap = try Heap.init(std.testing.allocator, Heap_module.Heap.DEFAULT_SIZE);
    defer heap.deinit();

    const binaries = [_][]const u8{
        &[_]u8{ 0x00, 0x11 },
        &[_]u8{ 0x22, 0x33, 0x44 },
        &[_]u8{ 0x55, 0x66, 0x77, 0x88 },
        &[_]u8{0x99},
    };
    var objects: [4]*HeapObject = undefined;

    for (binaries, 0..) |bin, i| {
        objects[i] = try alloc(&heap, bin);
    }

    for (binaries, 0..) |expected, i| {
        try std.testing.expectEqualSlices(u8, expected, getBytes(objects[i]));
    }
}

test "binary: zero bytes" {
    const Heap_module = @import("heap.zig");
    var heap = try Heap.init(std.testing.allocator, Heap_module.Heap.DEFAULT_SIZE);
    defer heap.deinit();

    const data = [_]u8{ 0x00, 0x00, 0x00 };
    const obj = try alloc(&heap, &data);
    try std.testing.expectEqualSlices(u8, &data, getBytes(obj));
}
