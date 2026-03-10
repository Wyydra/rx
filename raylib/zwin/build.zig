const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // ── Raylib dependency ─────────────────────────────────────────────────────
    const raylib_dep = b.dependency("raylib_zig", .{
        .target = target,
        .optimize = optimize,
    });

    const raylib = raylib_dep.module("raylib");
    const raylib_artifact = raylib_dep.artifact("raylib");

    // ── Shared library (Rx port plugin) ───────────────────────────────────────
    const lib = b.addLibrary(.{
        .name = "zwin",
        .linkage = .dynamic,
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    // Link raylib
    lib.root_module.linkLibrary(raylib_artifact);
    lib.root_module.addImport("raylib", raylib);

    // Expose rx_api.h so @cImport can find it
    lib.root_module.addIncludePath(b.path("../../rx/include"));

    // Build system puts libzwin.so in zig-out/lib/
    b.installArtifact(lib);
}
