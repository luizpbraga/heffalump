const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const heffalump_mod = b.addModule("heffalump", .{
        .root_source_file = .{ .path = "./heffalump.zig" },
    });

    const tests = b.addTest(.{
        .root_source_file = .{ .path = "./test/test.zig" },
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    tests.linkSystemLibrary("pq");
    tests.root_module.addImport("heffalump", heffalump_mod);

    const run_lib_unit_tests = b.addRunArtifact(tests);
    const test_step = b.step("test", "Run Heffalump unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);
}
