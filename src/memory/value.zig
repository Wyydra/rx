pub const HeapObject = packed struct {
    pub const Kind = enum(u8) {
        float,
        string,
        tuple,
        closure,
        binary,
    };

    size: u48,
    flags: u8,
    kind: Kind,

    // Flags bit layout:
    // Bit 0: GC mark bit
    // Bit 1: Pinned (don't move/collect)
    // Bit 2: Frozen (immutable)
    // Bits 3-7: Reserved
    pub const FLAG_GC_MARK: u8 = 1 << 0;
    pub const FLAG_PINNED: u8 = 1 << 1;
    pub const FLAG_FROZEN: u8 = 1 << 2;
    pub fn isMarked(self: *const HeapObject) bool {
        return (self.flags & FLAG_GC_MARK) != 0;
    }
    pub fn mark(self: *HeapObject) void {
        self.flags |= FLAG_GC_MARK;
    }
    pub fn unmark(self: *HeapObject) void {
        self.flags &= ~FLAG_GC_MARK;
    }
    pub fn isPinned(self: *const HeapObject) bool {
        return (self.flags & FLAG_PINNED) != 0;
    }
    pub fn isFrozen(self: *const HeapObject) bool {
        return (self.flags & FLAG_FROZEN) != 0;
    }
};

pub const Value = packed struct {
    bits: u64,

    const Self = @This();

    const TAG_BITS = 3;
    const TAG_MASK: u64 = 0b111;
    const PAYLOAD_MASK: u64 = ~TAG_MASK;
    const PAYLOAD_BITS = 61;

    // Integer range: -(2^60) to (2^60 - 1)
    pub const INT_MIN: i64 = -(1 << 60);
    pub const INT_MAX: i64 = (1 << 60) - 1;

    pub const PID_MAX: u64 = (1 << 61) - 1;

    pub const Tag = enum(u3) {
        pointer = 0b000, // Must be 000 for aligned pointers
        integer = 0b001,
        nil = 0b010,
        boolean = 0b011,
        pid = 0b100,
        reserved1 = 0b101,
        reserved2 = 0b110,
        reserved3 = 0b111,
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

    pub fn pid(id: u64) Value {
        std.debug.assert(id <= PID_MAX);

        return .{ .bits = (id << TAG_BITS) | @intFromEnum(Tag.pid) };
    }

    pub fn pointer(obj: *HeapObject) Value {
        const addr = @intFromPtr(obj);
        std.debug.assert(addr & TAG_MASK == 0);
        return .{ .bits = addr };
    }

    pub inline fn getTag(self: Self) Tag {
        return @enumFromInt(@as(u3, @truncate(self.bits & TAG_MASK)));
    }

    pub inline fn isNil(self: Self) bool {
        return self.getTag() == .nil;
    }

    pub inline fn isBoolean(self: Self) bool {
        return self.getTag() == .boolean;
    }
    pub inline fn isInteger(self: Self) bool {
        return self.getTag() == .integer;
    }
    pub inline fn isPointer(self: Self) bool {
        return self.getTag() == .pointer;
    }
    pub inline fn isPid(self: Self) bool {
        return self.getTag() == .pid;
    }

    pub fn isFloat(self: Self) bool {
        if (!self.isPointer()) return false;
        const obj = self.asPointer() catch return false;
        return obj.kind == .float;
    }
    pub fn isString(self: Self) bool {
        if (!self.isPointer()) return false;
        const obj = self.asPointer() catch return false;
        return obj.kind == .string;
    }
    pub fn isTuple(self: Self) bool {
        if (!self.isPointer()) return false;
        const obj = self.asPointer() catch return false;
        return obj.kind == .tuple;
    }
    pub fn isClosure(self: Self) bool {
        if (!self.isPointer()) return false;
        const obj = self.asPointer() catch return false;
        return obj.kind == .closure;
    }
    pub fn isBinary(self: Self) bool {
        if (!self.isPointer()) return false;
        const obj = self.asPointer() catch return false;
        return obj.kind == .binary;
    }
    pub fn isNumber(self: Self) bool {
        return self.isInteger() or self.isFloat();
    }

    pub fn asBoolean(self: Self) !bool {
        if (self.getTag() != .boolean) return error.TypeError;
        const payload = self.bits >> TAG_BITS;
        return payload != 0;
    }
    pub fn asInteger(self: Self) !i64 {
        if (self.getTag() != .integer) return error.TypeError;
        // Cast to signed, then arithmetic shift right to preserve sign
        const signed_bits: i64 = @bitCast(self.bits);
        return signed_bits >> TAG_BITS;
    }
    pub fn asPid(self: Self) !u64 {
        if (self.getTag() != .pid) return error.TypeError;
        return self.bits >> TAG_BITS;
    }
    pub fn asPointer(self: Self) !*HeapObject {
        if (self.getTag() != .pointer) return error.TypeError;
        const addr = self.bits & PAYLOAD_MASK;
        const ptr: *HeapObject = @ptrFromInt(addr);
        // Verify alignment in debug mode
        std.debug.assert(@intFromPtr(ptr) % 8 == 0);
        return ptr;
    }

    pub fn equals(self: Self, other: Self) bool {
        // Fast path: bit-identical values
        if (self.bits == other.bits) return true;
        // Different tags = not equal
        if (self.getTag() != other.getTag()) return false;
        // For now, only bit-equality
        // TODO: add deep equality for heap objects (string contents, tuple elements)
        return false;
    }
    pub fn hash(self: Self) u64 {
        // Simple hash: use bits directly for immediate values
        // For pointers, this hashes the address (reference equality)
        // TODO: add content-based hashing for heap objects
        return self.bits;
    }

    pub fn format(
        self: Self,
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
            .pid => {
                const p = self.asPid() catch unreachable;
                try writer.print("pid<{d}>", .{p});
            },
            .pointer => {
                const obj = self.asPointer() catch unreachable;
                try writer.print("{s}<{*}>", .{ @tagName(obj.kind), obj });
                // TODO: pretty-print contents based on heap object type
            },
            else => try writer.writeAll("<reserved>"),
        }
    }
    /// Returns true if value is truthy (not nil and not false)
    pub fn isTruthy(self: Self) bool {
        if (self.isNil()) return false;
        if (self.isBoolean()) {
            return (self.asBoolean() catch false);
        }
        return true; // Everything else is truthy
    }
    /// Returns false if value is falsy (nil or false)
    pub fn isFalsy(self: Self) bool {
        return !self.isTruthy();
    }
};

