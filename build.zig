const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "clipt",
        .root_module = b.createModule(.{
            .root_source_file = b.path("clipt.zig"),
            .target = target,
            .optimize = optimize,
            .strip = true,
            .single_threaded = true,
        }),
    });
    exe.root_module.linkSystemLibrary("user32", .{});
    exe.root_module.linkSystemLibrary("kernel32", .{});
    const install = b.addInstallArtifact(exe, .{ .dest_dir = .{ .override = .prefix } });
    b.getInstallStep().dependOn(&install.step);

    const run = b.addRunArtifact(exe);
    if (b.args) |args| run.addArgs(args);
    const run_step = b.step("run", "Run clipt");
    run_step.dependOn(&run.step);
}
