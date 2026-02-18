const std = @import("std");
const String = @import("string.zig");
const Heap = @import("heap.zig").Heap;
const Closure = @import("closure.zig");
const Function = @import("function.zig");

pub const HeapObject = struct {
    pub const Kind = enum(u8) {
        closure,
        function,
        string,
    };

    size: u48,
    flags: u8,
    kind: Kind,

    pub const GC_MARK: u8 = 1 << 0;
    pub const PINNED: u8 = 1 << 1;
    pub const FROZEN: u8 = 1 << 2;

    pub fn isMarked(self: *const HeapObject) bool {
        return (self.flags & GC_MARK) != 0;
    }
    pub fn mark(self: *HeapObject) void {
        self.flags |= GC_MARK;
    }

    pub fn unmark(self: *HeapObject) void {
        self.flags &= ~GC_MARK;
    }
    pub fn isPinned(self: *const HeapObject) bool {
        return (self.flags & PINNED) != 0;
    }
    pub fn isFrozen(self: *const HeapObject) bool {
        return (self.flags & FROZEN) != 0;
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
                    .closure => {
                        const count = Closure.getEnvCount(obj);
                        const func = Closure.getFunction(obj);
                        try writer.print("<Closure env_count={d} func=0x{x}>", .{ count, @intFromPtr(func) });
                    },
                    .function => {
                        const meta = Function.getMeta(obj);
                        try writer.print("<Function arity={d}>", .{meta.arity});
                    },
                }

            },
        }
    }
};
