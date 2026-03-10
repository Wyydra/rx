const std = @import("std");
const Value = @import("../memory/value.zig").Value;
const Io = std.Io;

pub const Mailbox = struct {
    queue: Io.Queue(Value),
    buffer: []Value,

    pub fn init(allocator: std.mem.Allocator) !Mailbox {
        // Queue has a fixed capacity
        const buffer = try allocator.alloc(Value, 256);
        @memset(buffer, Value.nil());
        return .{
            .queue = .init(buffer),
            .buffer = buffer,
        };
    }

    pub fn deinit(self: *Mailbox, allocator: std.mem.Allocator, io: Io) void {
        self.queue.close(io);
        allocator.free(self.buffer);
    }

    pub fn put(self: *Mailbox, io: Io, value: Value) void {
        // Blocks until there is space in the queue
        self.queue.putOneUncancelable(io, value) catch |err| switch (err) {
            error.Closed => {}, // Queue is closing, ignore
        };
    }

    pub fn get(self: *Mailbox, io: Io) ?Value {
        // Blocks until a value is available or queue shrinks/closes
        return self.queue.getOne(io) catch |err| switch (err) {
            error.Canceled => return null,
            error.Closed => return null,
        };
    }
};
