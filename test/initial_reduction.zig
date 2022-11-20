//! Test initial reduction
//! After the initial reduction, the number of test blocks to reproduce the
//! behavior are reduced.

const std = @import("std");
const builtin = @import("builtin");
const TestContext = @import("../src/test.zig").TestContext;

pub fn addCases(ctx: *TestContext) !void {
    try addCase(ctx, "./test/initial_reduction/minimal_b.zig", "./test/initial_reduction/minimal_a.zig");
}

pub fn addCase(ctx: *TestContext, fpath_before: []const u8, fpath_after: []const u8) !void {
    const case = TestContext.Case{
        .filepath_before = fpath_before,
        .filepath_after = fpath_after,
    };
    try ctx.cases.append(case);
}
