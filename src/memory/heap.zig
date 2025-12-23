const std = @import("std");
const Value = @import("value.zig").Value;
const HeapObject = @import("value.zig").HeapObject;

pub const HeapError = error{
    OutOfMemory,
    InvalidSize,
};
pub const ObjectError = error{
    TypeMismatch,
    IndexOutOfBounds,
    InvalidUtf8, // For future string validation
    FrozenObject, // For future immutability checks
};

pub const Heap = struct {
    allocator: std.mem.Allocator,
    buffer: []u8,
    offset: usize,
    objects: std.ArrayList(*HeapObject),
    capacity: usize,

    pub const DEFAULT_SIZE: usize = 1024 * 1024; // 1MB

    pub fn init(allocator: std.mem.Allocator, size: usize) !Heap {
        const buffer = try allocator.alignedAlloc(u8, .@"8", size);
        errdefer allocator.free(buffer);

        var objects: std.ArrayList(*HeapObject) = .empty;
        errdefer objects.deinit(allocator);

        return Heap{
            .allocator = allocator,
            .buffer = buffer,
            .offset = 0,
            .objects = objects,
            .capacity = size,
        };
    }

    pub fn deinit(self: *Heap) void {
        self.objects.deinit(self.allocator);
        self.allocator.free(self.buffer);
    }

    pub fn reset(self: *Heap) void {
        self.offset = 0;
        self.objects.clearRetainingCapacity();
    }

    pub fn byteUsed(self: *const Heap) usize {
        return self.offset;
    }

    pub fn bytesAvailable(self: *const Heap) usize {
        return self.capacity - self.offset;
    }

    pub fn objectCount(self: *const Heap) usize {
        return self.objects.items.len;
    }

    fn alloc(self: *Heap, size: usize) !*HeapObject {
        const aligned_size = std.mem.alignForward(usize, size, 8);

        if (self.offset + aligned_size > self.capacity) {
            return error.OutOfMemory;
        }

        const ptr = @as(*HeapObject, @ptrCast(@alignCast(&self.buffer[self.offset])));

        std.debug.assert(@intFromPtr(ptr) % 8 == 0);

        self.offset += aligned_size;

        try self.objects.append(self.allocator, ptr);

        return ptr;
    }

    pub fn allocAndInitHeader(self: *Heap, kind: HeapObject.Kind, size: u48) !*HeapObject {
        const header_size = @sizeOf(HeapObject);

        // Calculate data size based on kind
        const data_size: usize = switch (kind) {
            .tuple => size * @sizeOf(Value),
            .string, .binary => size,
            .closure => @sizeOf(u64) + (size * @sizeOf(Value)),
            .float => @sizeOf(f64),
        };

        const total_size = header_size + data_size;
        const obj = try self.alloc(total_size);

        // Initialize header
        obj.* = HeapObject{
            .kind = kind,
            .flags = 0,
            .size = size,
        };

        return obj;
    }
};
