const std = @import("std");
const Heap = @import("heap.zig").Heap;
const HeapObject = @import("value.zig").HeapObject;

pub const StringMeta = struct {
    hash: u32,
    len: u32,
};

// Layout:
// 1. [HeapObject Header]
// 2. [StringMeta] (8 bytes)
// 3. [Bytes...] (N bytes)
// 4. [Null Terminator] (1 byte, optional but good for C-Interop)

pub fn alloc(heap: *Heap, chars: []const u8) !*HeapObject {
    if (heap.strings.get(chars)) |obj| {
        return obj;
    }

    const meta_size = @sizeOf(StringMeta);
    const total_size = meta_size + chars.len + 1;

    const obj = try heap.alloc(.string, @intCast(total_size));

    const payload_ptr = @as([*]u8, @ptrCast(obj)) + @sizeOf(HeapObject);
    const meta_ptr = @as(*StringMeta, @ptrCast(@alignCast(payload_ptr)));
    const chars_ptr = payload_ptr + meta_size;

    //TODO: ????
    var hash: u32 = 2166136261;
    for (chars) |c| {
        hash ^= c;
        hash *%= 16777619;
    }

    meta_ptr.* = StringMeta{
        .hash = hash,
        .len = @intCast(chars.len),
    };

    @memcpy(chars_ptr[0..chars.len], chars);
    chars_ptr[chars.len] = 0; // Null terminate

    const key_in_heap = chars_ptr[0..chars.len];
    try heap.strings.put(key_in_heap, obj);

    return obj;
}

pub fn getMeta(obj: *const HeapObject) *const StringMeta {
    std.debug.assert(obj.kind == .string);
    const payload_ptr = @as([*]const u8, @ptrCast(obj)) + @sizeOf(HeapObject);
    return @as(*const StringMeta, @ptrCast(@alignCast(payload_ptr)));
}

pub fn getChars(obj: *const HeapObject) []const u8 {
    const meta = getMeta(obj);
    const offset = @sizeOf(HeapObject) + @sizeOf(StringMeta);
    const ptr = @as([*]const u8, @ptrCast(obj)) + offset;
    return ptr[0..meta.len];
}

pub fn getHash(obj: *const HeapObject) u32 {
    return getMeta(obj).hash;
}
