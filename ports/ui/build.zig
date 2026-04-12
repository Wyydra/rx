const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const rx_dep = b.dependency("rx", .{});

    const mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .root_source_file = b.path("src/main.zig"),
    });

    mod.addIncludePath(rx_dep.path("include"));

    mod.linkSystemLibrary("gtk4", .{});

    const lib = b.addLibrary(.{
        .linkage = .dynamic,
        .name = "rxi_ui",
        .root_module = mod,
    });

    b.installArtifact(lib);
}
