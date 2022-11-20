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
        filepath_before: []const u8,
        filepath_after: []const u8,

        result: anyerror!void = {},
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
        // var env_map = try std.process.getEnvMap(ctx.arena);
        // try env_map.put("ZIG_EXE", self_exe_path);
        const zig_exe_path = try std.process.getEnvVarOwned(ctx.arena, "ZIG_EXE");
        // TODO get reduction executable path to call the respective command
        const red_exe_path = try std.process.getEnvVarOwned(ctx.arena, "RED_EXE");
        var progress = std.Progress{};
        const root_node = progress.start("reduction", ctx.cases.items.len);
        defer root_node.end();

        for (ctx.cases.items) |*case| {
            var prg_node = root_node.start(case.filepath_before, 1);
            prg_node.activate();
            defer prg_node.end();
            // TODO: figure out how to run things
        }

        var fail_count: usize = 0;
        for (ctx.cases.items) |*case| {
            case.result catch |err| {
                fail_count += 1;
                std.debu.print("{s} failed: {s}\n", .{ case.name, @errorName(err) });
            };
        }

        if (fail_count != 0) {
            std.debu.print("{d} tests failed\n", .{fail_count});
            return error.TestFailed;
        }

    }

    // TODO ignore host system
    // fn runOneCase() {
    //         const result = try std.ChildProcess.exec(.{
    //             .allocator = arena,
    //             .argv = zig_args.items,
    //         });
    // }
};
