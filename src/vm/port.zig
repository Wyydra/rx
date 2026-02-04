const std = @import("std");
const Receiver = @import("interface.zig").Receiver;
const Value = @import("../memory/value.zig").Value;

pub const Port = extern struct {
    context: ?*anyopaque,

    handler: *const fn (ctx: ?*anyopaque, msg: Value) callconv(.c) void,

    fn receiveImpl(ptr: *anyopaque, msg: Value) bool {
        const self = @as(*Port, @ptrCast(@alignCast(ptr)));
        (self.handler)(self.context, msg);
        return false;
    }

    pub fn asReceiver(self: *Port) Receiver {
        return .{
            .ptr = self,
            .sendFn = receiveImpl,
        };
    }
};
