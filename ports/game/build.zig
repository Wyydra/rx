const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const sdl_dep = b.dependency("sdl", .{
        .target = target,
        .optimize = optimize,
    });

    const rx_dep = b.dependency("rx", .{
        .target = target,
        .optimize = optimize,
    });

    const mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .strip = true,
    });

    mod.addIncludePath(rx_dep.path("include"));
    mod.linkLibrary(sdl_dep.artifact("SDL3"));

    const lib = b.addLibrary(.{
        .linkage = .dynamic,
        .name = "rxi_game",
        .root_module = mod,
    });

    b.installArtifact(lib);
}
