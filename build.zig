const std = @import("std");
const log = std.log.scoped(.ntp_client_build);

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const flags = b.dependency("flags", .{});
    const flags_module = flags.module("flags");

    const zdt = b.dependency("zdt", .{
        // use system zoneinfo:
        //        .prefix_tzdb = @as([]const u8, "/usr/share/zoneinfo"),
    });
    const zdt_module = zdt.module("zdt");

    const exe = b.addExecutable(.{
        .name = "ntp_client",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    b.installArtifact(exe);

    //    exe.linkLibC(); // needed for DNS query

    exe.root_module.addImport("flags", flags_module);
    exe.root_module.addImport("zdt", zdt_module);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| run_cmd.addArgs(args);

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const unit_tests = b.addTest(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    const run_unit_tests = b.addRunArtifact(unit_tests);
    //    run_unit_tests.has_side_effects = true;
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);

    const docs_step = b.step("docs", "auto-generate documentation");
    {
        const install_docs = b.addInstallDirectory(.{
            .source_dir = exe.getEmittedDocs(),
            .install_dir = std.Build.InstallDir{ .custom = "../autodoc" },
            .install_subdir = "",
        });
        docs_step.dependOn(&install_docs.step);
    }
}