const std = @import("std");

const testing = std.testing;
const expect = testing.expect;
const expectEqual = testing.expectEqual;
const expectError = testing.expectError;

test "Value: nil construction and type checking" {
    const v = Value.nil();

    try expect(v.isNil());
    try expect(!v.isBoolean());
    try expect(!v.isInteger());
    try expect(!v.isPointer());
    try expect(!v.isPid());

    try expectEqual(Value.Tag.nil, v.getTag());
}
test "Value: boolean construction and extraction" {
    const t = Value.boolean(true);
    const f = Value.boolean(false);

    // Type checking
    try expect(t.isBoolean());
    try expect(f.isBoolean());
    try expect(!t.isNil());
    try expect(!f.isInteger());

    // Extraction
    try expectEqual(true, try t.asBoolean());
    try expectEqual(false, try f.asBoolean());

    // Type error on wrong extraction
    try expectError(error.TypeError, t.asInteger());
    try expectError(error.TypeError, f.asPid());

    // Truthiness
    try expect(t.isTruthy());
    try expect(f.isFalsy());
}
test "Value: integer construction, extraction, and sign extension" {
    // Positive integers
    const pos = Value.integer(42);
    try expect(pos.isInteger());
    try expectEqual(@as(i64, 42), try pos.asInteger());

    // Zero
    const zero = Value.integer(0);
    try expectEqual(@as(i64, 0), try zero.asInteger());

    // Negative integers
    const neg = Value.integer(-123);
    try expectEqual(@as(i64, -123), try neg.asInteger());

    // Boundary values (61-bit range)
    const max = Value.integer(Value.INT_MAX);
    try expectEqual(Value.INT_MAX, try max.asInteger());

    const min = Value.integer(Value.INT_MIN);
    try expectEqual(Value.INT_MIN, try min.asInteger());

    // Large negative (tests sign extension)
    const large_neg = Value.integer(-1_000_000_000_000);
    try expectEqual(@as(i64, -1_000_000_000_000), try large_neg.asInteger());

    // Type error
    try expectError(error.TypeError, pos.asBoolean());

    // Truthiness (all integers are truthy)
    try expect(pos.isTruthy());
    try expect(zero.isTruthy());
    try expect(neg.isTruthy());
}
test "Value: PID construction and extraction" {
    const p1 = Value.pid(0);
    const p2 = Value.pid(12345);
    const p3 = Value.pid(Value.PID_MAX);

    try expect(p1.isPid());
    try expect(p2.isPid());

    try expectEqual(@as(u64, 0), try p1.asPid());
    try expectEqual(@as(u64, 12345), try p2.asPid());
    try expectEqual(Value.PID_MAX, try p3.asPid());

    // Type error
    try expectError(error.TypeError, p1.asInteger());
}
test "Value: pointer construction and extraction" {
    var obj = HeapObject{
        .kind = .string,
        .flags = 0,
        .size = 16,
    };

    // Verify our test object is aligned
    const addr = @intFromPtr(&obj);
    try expect(addr % 8 == 0);

    const v = Value.pointer(&obj);

    try expect(v.isPointer());
    try expect(!v.isInteger());
    try expect(!v.isNil());

    const extracted = try v.asPointer();
    try expectEqual(&obj, extracted);
    try expectEqual(HeapObject.Kind.string, extracted.kind);

    // Type-specific checks
    try expect(v.isString());
    try expect(!v.isFloat());
    try expect(!v.isTuple());

    // Type error
    try expectError(error.TypeError, v.asInteger());
}
test "Value: equality" {
    // Same type, same value
    const a1 = Value.integer(42);
    const a2 = Value.integer(42);
    try expect(a1.equals(a2));

    // Same type, different value
    const b1 = Value.integer(42);
    const b2 = Value.integer(43);
    try expect(!b1.equals(b2));

    // Different types
    const c1 = Value.integer(1);
    const c2 = Value.boolean(true);
    try expect(!c1.equals(c2));

    // Nil equality
    const n1 = Value.nil();
    const n2 = Value.nil();
    try expect(n1.equals(n2));

    // Boolean equality
    const t1 = Value.boolean(true);
    const t2 = Value.boolean(true);
    const f1 = Value.boolean(false);
    try expect(t1.equals(t2));
    try expect(!t1.equals(f1));
}
test "Value: hashing" {
    // Same value = same hash
    const a1 = Value.integer(42);
    const a2 = Value.integer(42);
    try expectEqual(a1.hash(), a2.hash());

    // Different values = different hash (usually)
    const b1 = Value.integer(42);
    const b2 = Value.integer(43);
    try expect(b1.hash() != b2.hash());

    // Nil hash
    const n = Value.nil();
    _ = n.hash(); // Just verify it doesn't crash
}
test "Value: formatting" {
    var buf: [256]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const writer = fbs.writer();

    // Nil
    try Value.nil().format(writer);
    try testing.expectEqualStrings("nil", fbs.getWritten());
    fbs.reset();

    // Boolean
    try Value.boolean(true).format(writer);
    try testing.expectEqualStrings("true", fbs.getWritten());
    fbs.reset();

    try Value.boolean(false).format(writer);
    try testing.expectEqualStrings("false", fbs.getWritten());
    fbs.reset();

    // Integer
    try Value.integer(42).format(writer);
    try testing.expectEqualStrings("42", fbs.getWritten());
    fbs.reset();

    try Value.integer(-999).format(writer);
    try testing.expectEqualStrings("-999", fbs.getWritten());
    fbs.reset();

    // PID
    try Value.pid(12345).format(writer);
    try expect(std.mem.startsWith(u8, fbs.getWritten(), "pid<12345>"));
    fbs.reset();
}
test "Value: truthiness" {
    // Falsy values
    try expect(Value.nil().isFalsy());
    try expect(Value.boolean(false).isFalsy());

    // Truthy values
    try expect(Value.boolean(true).isTruthy());
    try expect(Value.integer(0).isTruthy());
    try expect(Value.integer(42).isTruthy());
    try expect(Value.integer(-1).isTruthy());
    try expect(Value.pid(0).isTruthy());
}
test "HeapObject: flag operations" {
    var obj = HeapObject{
        .kind = .string,
        .flags = 0,
        .size = 16,
    };

    // Initially unmarked
    try expect(!obj.isMarked());
    try expect(!obj.isPinned());
    try expect(!obj.isFrozen());

    // Mark
    obj.mark();
    try expect(obj.isMarked());

    // Unmark
    obj.unmark();
    try expect(!obj.isMarked());

    // Multiple flags can coexist
    obj.flags = HeapObject.FLAG_GC_MARK | HeapObject.FLAG_PINNED;
    try expect(obj.isMarked());
    try expect(obj.isPinned());
    try expect(!obj.isFrozen());
}
