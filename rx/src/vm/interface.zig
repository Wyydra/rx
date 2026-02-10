const Value = @import("../memory/value.zig").Value;

pub const Receiver = struct {
    ptr: *anyopaque,
    sendFn: *const fn (ptr: *anyopaque, msg: Value) bool,

    pub fn send(self: Receiver, msg: Value) bool {
        return self.sendFn(self.ptr, msg);
    }
};
