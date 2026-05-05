const std = @import("std");
const ActorId = @import("actor.zig").ActorId;
const AsyncPort = @import("port.zig").AsyncPort;
const DynamicLibrary = @import("loader.zig").DynamicLibrary;

pub const Resource = struct {
    ptr: *anyopaque,
    destroyFn: *const fn (ptr: *anyopaque, allocator: std.mem.Allocator) void,
};

pub const System = struct {
    allocator: std.mem.Allocator,

    registry: std.StringArrayHashMapUnmanaged(ActorId),
    resources: std.ArrayListUnmanaged(Resource),
    ports: std.ArrayListUnmanaged(*AsyncPort),
    dynamic_libraries: std.ArrayListUnmanaged(DynamicLibrary),

    io: std.Io,
    mutex: std.Io.Mutex,

    pub fn init(allocator: std.mem.Allocator, io: std.Io) System {
        return .{
            .allocator = allocator,
            .registry = .empty,
            .resources = .empty,
            .ports = .empty,
            .dynamic_libraries = .empty,
            .io = io,
            .mutex = std.Io.Mutex.init,
        };
    }

    pub fn deinit(self: *System) void {
        self.mutex.lockUncancelable(self.io);
        for (self.registry.keys()) |key| {
            self.allocator.free(key);
        }
        self.registry.deinit(self.allocator);
        self.mutex.unlock(self.io);

        for (self.dynamic_libraries.items) |*lib| {
            lib.close();
        }
        self.dynamic_libraries.deinit(self.allocator);

        for (self.resources.items) |r| r.destroyFn(r.ptr, self.allocator);
        self.resources.deinit(self.allocator);
    }

    pub fn teardownPorts(self: *System, io: std.Io, port_group: *std.Io.Group) void {
        for (self.ports.items) |p| p.mailbox.close();
        port_group.await(io) catch |err| {
            std.debug.print("port cleanup await error: {any}\n", .{err});
        };
        for (self.ports.items) |p| {
            if (p.deinit) |f| f(p.context);
            p.mailbox.deinit();
            self.allocator.destroy(p);
        }
        self.ports.deinit(self.allocator);
    }

    pub fn trackResource(
        self: *System,
        ptr: *anyopaque,
        destroyFn: *const fn (*anyopaque, std.mem.Allocator) void,
    ) !void {
        try self.resources.append(self.allocator, .{ .ptr = ptr, .destroyFn = destroyFn });
    }

    pub fn register(self: *System, name: []const u8, pid: ActorId) !void {
        const key = try self.allocator.dupe(u8, name);
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        try self.registry.put(self.allocator, key, pid);
    }
    pub fn resolve(self: *System, name: []const u8) ?ActorId {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        return self.registry.get(name);
    }
};
