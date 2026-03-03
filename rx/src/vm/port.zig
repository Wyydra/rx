const std = @import("std");
const Receiver = @import("interface.zig").Receiver;
const Value = @import("../memory/value.zig").Value;

pub const Port = struct {
    context: ?*anyopaque,
    handler: *const fn (ctx: ?*anyopaque, msg: Value, sched: ?*anyopaque) callconv(.c) void,
    cleanup: ?*const fn (ctx: ?*anyopaque) callconv(.c) void,

    allocator: std.mem.Allocator,
    io: std.Io,
    sched: *anyopaque, // The Scheduler instance

    queue_buf: []Value,
    queue: std.Io.Queue(Value),

    pub fn init(
        allocator: std.mem.Allocator,
        io: std.Io,
        sched: *anyopaque,
        context: ?*anyopaque,
        handler: *const fn (ctx: ?*anyopaque, msg: Value, sched: ?*anyopaque) callconv(.c) void,
        cleanup: ?*const fn (ctx: ?*anyopaque) callconv(.c) void,
    ) !*Port {
        const self = try allocator.create(Port);
        const buf = try allocator.alloc(Value, 256); // 256 messages capacity by default
        self.* = .{
            .context = context,
            .handler = handler,
            .cleanup = cleanup,
            .allocator = allocator,
            .io = io,
            .sched = sched,
            .queue_buf = buf,
            .queue = std.Io.Queue(Value).init(buf),
        };
        return self;
    }

    pub fn deinit(self: *Port) void {
        if (self.cleanup) |c| {
            c(self.context);
        }
        self.allocator.free(self.queue_buf);
        self.allocator.destroy(self);
    }

    pub fn run(self: *Port) void {
        while (true) {
            const msg = self.queue.getOne(self.io) catch break;
            (self.handler)(self.context, msg, self.sched);
        }
    }

    fn receiveImpl(ptr: *anyopaque, msg: Value, sched: *anyopaque) void {
        _ = sched;
        const self = @as(*Port, @ptrCast(@alignCast(ptr)));
        // Put the message async. We don't block the VM fully unless the port queue is filled (256 msg).
        // Actually, putOne can block. In a strictly async VM, this will yield to std.Io.
        self.queue.putOne(self.io, msg) catch |err| {
            std.debug.print("Failed to dispatch to Port queue: {any}\n", .{err});
        };
    }

    pub fn asReceiver(self: *Port) Receiver {
        return .{
            .ptr = self,
            .sendFn = receiveImpl,
        };
    }
};
