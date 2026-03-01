const std = @import("std");
const Value = @import("value.zig").Value;
const HeapObject = @import("value.zig").HeapObject;

pub const HeapError = error{
    OutOfMemory,
    InvalidSize,
};

pub const Heap = struct {
    allocator: std.mem.Allocator,

    from_space: []u8,
    to_space: []u8,

    offset: usize,
    capacity: usize, // size of semi space

    copy_offset: usize,
    scanned_offset: usize,

    strings: std.StringHashMap(*HeapObject),

    pub const DEFAULT_SIZE: usize = 1024 * 1024; // 1MB

    pub fn init(allocator: std.mem.Allocator, size: usize) !Heap {
        const from_buffer = try allocator.alignedAlloc(u8, .@"8", size);
        const to_buffer = try allocator.alignedAlloc(u8, .@"8", size);

        var strings = std.StringHashMap(*HeapObject).init(allocator);
        errdefer strings.deinit();

        return Heap{
            .allocator = allocator,
            .from_space = from_buffer,
            .to_space = to_buffer,
            .offset = 0,
            .copy_offset = 0,
            .scanned_offset = 0,
            .strings = strings,
            .capacity = size,
        };
    }

    pub fn deinit(self: *Heap) void {
        self.strings.deinit();
        self.allocator.free(self.from_space);
        self.allocator.free(self.to_space);
    }

    pub fn reset(self: *Heap) void {
        self.offset = 0;
        self.strings.clearRetainingCapacity();
    }

    pub fn alloc(self: *Heap, kind: HeapObject.Kind, payload_size: usize) !*HeapObject {
        const total_size = @sizeOf(HeapObject) + payload_size;
        const aligned_size = std.mem.alignForward(usize, total_size, 8);

        if (self.offset + aligned_size > self.capacity) {
            return error.OutOfMemory;
        }

        const ptr_int = @intFromPtr(self.from_space.ptr) + self.offset;
        const obj: *HeapObject = @ptrFromInt(ptr_int);

        self.offset += aligned_size;

        obj.* = HeapObject{
            .kind = kind,
            .flags = 0,
            .size = @intCast(payload_size),
        };

        return obj;
    }

    pub fn copyObject(self: *Heap, oldObj: *HeapObject) !*HeapObject {
        if (oldObj.isMoved()) {
            return oldObj.getForwardingPointer();
        }

        const total_size = @sizeOf(HeapObject) + oldObj.size;
        const aligned_size = std.mem.alignForward(usize, total_size, 8);

        const destPtrInt = @intFromPtr(self.to_space.ptr) + self.copy_offset;
        const newObj: *HeapObject = @ptrFromInt(destPtrInt);

        const srcSlice = @as([*]u8, @ptrCast(oldObj))[0..aligned_size];
        const destSlice = @as([*]u8, @ptrCast(newObj))[0..aligned_size];
        @memcpy(destSlice, srcSlice);

        self.copy_offset += aligned_size;

        oldObj.moved();
        oldObj.setForwardingPointer(newObj);

        return newObj;
    }

    pub fn copyValue(self: *Heap, value: *Value) !void {
        if (!value.isPointer()) return;

        const oldObj = value.asPointer() catch unreachable;
        const newObj = try self.copyObject(oldObj);
        value.* = Value.pointer(newObj);
    }
};
