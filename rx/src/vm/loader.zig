const std = @import("std");

pub const LoadFn = *const fn (sched: *anyopaque) callconv(.c) void;

pub const DynamicLibrary = struct {
    lib: std.DynLib,

    pub fn close(self: *DynamicLibrary) void {
        self.lib.close();
    }
};

pub fn open(path: []const u8) !struct { DynamicLibrary, LoadFn } {
    var lib = try std.DynLib.open(path);
    errdefer lib.close();

    const sym = lib.lookup(LoadFn, "rx_load") orelse return error.SymbolNotFound;
    return .{ .{ .lib = lib }, sym };
}
