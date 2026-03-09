const std = @import("std");
const System = @import("system.zig").System;
const Scheduler = @import("scheduler.zig").Scheduler;
const HeapObject = @import("../memory/value.zig").HeapObject;
const Value = @import("../memory/value.zig").Value;
const ActorId = @import("actor.zig").ActorId;
const Port = @import("port.zig").Port;
const MathPort = @import("../bif/math.zig").MathPort;
const PortLoader = @import("loader.zig").PortLoader;

pub const VM = struct {
    system: System,
    scheduler: Scheduler,
    allocator: std.mem.Allocator,
    math_port: MathPort,
    loader: PortLoader,

    pub fn init(allocator: std.mem.Allocator) !*VM {
        const self = try allocator.create(VM);
        errdefer allocator.destroy(self);

        self.allocator = allocator;
        self.system = System.init(allocator);
        self.scheduler = Scheduler.init(allocator, 0, &self.system);
        self.loader = PortLoader.init(allocator);

        // Register built-in BIF ports
        self.math_port = MathPort.init();
        const math_pid = try self.scheduler.spawnReceiver(@import("port.zig").asReceiver(&self.math_port.port));
        try self.system.register("math", math_pid);

        return self;
    }

    pub fn deinit(self: *VM) void {
        self.loader.deinit();
        self.scheduler.deinit();
        self.system.deinit();
        self.allocator.destroy(self);
    }

    pub fn spawn(self: *VM, main_func: *HeapObject, args: []const Value) !ActorId {
        return self.scheduler.spawn(main_func, args);
    }

    pub fn loadPlugin(self: *VM, path: []const u8) !void {
        const load_fn = try self.loader.open(path);
        load_fn(@ptrCast(&self.scheduler));
    }

    pub fn execute(self: *VM) !void {
        return self.scheduler.execute();
    }
};
