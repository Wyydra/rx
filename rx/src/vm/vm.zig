const std = @import("std");
const System = @import("system.zig").System;
const Scheduler = @import("scheduler.zig").Scheduler;
const HeapObject = @import("../memory/value.zig").HeapObject;
const Value = @import("../memory/value.zig").Value;
const ActorId = @import("actor.zig").ActorId;

pub const VM = struct {
    system: System,
    scheduler: Scheduler,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) !*VM {
        const self = try allocator.create(VM);
        errdefer allocator.destroy(self);

        self.allocator = allocator;
        self.system = System.init(allocator);
        self.scheduler = Scheduler.init(allocator, 0, &self.system);

        return self;
    }

    pub fn deinit(self: *VM) void {
        self.scheduler.deinit();
        self.system.deinit();
        self.allocator.destroy(self);
    }

    pub fn spawn(self: *VM, main_func: *HeapObject, args: []const Value) !ActorId {
        return self.scheduler.spawn(main_func, args);
    }

    pub fn execute(self: *VM) !void {
        return self.scheduler.execute();
    }
};
