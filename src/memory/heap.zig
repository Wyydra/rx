const std = @import("std");
const Value = @import("value.zig").Value;
const HeapObject = @import("value.zig").HeapObject;

pub const HeapError = error{
    OutOfMemory,
    InvalidSize,
};

pub const Heap = struct {
    allocator: std.mem.Allocator,
    buffer: []u8,
    offset: usize,
    objects: std.ArrayList(*HeapObject),
    strings: std.StringHashMap(*HeapObject),
    capacity: usize,

    pub const DEFAULT_SIZE: usize = 1024 * 1024; // 1MB

    pub fn init(allocator: std.mem.Allocator, size: usize) !Heap {
        const buffer = try allocator.alignedAlloc(u8, .@"8", size);
        errdefer allocator.free(buffer);

        var objects: std.ArrayList(*HeapObject) = .empty;
        errdefer objects.deinit(allocator);

        var strings = std.StringHashMap(*HeapObject).init(allocator);
        errdefer strings.deinit();

        return Heap{
            .allocator = allocator,
            .buffer = buffer,
            .offset = 0,
            .objects = objects,
            .strings = strings,
            .capacity = size,
        };
    }

    pub fn deinit(self: *Heap) void {
        self.objects.deinit(self.allocator);
        self.strings.deinit();
        self.allocator.free(self.buffer);
    }

    pub fn reset(self: *Heap) void {
        self.offset = 0;
        self.objects.clearRetainingCapacity();
        self.strings.clearRetainingCapacity();
    }

    pub fn alloc(self: *Heap, kind: HeapObject.Kind, payload_size: usize) !*HeapObject {
        const total_size = @sizeOf(HeapObject) + payload_size;

        const aligned_size = std.mem.alignForward(usize, total_size, 8);

        if (self.offset + aligned_size > self.buffer.len) {
            return error.OutOfMemory;
        }

        const ptr_int = @intFromPtr(self.buffer.ptr) + self.offset;
        const obj: *HeapObject = @ptrFromInt(ptr_int);

        self.offset += aligned_size;

        obj.* = HeapObject{
            .kind = kind,
            .flags = 0,
            .size = @intCast(payload_size),
        };

        try self.objects.append(self.allocator, obj);

        return obj;
    }
};
