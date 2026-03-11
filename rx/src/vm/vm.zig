const std = @import("std");
const System = @import("system.zig").System;
const Scheduler = @import("scheduler.zig").Scheduler;
const HeapObject = @import("../memory/value.zig").HeapObject;
const Value = @import("../memory/value.zig").Value;
const ActorId = @import("actor.zig").ActorId;
const Port = @import("port.zig").Port;
const PortLoader = @import("loader.zig").PortLoader;

pub const VM = struct {
    system: System,
    scheduler: Scheduler,
    allocator: std.mem.Allocator,
    loader: PortLoader,

    pub fn init(allocator: std.mem.Allocator, io: std.Io) !*VM {
        const self = try allocator.create(VM);
        errdefer allocator.destroy(self);

        self.allocator = allocator;
        self.system = System.init(allocator);
        self.scheduler = Scheduler.init(allocator, 0, &self.system, io);
        self.loader = PortLoader.init(allocator);

        return self;
    }

    pub fn deinit(self: *VM) void {
        self.scheduler.deinit();
        self.system.teardownPorts(self.scheduler.io, &self.scheduler.port_group);
        self.loader.deinit();
        self.system.deinit();
        self.allocator.destroy(self);
    }

    pub fn spawn(self: *VM, main_func: *HeapObject, args: []const Value) !ActorId {
        return self.scheduler.spawn(main_func, args);
    }

    // for now load is synchronous
    pub fn loadPort(self: *VM, path: []const u8) !void {
        const res = try self.loader.open(path);
        const dynamic_lib = res[0];
        const load_fn = res[1];
        try self.system.dynamic_libraries.append(self.allocator, dynamic_lib);
        load_fn(@ptrCast(&self.scheduler));
    }

    pub fn execute(self: *VM) !void {
        return self.scheduler.execute();
    }
};
