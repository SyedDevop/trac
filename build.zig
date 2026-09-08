const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const include_tasks_md_content = b.option(bool, "include_content", "Include the TASKS.md content in Task.task_md_content") orelse false;

    const zarg = b.dependency("zarg", .{
        .target = target,
        .optimize = optimize,
    });

    const exe = b.addExecutable(.{
        .name = "trac",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zarg", .module = zarg.module("zarg") },
            },
        }),
    });
    const opt = b.addOptions();
    opt.addOption(bool, "include_tasks_md_content", include_tasks_md_content);
    exe.root_module.addOptions("buildOptions", opt);
    b.installArtifact(exe);

    const run_step = b.step("run", "Run this project");

    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);
}
