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
        atom,
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
    pub fn payload(self: anytype, comptime T: type) [*]T {
        const addr = @intFromPtr(self) + @sizeOf(HeapObject);
        return @ptrFromInt(addr);
    }

    pub fn as(self: anytype, comptime kind: Kind) (if (@TypeOf(self) == *const HeapObject) *const HeapObject else *HeapObject) {
        std.debug.assert(self.kind == kind);
        return self;
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

pub const Value = packed struct(u64) {
    bits: u64,

    const TAG_BITS = 3;
    const TAG_MASK: u64 = 0b111;
    const PAYLOAD_MASK: u64 = ~TAG_MASK;

    pub const Tag = enum(u3) {
        pointer = 0b000,
        integer = 0b001,
        nil = 0b010,
        boolean = 0b011,
        atom = 0b100,
    };

    pub const Error = error{
        TypeError,
        DivisionByZero,
        IntegerOverflow,
    };

    // --- Constructors ---

    pub fn nil() Value {
        return .{ .bits = @intFromEnum(Tag.nil) };
    }

    pub fn boolean(b: bool) Value {
        const payload: u64 = if (b) 1 else 0;
        return .{ .bits = (payload << TAG_BITS) | @intFromEnum(Tag.boolean) };
    }

    pub fn integer(value: i64) Value {
        const payload: u64 = @bitCast(value);
        return .{ .bits = (payload << TAG_BITS) | @intFromEnum(Tag.integer) };
    }

    pub fn pointer(obj: anyptr) Value {
        const addr = @intFromPtr(obj);
        return .{ .bits = addr | @intFromEnum(Tag.pointer) };
    }

    pub fn atom(obj: anyptr) Value {
        const addr = @intFromPtr(obj);
        return .{ .bits = addr | @intFromEnum(Tag.atom) };
    }

    const anyptr = if (@import("builtin").zig_version.minor >= 12) *anyopaque else *HeapObject;

    // --- Checkers ---

    pub inline fn getTag(self: Value) Tag {
        return @enumFromInt(@as(u3, @truncate(self.bits & TAG_MASK)));
    }

    pub inline fn is(self: Value, tag: Tag) bool {
        return self.getTag() == tag;
    }

    pub fn isObj(self: Value, kind: HeapObject.Kind) bool {
        if (!self.is(.pointer) and !self.is(.atom)) return false;
        const obj = self.asPtr() catch return false;
        return obj.kind == kind;
    }

    // --- Extractors ---

    pub fn asInteger(self: Value) Error!i64 {
        if (!self.is(.integer)) return error.TypeError;
        const signed_bits: i64 = @bitCast(self.bits);
        return signed_bits >> TAG_BITS;
    }

    pub fn asBoolean(self: Value) Error!bool {
        if (!self.is(.boolean)) return error.TypeError;
        return (self.bits >> TAG_BITS) != 0;
    }

    pub fn asPtr(self: Value) Error!*HeapObject {
        if (!self.is(.pointer) and !self.is(.atom)) return error.TypeError;
        const addr = self.bits & PAYLOAD_MASK;
        return @ptrFromInt(@as(usize, @intCast(addr)));
    }

    // --- Arithmetic ---

    pub fn add(self: Value, other: Value) Error!Value {
        const a = try self.asInteger();
        const b = try other.asInteger();
        return Value.integer(a + b);
    }

    pub fn sub(self: Value, other: Value) Error!Value {
        const a = try self.asInteger();
        const b = try other.asInteger();
        return Value.integer(a - b);
    }

    pub fn mul(self: Value, other: Value) Error!Value {
        const a = try self.asInteger();
        const b = try other.asInteger();
        return Value.integer(a * b);
    }

    pub fn div(self: Value, other: Value) Error!Value {
        const a = try self.asInteger();
        const b = try other.asInteger();
        if (b == 0) return error.DivisionByZero;
        return Value.integer(@divTrunc(a, b));
    }

    // --- Comparison ---

    pub fn lt(self: Value, other: Value) Error!bool {
        return (try self.asInteger()) < (try other.asInteger());
    }

    pub fn gt(self: Value, other: Value) Error!bool {
        return (try self.asInteger()) > (try other.asInteger());
    }

    pub fn isClosure(self: Value) bool { return self.isObj(.closure); }
    pub fn isFunction(self: Value) bool { return self.isObj(.function); }
    pub fn isString(self: Value) bool { return self.isObj(.string); }

    pub fn asAtom(self: Value) Error![]const u8 {
        const obj = try self.asPtr();
        return String.getChars(obj);
    }

    pub fn asClosure(self: Value) Error!*HeapObject {
        if (!self.isClosure()) return error.TypeError;
        return self.asPtr();
    }

    pub fn asFunction(self: Value) Error!*HeapObject {
        if (!self.isFunction()) return error.TypeError;
        return self.asPtr();
    }

    pub fn asString(self: Value) Error![]const u8 {
        if (!self.isString()) return error.TypeError;
        const obj = try self.asPtr();
        return String.getChars(obj);
    }

    pub fn isHeapAllocated(self: Value) bool {
        return self.is(.pointer) or self.is(.atom);
    }

    pub fn equals(self: Value, other: Value) bool {
        if (self.bits == other.bits) return true;

        if (self.isString() and other.isString()) {
            const s1 = self.asString() catch unreachable;
            const s2 = other.asString() catch unreachable;
            return std.mem.eql(u8, s1, s2);
        }

        if (self.is(.atom) and other.is(.atom)) {
            const a1 = self.asAtom() catch unreachable;
            const a2 = other.asAtom() catch unreachable;
            return std.mem.eql(u8, a1, a2);
        }

        return false;
    }

    pub fn format(
        self: Value,
        writer: anytype,
    ) !void {
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
            .atom => {
                const s = self.asAtom() catch "???";
                try writer.print(":{s}", .{s});
            },
            .pointer => {
                const obj = self.asPtr() catch unreachable;
                switch (obj.kind) {
                    .string => {
                        const s = self.asString() catch unreachable;
                        try writer.print("\"{s}\"", .{s});
                    },
                    .atom => {
                        const s = String.getChars(obj);
                        try writer.print("#{s}", .{s});
                    },
                    .closure => try writer.writeAll("#<closure>"),
                    .function => try writer.writeAll("#<function>"),
                    .tuple => {
                        const elems = Tuple.slice(obj);
                        try writer.writeAll("[");
                        for (elems, 0..) |elem, i| {
                            try elem.format(writer);
                            if (i < elems.len - 1) try writer.writeAll(", ");
                        }
                        try writer.writeAll("]");
                    },
                }
            },
        }
    }
};

