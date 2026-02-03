const std = @import("std");
const Value = @import("../memory/value.zig").Value;
const HeapObject = @import("../memory/value.zig").HeapObject;
const Function = @import("../memory/function.zig");

pub const CallFrame = struct {
    base: usize,
    return_ip: usize,
    closure: *HeapObject,
};
pub const Process = struct {
    node: std.DoublyLinkedList.Node = .{},

    pid: u32, // TODO: proper type

    stack: std.ArrayList(Value),
    frames: std.ArrayList(CallFrame),

    saved_ip: usize,

    pub fn init(allocator: std.mem.Allocator, pid: u32, main_closure: *HeapObject) !*Process {
        // TODO: same allocator as vm heap ??
        const self = try allocator.create(Process);

        self.node = .{ .prev = null, .next = null };
        self.pid = pid;
        self.stack = .empty;
        self.frames = .empty;
        self.saved_ip = 0;

        try self.stack.append(allocator,Value.pointer(main_closure));
        try self.stack.appendNTimes(allocator, Value.nil(), 20); 

        try self.frames.append(allocator, .{
            .base = 1,
            .return_ip = 0,
            .closure = main_closure,
        });

        return self;
    }

    pub fn deinit(self: *Process, allocator: std.mem.Allocator) void {
        self.stack.deinit(allocator);
        self.frames.deinit(allocator);
        allocator.destroy(self); 
    }
};
