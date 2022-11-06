const std = @import("std");
test {
    const gpa = std.testing.allocator;
    var arena_allocator = std.heap.ArenaAllocator.init(gpa);
    defer arena_allocator.deinit();
    const arena = arena_allocator.allocator();

    var ctx = TestContext.init(gpa, arena);
    defer ctx.deinit();

    // no fancy logic yet

    try @import("test_cases").addCases(&ctx);
    try ctx.run();
}

pub const TestContext = struct {
    gpa: std.mem.Allocator,
    arena: std.mem.Allocator,
    cases: std.ArrayList(Case),

    /// A `Case` consists of the test name, from which the start and end
    /// is being derived.
    pub const Case = struct {
        /// Name of the test case. Used to identify the file before and after
        /// reduction.
        name: []const u8,
    };

    fn init(gpa: std.mem.Allocator, arena: std.mem.Allocator) TestContext {
        return .{
            .gpa = gpa,
            .arena = arena,
            .cases = std.ArrayList(Case).init(gpa),
        };
    }
    fn deinit(ctx: *TestContext) void {
        ctx.cases.deinit();
        ctx.* = undefined;
    }

    /// Run program and compare output of last reduction with expected output
    fn run(ctx: *TestContext) !void {
        var progress = std.Progress{};
        const root_node = progress.start("reduction", ctx.cases.items.len);
        defer root_node.end();

        var beforepath_buf: [1000]u8 = undefined;
        var afterpath_buf: [1000]u8 = undefined;

        _ = beforepath_buf;
        _ = afterpath_buf;
        std.debug.print("running {s}\n", .{ctx.cases.items[0].name});

        // TODO finish up
        // "test/initial_reduction/minimal_b.zig",
        // "test/initial_reduction/minimal_a.zig",

        // parse results, then compare against expected

        // add more examples
    }
};