/// Deep-copy a Value into `allocator`-owned memory so it outlives the
/// sender's process heap. Closures/functions are shared as read-only pointers.
pub fn deepCopyAlloc(allocator: std.mem.Allocator, src: Value) error{OutOfMemory}!Value {
    if (!src.isHeapAllocated()) return src; // integers, booleans, nil are immediate — safe as-is
    const srcObj = src.asPtr() catch return src;
    const copied = try deepCopyObject(allocator, srcObj);
    // Preserve the atom tag so the copy is still recognized as an atom.
    return if (src.is(.atom)) Value.atom(copied) else Value.pointer(copied);
}

fn deepCopyObject(allocator: std.mem.Allocator, src: *HeapObject) error{OutOfMemory}!*HeapObject {
    switch (src.kind) {
        .string => return String.alloc(allocator, .string, String.getChars(src)),
        .atom => return String.alloc(allocator, .atom, String.getChars(src)),
        .function => return src, // Safe: Static code

        .closure => {
            // A closure must copy its captured environment!
            const src_env = Closure.getEnv(src);
            const func = Closure.getFunction(src);
            const dst = try Closure.alloc(allocator, func, @intCast(src_env.len));
            const dst_env = Closure.getEnv(dst);

            for (src_env, 0..) |elem, i| {
                dst_env[i] = deepCopyAlloc(allocator, elem) catch |err| {
                    // Note: freeObject handles recursive cleanup for tuples/closures
                    freeObject(allocator, dst);
                    return err;
                };
            }
            return dst;
        },

        .tuple => {
            const src_elems = Tuple.slice(src);
            const dst = try HeapObject.allocate(allocator, .tuple, src_elems.len * @sizeOf(Value));
            const dst_elems = Tuple.slice(dst);

            // Initialize with nil to ensure safe cleanup on failure
            @memset(dst_elems, Value.nil());

            for (src_elems, 0..) |elem, i| {
                dst_elems[i] = deepCopyAlloc(allocator, elem) catch |err| {
                    freeObject(allocator, dst); // Free the partial allocation!
                    return err;
                };
            }
            return dst;
        },
    }
}

/// Free a Value that was produced by `deepCopyAlloc`.
/// Must NOT be called on GC-managed values living inside a process Heap.
pub fn freeValue(allocator: std.mem.Allocator, v: Value) void {
    if (!v.isHeapAllocated()) return;
    const obj = v.asPtr() catch return;
    freeObject(allocator, obj);
}

fn freeObject(allocator: std.mem.Allocator, obj: *HeapObject) void {
    switch (obj.kind) {
        .tuple => for (Tuple.slice(obj)) |elem| freeValue(allocator, elem),
        .string, .atom => {}, // string/atom bytes are part of the same contiguous allocation, freed below
        .closure, .function => return, // shared, not owned by us
    }
    const total = @sizeOf(HeapObject) + obj.size;
    const bytes: []align(8) u8 = @as([*]align(8) u8, @ptrCast(obj))[0..total];
    allocator.free(bytes);
}
