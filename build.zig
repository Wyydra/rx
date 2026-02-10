const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Dependency on rx
    const rx = b.dependency("rx", .{
        .target = target,
        .optimize = optimize,
    });

    // Dependency on rxt
    const rxt = b.dependency("rxt", .{
        .target = target,
        .optimize = optimize,
    });

    // Expose rx artifact
    const rx_exe = rx.artifact("rx");
    b.installArtifact(rx_exe);

    // Expose rxt artifact
    const rxt_exe = rxt.artifact("rxt");
    b.installArtifact(rxt_exe);

    // Run step for rx
    const run_rx_step = b.step("run-rx", "Run the rx project");
    const run_rx_cmd = b.addRunArtifact(rx_exe);
    if (b.args) |args| {
        run_rx_cmd.addArgs(args);
    }
    run_rx_step.dependOn(&run_rx_cmd.step);

    // Run step for rxt
    const run_rxt_step = b.step("run-rxt", "Run the rxt project");
    const run_rxt_cmd = b.addRunArtifact(rxt_exe);
    if (b.args) |args| {
        run_rxt_cmd.addArgs(args);
    }
    run_rxt_step.dependOn(&run_rxt_cmd.step);
}
