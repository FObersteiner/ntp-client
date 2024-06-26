const std = @import("std");
const log = std.log.scoped(.ntp_client_build);
const client_version = std.SemanticVersion{ .major = 0, .minor = 0, .patch = 14 };

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // -Dexe option is required to build the executable.
    // This avoids leaking dependencies, if another project wants to use
    // ntp.zig as a library.
    const build_exe = b.option(bool, "exe", "build executable");

    // expose ntp.zig as a library
    _ = b.addModule("ntp_client", .{
        .root_source_file = b.path("src/ntp.zig"),
    });

    if (build_exe) |_| {
        const exe = b.addExecutable(.{
            .name = "ntp_client",
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .version = client_version,
        });

        b.installArtifact(exe);

        // for Windows compatibility, required by sockets functionality
        exe.linkLibC();

        // using lazy dependencies here so that another project can
        // use the NTP lib without having to fetch flags and zdt
        if (b.lazyDependency("flags", .{
            .optimize = optimize,
            .target = target,
        })) |dep| {
            exe.root_module.addImport("flags", dep.module("flags"));
        }
        if (b.lazyDependency("zdt", .{
            .optimize = optimize,
            .target = target,
            // use system zoneinfo:
            // .prefix_tzdb = @as([]const u8, "/usr/share/zoneinfo"),
        })) |dep| {
            exe.root_module.addImport("zdt", dep.module("zdt"));
        }

        const run_cmd = b.addRunArtifact(exe);
        run_cmd.step.dependOn(b.getInstallStep());

        if (b.args) |args| run_cmd.addArgs(args);

        const run_step = b.step("run", "Run the app");
        run_step.dependOn(&run_cmd.step);
    }

    // run unit tests from ntp.zig, which on its own has no dependencies
    const unit_tests = b.addTest(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    const run_unit_tests = b.addRunArtifact(unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);

    // autodocs step excluded since not really useful as NTP lib is currently
    // pretty small.
    // const docs_step = b.step("docs", "auto-generate documentation");
    // {
    //     const install_docs = b.addInstallDirectory(.{
    //         .source_dir = exe.getEmittedDocs(),
    //         .install_dir = std.Build.InstallDir{ .custom = "../autodoc" },
    //         .install_subdir = "",
    //     });
    //     docs_step.dependOn(&install_docs.step);
    // }
}
