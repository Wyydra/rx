const std = @import("std");
const String = @import("string.zig");
const Heap = @import("heap.zig").Heap;
const Closure = @import("closure.zig");
const Function = @import("function.zig");
const Tuple = @import("tuple.zig");

pub const HeapObject = packed struct {
    pub const Kind = enum(u8) {
        closure,
        function,
        string,
        tuple,
    };

    size: u48,
    flags: u8,
    kind: Kind,

    pub const GC_MARK: u8 = 1 << 0;
    pub const FROZEN: u8 = 1 << 1;
    pub const MOVED: u8 = 1 << 2;

    pub fn mark(self: *HeapObject) void {
        self.flags |= GC_MARK;
    }

    pub fn unmark(self: *HeapObject) void {
        self.flags &= ~GC_MARK;
    }

    pub fn moved(self: *HeapObject) void {
        self.flags |= MOVED;
    }

    pub fn freeze(self: *HeapObject) void {
        self.flags |= FROZEN;
    }

    pub fn isMarked(self: *const HeapObject) bool {
        return (self.flags & GC_MARK) != 0;
    }

    pub fn isFrozen(self: *const HeapObject) bool {
        return (self.flags & FROZEN) != 0;
    }
    pub fn isMoved(self: *const HeapObject) bool {
        return (self.flags & MOVED) != 0;
    }

    // Set the forwarding pointer for this object at start of payload
    pub fn setForwardingPointer(self: *HeapObject, ptr: *HeapObject) void {
        const payload_ptr: *usize = @ptrFromInt(@intFromPtr(self) + @sizeOf(HeapObject));
        payload_ptr.* = @intFromPtr(ptr);
    }

    // Get the forwarding pointer for this object at start of payload
    pub fn getForwardingPointer(self: *const HeapObject) *HeapObject {
        std.debug.assert(self.isMoved());
        const payload_ptr: *const usize = @ptrFromInt(@intFromPtr(self) + @sizeOf(HeapObject));
        const addr = payload_ptr.*;
        return @ptrFromInt(addr);
    }
    pub fn allocate(allocator: std.mem.Allocator, kind: Kind, payload_size: usize) !*HeapObject {
        const total_size = @sizeOf(HeapObject) + payload_size;
        const slice = try allocator.alignedAlloc(u8, .@"8", total_size);

        const obj: *HeapObject = @ptrCast(slice.ptr);
        obj.* = HeapObject{
            .kind = kind,
            .flags = 0,
            .size = @intCast(payload_size),
        };

        return obj;
    }
};

