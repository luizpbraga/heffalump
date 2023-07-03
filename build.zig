const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const heffalump = b.createModule(.{
        .source_file = .{ .path = "src/heffalump.zig" },
    });

    try b.modules.put(b.dupe("heffalump"), heffalump);

    const lib = b.addStaticLibrary(.{
        .name = "heffalump",
        .root_source_file = .{ .path = "src/heffalump.zig" },
        .target = target,
        .optimize = optimize,
    });

    lib.linkLibC();
    lib.linkSystemLibrary("pq");

    b.installArtifact(lib);

    const main_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/test.zig" },
        .target = target,
        .optimize = optimize,
    });

    main_tests.linkLibC();
    main_tests.linkSystemLibrary("pq");

    const run_main_tests = b.addRunArtifact(main_tests);

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&run_main_tests.step);
}
