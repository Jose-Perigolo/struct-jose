const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Library module
    const lib_mod = b.addModule("voxgig-struct", .{
        .root_source_file = b.path("src/struct.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Static library artifact
    const lib = b.addStaticLibrary(.{
        .name = "voxgig-struct",
        .root_source_file = b.path("src/struct.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(lib);

    // Tests
    const tests = b.addTest(.{
        .root_source_file = b.path("test/struct_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    tests.root_module.addImport("voxgig-struct", lib_mod);

    const run_tests = b.addRunArtifact(tests);
    run_tests.has_side_effects = true;

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_tests.step);
}
