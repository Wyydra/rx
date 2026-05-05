const std = @import("std");
const Value = @import("value.zig").Value;
const HeapObject = @import("value.zig").HeapObject;

pub const HeapError = error{
    OutOfMemory,
    InvalidSize,
};

pub const Heap = struct {
    backing_allocator: std.mem.Allocator,

    from_space: []u8,
    to_space: []u8,

    offset: usize,
    capacity: usize, // size of semi space

    copy_offset: usize,
    scanned_offset: usize,

    strings: std.StringHashMap(*HeapObject),
    atoms: std.StringHashMap(*HeapObject),

    pub const DEFAULT_SIZE: usize = 1024 * 1024; // 1MB

    pub fn init(init_allocator: std.mem.Allocator, size: usize) !Heap {
        const from_buffer = try init_allocator.alignedAlloc(u8, .@"8", size);
        const to_buffer = try init_allocator.alignedAlloc(u8, .@"8", size);

        var strings = std.StringHashMap(*HeapObject).init(init_allocator);
        errdefer strings.deinit();

        var atoms = std.StringHashMap(*HeapObject).init(init_allocator);
        errdefer atoms.deinit();

        return Heap{
            .backing_allocator = init_allocator,
            .from_space = from_buffer,
            .to_space = to_buffer,
            .offset = 0,
            .copy_offset = 0,
            .scanned_offset = 0,
            .strings = strings,
            .atoms = atoms,
            .capacity = size,
        };
    }

    pub fn deinit(self: *Heap) void {
        self.strings.deinit();
        self.atoms.deinit();
        self.backing_allocator.free(self.from_space);
        self.backing_allocator.free(self.to_space);
    }

    pub fn reset(self: *Heap) void {
        self.offset = 0;
        self.strings.clearRetainingCapacity();
        self.atoms.clearRetainingCapacity();
    }

    pub fn allocUnsafe(self: *Heap, kind: HeapObject.Kind, payload_size: usize) !*HeapObject {
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

    pub fn allocator(self: *Heap) std.mem.Allocator {
        return std.mem.Allocator{
            .ptr = self,
            .vtable = &.{
                .alloc = allocFn,
                .resize = resizeFn,
                .remap = remapFn,
                .free = freeFn,
            },
        };
    }

    fn allocFn(ctx: *anyopaque, len: usize, ptr_align: std.mem.Alignment, ret_addr: usize) ?[*]u8 {
        _ = ret_addr;
        const self: *Heap = @ptrCast(@alignCast(ctx));

        // Note: Our allocUnsafe implementation ensures 8-byte alignment for all HeapObjects,
        // which matches the typical requirements for our structures.
        // We'll just enforce that requested alignment isn't bigger than what we can provide trivially.
        const align_val = ptr_align.toByteUnits();
        if (align_val > 8) return null;

        const aligned_size = std.mem.alignForward(usize, len, 8);

        if (self.offset + aligned_size > self.capacity) {
            return null;
        }

        const ptr_int = @intFromPtr(self.from_space.ptr) + self.offset;
        self.offset += aligned_size;

        return @ptrFromInt(ptr_int);
    }

    fn resizeFn(ctx: *anyopaque, buf: []u8, buf_align: std.mem.Alignment, new_len: usize, ret_addr: usize) bool {
        _ = ctx;
        _ = buf;
        _ = buf_align;
        _ = new_len;
        _ = ret_addr;
        return false;
    }

    fn remapFn(ctx: *anyopaque, memory: []u8, alignment: std.mem.Alignment, new_len: usize, ret_addr: usize) ?[*]u8 {
        _ = ctx;
        _ = memory;
        _ = alignment;
        _ = new_len;
        _ = ret_addr;
        return null;
    }

    fn freeFn(ctx: *anyopaque, buf: []u8, buf_align: std.mem.Alignment, ret_addr: usize) void {
        _ = ctx;
        _ = buf;
        _ = buf_align;
        _ = ret_addr;
    }

    pub fn createString(self: *Heap, chars: []const u8) !*HeapObject {
        const String = @import("string.zig");

        if (self.strings.get(chars)) |obj| {
            return obj;
        }

        const obj = try String.alloc(self.allocator(), .string, chars);

        const key_in_heap = String.getChars(obj);
        try self.strings.put(key_in_heap, obj);

        return obj;
    }

    pub fn createAtom(self: *Heap, chars: []const u8) !*HeapObject {
        const String = @import("string.zig");

        if (self.atoms.get(chars)) |obj| {
            return obj;
        }

        const obj = try String.alloc(self.allocator(), .atom, chars);

        const key_in_heap = String.getChars(obj);
        try self.atoms.put(key_in_heap, obj);

        return obj;
    }

    pub fn copyObject(self: *Heap, oldObj: *HeapObject) !*HeapObject {
        if (oldObj.isFrozen()) {
            return oldObj;
        }

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
        if (!value.isHeapAllocated()) return;

        const oldObj = value.asPtr() catch unreachable;
        const newObj = try self.copyObject(oldObj);
        if (value.is(.atom)) {
            value.* = Value.atom(newObj);
        } else {
            value.* = Value.pointer(newObj);
        }
    }

    pub fn scan(self: *Heap) !void {
        const Tuple = @import("tuple.zig");
        const Closure = @import("closure.zig");
        const Function = @import("function.zig");

        while (self.scanned_offset < self.copy_offset) {
            const currentObjPtr = @intFromPtr(self.to_space.ptr) + self.scanned_offset;
            const currentObj: *HeapObject = @ptrFromInt(currentObjPtr);

            switch (currentObj.kind) {
                .string, .atom => {},
                .closure => {
                    const env = Closure.getEnv(currentObj);
                    for (env) |*val| try self.copyValue(val);

                    const func = Closure.getFunction(currentObj);
                    const newFunc = try self.copyObject(func);
                    Closure.setFunction(currentObj, newFunc);
                },
                .function => {
                    const constsConst = Function.getConstants(currentObj);
                    const consts = @as([*]Value, @ptrCast(@constCast(constsConst.ptr)))[0..constsConst.len];
                    for (consts) |*val| try self.copyValue(val);
                },
                .tuple => {
                    const elems = Tuple.slice(currentObj);
                    for (elems) |*val| try self.copyValue(val);
                },
            }

            const totalSize = @sizeOf(HeapObject) + currentObj.size;
            self.scanned_offset += std.mem.alignForward(usize, totalSize, 8);
        }
    }

    /// Copy a Value from an external heap into THIS heap (for SEND message isolation).
    pub fn deepCopyValue(self: *Heap, src: Value) HeapError!Value {
        if (!src.is(.pointer) and !src.is(.atom)) return src; // Immediates safe

        const srcObj = src.asPtr() catch unreachable;
        const copy = try self.deepCopyObject(srcObj);

        if (src.is(.atom)) return Value.atom(copy);
        return Value.pointer(copy);
    }

    fn deepCopyObject(self: *Heap, src: *HeapObject) HeapError!*HeapObject {
        if (src.isFrozen()) return src;

        const String = @import("string.zig");
        const Tuple = @import("tuple.zig");

        switch (src.kind) {
            .string => return self.createString(String.getChars(src)),
            .atom => return self.createAtom(String.getChars(src)),
            .tuple => {
                const src_elems = Tuple.slice(src);
                const dst_obj = try self.allocUnsafe(.tuple, src_elems.len * @sizeOf(Value));
                const dst_elems = Tuple.slice(dst_obj);
                for (src_elems, 0..) |elem, i| {
                    dst_elems[i] = try self.deepCopyValue(elem);
                }
                return dst_obj;
            },
            .closure, .function => return src,
        }
    }
};
