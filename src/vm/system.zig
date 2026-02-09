const std = @import("std");
const ActorId = @import("actor.zig").ActorId;
pub const System = struct {
    allocator: std.mem.Allocator,

    registry: std.StringArrayHashMap(ActorId),

    pub fn init(allocator: std.mem.Allocator) System {
        return .{
            .allocator = allocator,
            .registry = std.StringArrayHashMap(ActorId).init(allocator),
        };
    }

    pub fn deinit(self: *System) void {
        self.registry.deinit();
    }

    pub fn register(self: *System, name: []const u8, pid: ActorId) !void {
        const key = self.allocator.dupe(u8, name);
        self.registry.put(key, pid);
    }
    pub fn resolve(self: *System, name: []const u8) ?ActorId {
        return self.registry.get(name);
    }
};
