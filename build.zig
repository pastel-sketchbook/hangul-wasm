const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.resolveTargetQuery(.{
        .cpu_arch = .wasm32,
        .os_tag = .freestanding,
    });

    const optimize = b.standardOptimizeOption(.{
        .preferred_optimize_mode = .ReleaseSmall,
    });

    // Create module
    const hangul_module = b.createModule(.{
        .root_source_file = b.path("hangul.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Create executable without entry point (WASM library)
    const exe = b.addExecutable(.{
        .name = "hangul",
        .root_module = hangul_module,
    });

    exe.entry = .disabled;
    exe.rdynamic = true;

    b.installArtifact(exe);

    // Test step
    const host_target = b.resolveTargetQuery(.{});

    const test_module = b.createModule(.{
        .root_source_file = b.path("hangul.zig"),
        .target = host_target,
    });

    const unit_tests = b.addTest(.{
        .root_module = test_module,
    });

    const run_tests = b.addRunArtifact(unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_tests.step);
}
