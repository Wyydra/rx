const std = @import("std");
pub const Process = @import("process.zig").Process;
pub const Port = @import("port.zig").Port;
const Scheduler = @import("scheduler.zig").Scheduler;
const Value = @import("../memory/value.zig").Value;

pub const ActorId = packed struct(u32) {
    // kow : local index 
    index: u24,

    // high 8 : scheduler id
    scheduler_id: u8,

    pub fn init(scheduler: u8, idx: u24) ActorId {
        return ActorId{
            .scheduler_id = scheduler,
            .index = idx,
        };
    }

    pub fn fromInt(raw: u32) ActorId {
        return @bitCast(raw);
    }

    pub fn toInt(self: ActorId) u32 {
        return @bitCast(self);
    }

    pub fn isLocal(self: ActorId, current_scheduler_id: u8) bool {
        return self.scheduler_id == current_scheduler_id;
    }

    pub fn equal(self: ActorId, other: ActorId) bool {
        return self.toInt() == other.toInt();
    }

    pub fn format(
        self: @This(),
        writer: *std.Io.Writer,
    ) std.Io.Writer.Error!void {
        try writer.print("<{d}:{d}>", .{self.scheduler_id, self.index});
    }
};

pub const Actor = union(enum) {
    process: *Process,
    port: *Port,

    pub fn send(self: Actor, msg: Value, sched: *Scheduler) void {
        switch (self) {
            .process => |proc| {
                // Software: Queue it for later execution
                proc.pushMessage(msg) catch {};
            },
            .port => |p| {
                // Hardware: Execute immediately (System Driver)
                (p.handler)(p.context, msg, sched);
            },
        }
    }

    pub fn deinit(self: Actor, allocator: std.mem.Allocator) void {
        switch (self) {
            .process => |proc| {
                proc.deinit(allocator); // Defined in process.zig
            },
            .port => |_| {
                // TODO: .cleanup() fn ptr to port struct
            },
        }
    }
};
