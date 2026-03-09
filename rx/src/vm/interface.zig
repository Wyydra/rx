const Value = @import("../memory/value.zig").Value;
const Scheduler = @import("scheduler.zig").Scheduler;

pub const Receiver = struct {
    ptr: *anyopaque,
    sendFn: *const fn (ptr: *anyopaque, msg: Value, sched: *Scheduler) bool,

    pub fn send(self: Receiver, msg: Value, sched: *Scheduler) bool {
        return self.sendFn(self.ptr, msg, sched);
    }
};
