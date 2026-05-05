const std = @import("std");
const Value = @import("../memory/value.zig").Value;
const Atomic = std.atomic.Value;

pub const QueueError = error{
    Closed,
    OutOfMemory,
};

// Ultra-fast Segmented Lock-Free MPSC Queue
// Amortizes allocation overhead by storing multiple values per Node (Chunk)
pub const Mailbox = struct {
    const Self = @This();

    pub const CHUNK_SIZE = 6; // Keeps Chunk exactly 64 bytes (6*8 + 16 bytes for header)
    const EMPTY_SLOT: u64 = std.math.maxInt(u64); // Ends in 0b111 (tag 7 is reserved, never a valid Value)

    pub const Chunk = struct {
        next: Atomic(?*Chunk) align(64),
        push_idx: Atomic(usize),
        slots: [CHUNK_SIZE]Atomic(u64),
    };

    head: Atomic(*Chunk),
    tail: *Chunk,
    pop_idx: usize,
    allocator: std.mem.Allocator,
    is_closed: Atomic(bool),

    pub fn init(allocator: std.mem.Allocator, io: std.Io) !Self {
        _ = io;
        const chunk = try allocator.create(Chunk);
        chunk.next.store(null, .unordered);
        chunk.push_idx.store(0, .unordered);
        for (0..CHUNK_SIZE) |i| chunk.slots[i].store(EMPTY_SLOT, .unordered);

        return .{
            .head = Atomic(*Chunk).init(chunk),
            .tail = chunk,
            .pop_idx = 0,
            .allocator = allocator,
            .is_closed = Atomic(bool).init(false),
        };
    }

    pub fn deinit(self: *Self) void {
        const freeValue = @import("../memory/value.zig").freeValue;
        var it_msg = self.iterator();
        while (it_msg.next()) |val_ptr| {
            freeValue(self.allocator, val_ptr.*);
        }

        var it: ?*Chunk = self.tail;
        while (it) |chunk| {
            const next = chunk.next.load(.acquire);
            self.allocator.destroy(chunk);
            it = next;
        }
    }

    pub fn close(self: *Self) void {
        self.is_closed.store(true, .release);
    }

    pub fn put(self: *Self, value: Value) QueueError!void {
        if (self.is_closed.load(.acquire)) return error.Closed;

        var chunk = self.head.load(.acquire);
        while (true) {
            const idx = chunk.push_idx.fetchAdd(1, .acquire);

            if (idx < CHUNK_SIZE) {
                // Wait-free fast path: slot reserved, write value
                chunk.slots[idx].store(value.bits, .release);
                return;
            }

            // Chunk is full.
            if (idx == CHUNK_SIZE) {
                // We are the designated thread to allocate the next chunk
                const next_chunk = self.allocator.create(Chunk) catch return error.OutOfMemory;
                next_chunk.next.store(null, .unordered);
                next_chunk.push_idx.store(0, .unordered);
                for (0..CHUNK_SIZE) |i| next_chunk.slots[i].store(EMPTY_SLOT, .unordered);

                chunk.next.store(next_chunk, .release);
                _ = self.head.cmpxchgStrong(chunk, next_chunk, .release, .monotonic);
                chunk = next_chunk;
            } else {
                // Another thread is allocating the next chunk, wait for it
                var next = chunk.next.load(.acquire);
                while (next == null) {
                    std.atomic.spinLoopHint();
                    next = chunk.next.load(.acquire);
                }
                // Try to help update head, but it's okay if it fails
                _ = self.head.cmpxchgWeak(chunk, next.?, .release, .monotonic);
                chunk = next.?;
            }
        }
    }

    pub fn get(self: *Self) !?Value {
        var chunk = self.tail;

        if (self.pop_idx == CHUNK_SIZE) {
            const next = chunk.next.load(.acquire);
            if (next == null) {
                if (self.is_closed.load(.acquire)) return error.Closed;
                return null;
            }
            self.allocator.destroy(chunk);
            self.tail = next.?;
            chunk = next.?;
            self.pop_idx = 0;
        }

        const slot = chunk.slots[self.pop_idx].load(.acquire);
        if (slot == EMPTY_SLOT) {
            if (self.is_closed.load(.acquire)) return error.Closed;
            return null; // Producer reserved but hasn't stored yet
        }

        self.pop_idx += 1;
        return Value{ .bits = slot };
    }

    pub fn isEmpty(self: *const Self) bool {
        const chunk = self.tail;
        if (self.pop_idx < CHUNK_SIZE) {
            return chunk.slots[self.pop_idx].load(.monotonic) == EMPTY_SLOT;
        }
        return chunk.next.load(.monotonic) == null;
    }

    pub const Iterator = struct {
        current_chunk: ?*Chunk,
        current_idx: usize,

        pub fn next(self: *@This()) ?*Value {
            while (self.current_chunk) |chunk| {
                if (self.current_idx == CHUNK_SIZE) {
                    self.current_chunk = chunk.next.load(.acquire);
                    self.current_idx = 0;
                    continue;
                }

                const slot_bits = chunk.slots[self.current_idx].load(.acquire);
                if (slot_bits == EMPTY_SLOT) return null; // No more items written

                // GC needs a pointer to the value to update it if moved.
                // Atomic(u64) has the exact same memory layout as u64/Value.
                const ptr: *Value = @ptrFromInt(@intFromPtr(&chunk.slots[self.current_idx]));
                self.current_idx += 1;
                return ptr;
            }
            return null;
        }
    };

    pub fn iterator(self: *Self) Iterator {
        // Safe to call by consumer during GC because MPSC guarantees
        // nodes from `tail` are reachable and not freed concurrently.
        return .{
            .current_chunk = self.tail,
            .current_idx = self.pop_idx,
        };
    }
};