pub const Value = packed struct {
    bits: u64,

    const TAG_BITS = 3;
    const TAG_MASK: u64 = 0b111;
    const PAYLOAD_MASK: u64 = ~TAG_MASK;
    const PAYLOAD_BITS = 61;

    // Integer range: -(2^60) to (2^60 - 1)
    pub const INT_MIN: i64 = -(1 << 60);
    pub const INT_MAX: i64 = (1 << 60) - 1;

    pub const Tag = enum(u3) {
        pointer = 0b000,
        integer = 0b001,
        nil = 0b010,
        boolean = 0b011,
        // pid = 0b100,
        // reserved1 = 0b101,
        // reserved2 = 0b110,
        // reserved3 = 0b111,
    };

    pub fn nil() Value {
        return .{ .bits = @intFromEnum(Tag.nil) };
    }

    pub fn boolean(b: bool) Value {
        const payload: u64 = if (b) 1 else 0;
        return .{ .bits = (payload << TAG_BITS) | @intFromEnum(Tag.boolean) };
    }

    pub fn integer(value: i64) Value {
        std.debug.assert(value >= INT_MIN);
        std.debug.assert(value <= INT_MAX);

        const payload: u64 = @bitCast(value);
        return .{ .bits = (payload << TAG_BITS) | @intFromEnum(Tag.integer) };
    }

    pub fn pointer(obj: *HeapObject) Value {
        const addr = @intFromPtr(obj);
        std.debug.assert(addr & TAG_MASK == 0);
        return .{ .bits = addr };
    }

    pub fn string(heap: *Heap, s: []const u8) !Value {
        const obj = try String.alloc(heap, s);
        return Value.pointer(obj);
    }

    pub inline fn getTag(self: Value) Tag {
        return @enumFromInt(@as(u3, @truncate(self.bits & TAG_MASK)));
    }

    pub inline fn isNil(self: Value) bool {
        return self.getTag() == .nil;
    }
    pub inline fn isBoolean(self: Value) bool {
        return self.getTag() == .boolean;
    }
    pub inline fn isInteger(self: Value) bool {
        return self.getTag() == .integer;
    }
    pub inline fn isPointer(self: Value) bool {
        return self.getTag() == .pointer;
    }

    pub fn isClosure(self: Value) bool {
        if (!self.isPointer()) return false;
        const obj = self.asPointer() catch return false;
        return obj.kind == .closure;
    }

    pub fn isFunction(self: Value) bool {
        if (!self.isPointer()) return false;
        const ptr = self.asPointer() catch return false;
        return ptr.kind == .function;
    }

    pub fn isString(self: Value) bool {
        if (!self.isPointer()) return false;
        const obj = self.asPointer() catch return false;
        return obj.kind == .string;
    }

    pub fn asBoolean(self: Value) !bool {
        if (self.getTag() != .boolean) return error.TypeError;
        const payload = self.bits >> TAG_BITS;
        return payload != 0;
    }
    pub fn asInteger(self: Value) !i64 {
        if (self.getTag() != .integer) return error.TypeError;
        // Cast to signed, then arithmetic shift right to preserve sign
        const signed_bits: i64 = @bitCast(self.bits);
        return signed_bits >> TAG_BITS;
    }

    pub fn asPointer(self: Value) !*HeapObject {
        if (self.getTag() != .pointer) return error.TypeError;
        const addr = self.bits & PAYLOAD_MASK;
        const ptr: *HeapObject = @ptrFromInt(@as(usize, @intCast(addr)));
        std.debug.assert(@intFromPtr(ptr) % 8 == 0);
        return ptr;
    }

    pub fn asClosure(self: Value) !*HeapObject {
        if (!self.isClosure()) return error.TypeError;
        return self.asPointer();
    }

    pub fn asFunction(self: Value) !*HeapObject {
        if (!self.isFunction()) return error.TypeError;
        return self.asPointer();
    }

    pub fn asString(self: Value) ![]const u8 {
        if (!self.isString()) return error.TypeError;
        const obj = try self.asPointer();
        return String.getChars(obj);
    }

    pub fn equals(self: Value, other: Value) bool {
        if (self.bits == other.bits) return true;

        if (self.isString() and other.isString()) {
            // Since strings are interned, pointer equality is sufficient!
            const obj1 = self.asPointer() catch unreachable;
            const obj2 = other.asPointer() catch unreachable;
            return obj1 == obj2;
        }

        if (self.getTag() != other.getTag()) return false;
        // For now, only bit-equality
        // TODO: add deep equality for heap objects
        return false;
    }

    pub fn format(
        self: @This(),
        writer: *std.Io.Writer,
    ) std.Io.Writer.Error!void {
        switch (self.getTag()) {
            .nil => try writer.writeAll("nil"),
            .boolean => {
                const b = self.asBoolean() catch unreachable;
                try writer.writeAll(if (b) "true" else "false");
            },
            .integer => {
                const i = self.asInteger() catch unreachable;
                try writer.print("{d}", .{i});
            },
            .pointer => {
                const obj = self.asPointer() catch unreachable;
                switch (obj.kind) {
                    .string => {
                        const s = self.asString() catch unreachable;
                        try writer.print("\"{s}\"", .{s});
                    },
                    .closure => try writer.writeAll("#<closure>"),
                    .function => try writer.writeAll("#<function>"),
                    .tuple => {
                        const elems = Tuple.slice(obj);
                        try writer.writeAll("(tuple");
                        for (elems) |elem| {
                            try writer.writeAll(" ");
                            try elem.format(writer);
                        }
                        try writer.writeAll(")");
                    },
                }
            },
        }
    }
};

/// Deep-copy a Value into `allocator`-owned memory so it outlives the
/// sender's process heap. Closures/functions are shared as read-only pointers.
pub fn deepCopyAlloc(allocator: std.mem.Allocator, src: Value) error{OutOfMemory}!Value {
    if (!src.isPointer()) return src; // integers, booleans, nil are immediate — safe as-is
    const srcObj = src.asPointer() catch return src; // not a pointer? return as-is
    return Value.pointer(try deepCopyObject(allocator, srcObj));
}

fn deepCopyObject(allocator: std.mem.Allocator, src: *HeapObject) error{OutOfMemory}!*HeapObject {
    switch (src.kind) {
        .string => return String.alloc(allocator, String.getChars(src)),
        .tuple => {
            const src_elems = Tuple.slice(src);
            const dst = try HeapObject.allocate(allocator, .tuple, src_elems.len * @sizeOf(Value));
            const dst_elems = Tuple.slice(dst);
            for (src_elems, 0..) |elem, i| dst_elems[i] = try deepCopyAlloc(allocator, elem);
            return dst;
        },
        // Closures/functions hold code pointers valid for all processes — share as read-only.
        .closure, .function => return src,
    }
}

/// Free a Value that was produced by `deepCopyAlloc`.
/// Must NOT be called on GC-managed values living inside a process Heap.
pub fn freeValue(allocator: std.mem.Allocator, v: Value) void {
    if (!v.isPointer()) return;
    const obj = v.asPointer() catch return;
    freeObject(allocator, obj);
}

fn freeObject(allocator: std.mem.Allocator, obj: *HeapObject) void {
    switch (obj.kind) {
        .tuple => for (Tuple.slice(obj)) |elem| freeValue(allocator, elem),
        .string => {}, // string bytes are part of the same contiguous allocation, freed below
        .closure, .function => return, // shared, not owned by us
    }
    const total = @sizeOf(HeapObject) + obj.size;
    const bytes: []align(8) u8 = @as([*]align(8) u8, @ptrCast(obj))[0..total];
    allocator.free(bytes);
}
