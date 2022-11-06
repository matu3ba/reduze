//! Test runner inspired by the compiler test suite.

const std = @import("std");
const builtin = @import("builtin");
const build = std.build;
const Mode = std.builtin.Mode;

// TODO refactor into lib
pub fn fatal(comptime format: []const u8, args: anytype) noreturn {
    std.log.err(format, args);
    std.process.exit(1);
}

const initial_reduction = @import("initial_reduction.zig");

pub const ReductionContext = struct {
    b: *build.Builder,
    step: *build.Step,
    exec: *std.build.LibExeObjStep,
    //modes: []const Mode,

    // TODO: use in-place compilation API of incremental Zig backend
    // to read all input programs, compile them in parallel and compare
    // the expected output locations of program started in memory
    pub fn add(
        self: *ReductionContext,
        before: []const u8,
        after: []const u8,
    ) void {
        self.addAllArgs(before, after, false);
    }

    /// before: pathtofilname_b.zig, output: pathtofilname_aN.zig,
    /// N maximum necessary algorithm step
    /// expected_after: pathtofilename_a.zig
    pub fn addAllArgs(
        self: *ReductionContext,
        before: []const u8,
        after: []const u8,
        link_libc: bool,
    ) void {
        _ = link_libc;
        const b = self.b;
        const exec = self.exec.getOutputSource();
        const startpath = b.pathJoin(&.{ "/tmp", "reduze", before });
        std.debug.print("before {s}, after {s}, results {s}\n", .{ before, after, startpath });
        std.debug.print("executing {s}", .{exec.getDisplayName()});
        std.debug.print(" {s}, ", .{before});
        std.debug.print("results in {s}\n", .{startpath});

        // const run_cmd = self.exec.run();
        // run_cmd.addArg(before);
        // run_cmd.addArg(startpath);
        // std.debug.print("addAllArgs will be run for {s} and {s}, results in {s}\n", .{ before, after, startpath });

        // TODO: test routine should pick biggest N it can find
        // => get last number item
        // _ = before;
        std.debug.print("addAllArgs was run for {s} and {s}, results in {s}\n", .{ before, after, startpath });
        // TODO run reduction and compare result
        {
            // TODO chunk-wise comparison of files
            // std.testing.expectEqualSlices(pathmaxN_source, after_source);
        }

        // for (self.modes) |mode| {
        //     const annotated_case_name = std.fmt.allocPrint(self.b.allocator, "build {s} ({s})", .{
        //         root_src,
        //         @tagName(mode),
        //     }) catch unreachable;
        //     if (self.test_filter) |filter| {
        //         if (std.mem.indexOf(u8, annotated_case_name, filter) == null) continue;
        //     }
        //
        //     const exe = b.addExecutable("test", root_src);
        //     exe.setBuildMode(mode);
        //     if (link_libc) {
        //         exe.linkSystemLibrary("c");
        //     }
        //
        //     const log_step = b.addLog("PASS {s}", .{annotated_case_name});
        //     log_step.step.dependOn(&exe.step);
        //
        //     self.step.dependOn(&log_step.step);
        // }
    }
};

pub fn testInitialReducation(
    b: *build.Builder,
    exec: *std.build.LibExeObjStep,
) *build.Step {
    const cases = b.allocator.create(ReductionContext) catch unreachable;
    cases.* = ReductionContext{
        .b = b,
        .step = b.step("test-init-red", "Test initial reduction"),
        .exec = exec,
    };
    initial_reduction.addCases(cases);
    return cases.step;
}
