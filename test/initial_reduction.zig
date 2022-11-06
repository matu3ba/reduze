//! Test initial reduction
//! After the initial reduction, the number of test blocks to reproduce the
//! behavior are reduced.

const std = @import("std");
const builtin = @import("builtin");
const TestContext = @import("../src/test.zig").TestContext;

pub fn addCases(ctx: *TestContext) !void {
    try addCase(ctx, "minimal");
}

pub fn addCase(ctx: *TestContext, name: []const u8) !void {
    const case = TestContext.Case{
        .name = name,
    };
    try ctx.cases.append(case);
}
