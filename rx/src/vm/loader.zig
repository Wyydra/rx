const std = @import("std");

const RTLD_LAZY: c_int = 0x00001;
const RTLD_GLOBAL: c_int = 0x00100;

extern fn dlopen(path: [*:0]const u8, flags: c_int) ?*anyopaque;
extern fn dlclose(handle: *anyopaque) c_int;
extern fn dlsym(handle: ?*anyopaque, name: [*:0]const u8) ?*anyopaque;
extern fn dlerror() ?[*:0]const u8;

pub const LoadFn = *const fn (sched: *anyopaque) callconv(.c) void;

pub const PortLoader = struct {
    handles: std.ArrayListUnmanaged(*anyopaque),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) PortLoader {
        return .{ .handles = .empty, .allocator = allocator };
    }

    pub fn deinit(self: *PortLoader) void {
        for (self.handles.items) |h| _ = dlclose(h);
        self.handles.deinit(self.allocator);
    }

    pub fn open(self: *PortLoader, path: []const u8) !LoadFn {
        const path_z = try self.allocator.dupeZ(u8, path);
        defer self.allocator.free(path_z);

        const handle = dlopen(path_z.ptr, RTLD_LAZY | RTLD_GLOBAL) orelse {
            if (dlerror()) |err| std.debug.print("dlopen error: {s}\n", .{std.mem.span(err)});
            return error.FileNotFound;
        };
        errdefer _ = dlclose(handle);

        const sym = dlsym(handle, "rx_load") orelse {
            if (dlerror()) |err| std.debug.print("dlsym(rx_load) error: {s}\n", .{std.mem.span(err)});
            return error.SymbolNotFound;
        };
        const load_fn: LoadFn = @ptrCast(sym);
        try self.handles.append(self.allocator, handle);
        return load_fn;
    }
};
