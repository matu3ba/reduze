const std = @import("std");
const tests = @import("test/tests.zig");

pub fn build(b: *std.build.Builder) void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});
    const test_step = b.step("test", "Run all the tests");

    // Standard release options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
    const mode = b.standardReleaseOptions();

    const exe = b.addExecutable("deltadebug", "src/main.zig");
    exe.setTarget(target);
    exe.setBuildMode(mode);
    exe.install();
    test_step.dependOn(&exe.step);
    const run_cmd = exe.run();
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    //const enable_logging = b.option(bool, "log", "Enable debug logging with --debug-log") orelse is_debug;

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    // package approach to separate test runner from build system
    var test_cases = b.addTest("src/test.zig");
    test_cases.setBuildMode(mode);
    test_cases.addPackagePath("test_cases", "test/cases.zig");
    //TODO figure out how to set the envmap for RED_EXE

    // const test_cases_options = b.addOptions();
    // test_cases.addOptions("build_options", test_cases_options);
    // test_cases_options.addOption(bool, "enable_logging", enable_logging);

    const test_cases_step = b.step("test-cases", "Run the main test cases.");
    test_cases_step.dependOn(&test_cases.step);
    test_step.dependOn(test_cases_step);

    // more test_step.dependOn(more_simple_test);
    // more test_step.dependOn(more_fancy_test);

    // const init_reductions = tests.testInitialReducation(b, exe);
    // init_reductions.dependOn(b.getInstallStep());
    // const test_step = b.step("test", "Run unit tests");
    // test_step.dependOn(init_reductions);
}
