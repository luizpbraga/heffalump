const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const heffalump_mod = b.addModule("heffalump", .{
        .root_source_file = .{ .path = "./heffalump.zig" },
    });

    const exe = b.addExecutable(.{
        .name = "heffalump",
        .root_source_file = .{ .path = "heffalump.zig" },
        .target = target,
        .optimize = optimize,
    });
    exe.linkLibC();
    exe.linkSystemLibrary("pq");
    exe.root_module.addImport("heffalump", heffalump_mod);

    b.installArtifact(exe);
    const run_cmd = b.addRunArtifact(exe);
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    // TESTS
    const tests = b.addTest(.{
        .root_source_file = .{ .path = "./test/test.zig" },
        .target = target,
        .optimize = optimize,
    });
    tests.linkLibC();
    tests.linkSystemLibrary("pq");
    tests.root_module.addImport("heffalump", heffalump_mod);

    const run_lib_unit_tests = b.addRunArtifact(tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);
}
