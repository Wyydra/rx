const std = @import("std");
const Port = @import("../vm/port.zig").Port;
const Value = @import("../memory/value.zig").Value;
const Scheduler = @import("../vm/scheduler.zig").Scheduler;
const ActorId = @import("../vm/actor.zig").ActorId;
const Tuple = @import("../memory/tuple.zig");

pub const MathPort = struct {
    port: Port,

    pub fn init() MathPort {
        return .{ .port = .{
            .context = null,
            .handler = handleMessage,
            .deinit = null,
        } };
    }

    fn handleMessage(ctx: ?*anyopaque, msg: Value, raw_sched: *anyopaque) callconv(.c) void {
        _ = ctx;
        const sched: *Scheduler = @ptrCast(@alignCast(raw_sched));

        if (!msg.isPointer()) return;
        const obj = msg.asPointer() catch return;
        if (obj.kind != .tuple) return;
        if (Tuple.getCount(obj) < 4) return;

        // (cmd, arg1, arg2, reply_pid)
        const cmd = Tuple.getValue(obj, 0).asInteger() catch return;
        const arg1 = Tuple.getValue(obj, 1).asInteger() catch return;
        const arg2 = Tuple.getValue(obj, 2).asInteger() catch return;
        const rpid = Tuple.getValue(obj, 3).asInteger() catch return;

        const result: i64 = switch (cmd) {
            1 => arg1 + arg2, // ADD
            2 => arg1 - arg2, // SUB
            else => return,
        };

        std.debug.print("Math port calculated: {d}\n", .{result});
        sched.send(ActorId.fromInt(@intCast(rpid)), Value.integer(result));
    }
};
