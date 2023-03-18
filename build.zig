const std = @import("std");
const tests = @import("test/tests.zig");

pub fn build(b: *std.build.Builder) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const reduze_exe = b.addExecutable(.{
        .name = "reduze",
        .root_source_file = .{ .path = "src/main.zig" },
        .optimize = optimize,
        .target = target,
    });
    const install_art = b.addInstallArtifact(reduze_exe);
    const install_step = b.step("install_reduze", "Install reducer executable");
    install_step.dependOn(&install_art.step);

    const run_cmd = b.addRunArtifact(reduze_exe);
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const tests_step = b.step("test", "Run all the tests");
    tests_step.dependOn(&reduze_exe.step);

    {
        var unit_tests = b.addTest(.{
            .root_source_file = .{ .path = "src/main.zig" },
            .optimize = optimize,
            .target = target,
        });
        // unit_tests.addModule("zig", zig_module);
        // tests_step.dependOn(&unit_tests.step);

        const tunit_step = b.step("tunit", "Run unit tests");
        tunit_step.dependOn(&unit_tests.step);
        tests_step.dependOn(tunit_step);
    }

    {
        const integration_tests = b.addExecutable(.{
            .name = "test-runner",
            .root_source_file = .{ .path = "test/runner.zig" },
        });
        // integration_tests.addModule("reduze", reduze_module);
        // const test_runner_options = b.addOptions();
        // integration_tests.addOptions("build_options", test_runner_options);
        // test_runner_options.addOption(bool, "test_all_allocation_failures", test_all_allocation_failures);
        const integration_test_runner = integration_tests.run();
        integration_test_runner.addArg(b.pathFromRoot("test/cases"));
        integration_test_runner.addArg(b.zig_exe);
        tests_step.dependOn(&integration_test_runner.step);
    }

    // const test_cases = b.addTest(.{
    //     .root_source_file = .{ .path = "src/test.zig" },
    //     .optimize = optimize,
    // });
    // test_cases.main_pkg_path = ".";
    // const test_filter = b.option([]const u8, "test-filter", "Skip tests that do not match filter");
    //
    // const test_cases_options = b.addOptions();
    // test_cases.addOptions("build_options", test_cases_options);
    // test_cases_options.addOption(bool, "enable_logging", enable_logging);
    // test_cases_options.addOption(?[]const u8, "test_filter", test_filter);

    // {
    //     const reduction_step = b.step("tred", "Run reduction tests");
    //     reduction_step.dependOn(&reduze_exe.step);
    //     reduction_step.dependOn(tests.addPkgTests(
    //         b,
    //         test_filter,
    //         "test/reduce.zig",
    //         "reduce",
    //         "Run the reduction tests",
    //     ));
    //     tests_step.dependOn(reduction_step);
    // }
}
