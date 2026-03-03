const Value = @import("../memory/value.zig").Value;

pub const Receiver = struct {
    ptr: *anyopaque,
    sendFn: *const fn (ptr: *anyopaque, msg: Value, scheduler: *anyopaque) void,

    pub fn send(self: Receiver, msg: Value, scheduler: *anyopaque) void {
        self.sendFn(self.ptr, msg, scheduler);
    }
};
