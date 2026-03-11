const std = @import("std");

pub const LoadFn = *const fn (sched: *anyopaque) callconv(.c) void;

pub const DynamicLibrary = struct {
    lib: std.DynLib,

    pub fn close(self: *DynamicLibrary) void {
        self.lib.close();
    }
};

pub const PortLoader = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) PortLoader {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *PortLoader) void {
        _ = self;
    }

    pub fn open(self: *PortLoader, path: []const u8) !struct { DynamicLibrary, LoadFn } {
        _ = self;
        // In Zig 0.16.x, DynLib.open usually takes an allocator.
        var lib = try std.DynLib.open(path);
        errdefer lib.close();

        const sym = lib.lookup(LoadFn, "rx_load") orelse return error.SymbolNotFound;
        return .{ .{ .lib = lib }, sym };
    }
};
