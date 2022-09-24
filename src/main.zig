const std = @import("std");
const cli_args = @import("cli_args.zig");

pub const Config = struct {
    in_path: []const u8,
    out_path: []const u8 = "/tmp/",
};

const Fail = enum {
    Compile,
    Run,
};

const InBehave = struct {
    fail: Fail,
    exec_res: std.ChildProcess.ExecResult,
};

const State = struct {
    out_nr: u64,
    //split_queue
    flist: []*?std.fs.File,
    fn init() State {
        return State{
            .out_nr = 0,
            .flist = undefined,
        };
    }
};

const stdout = std.io.getStdOut();
const stderr = std.io.getStdErr();

// 1. test file input
// 2. expected behavior = capture output of reference file
// 3. reduction strategies
// -  1. remove test blocks
// (4. validation strategy of step 3)

pub fn main() !void {
    var arena_instance = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena_instance.deinit();
    const arena = arena_instance.allocator();

    const args = try std.process.argsAlloc(arena);
    defer std.process.argsFree(arena, args);

    var config = try cli_args.validateArgs(args);
    var in_behave = InBehave{
        .fail = Fail.Compile,
        .exec_res = undefined,
    };
    // 1. capture output: Due to --test-no-exec we dont need seperation between
    // compiling and running. However, this may change on more complex build steps.

    // TODO fix https://github.com/ziglang/zig/issues/7441
    // for not spamming the ramdisk with stuff
    const exp_res_comp = try std.ChildProcess.exec(.{
        .allocator = arena,
        .argv = &[_][]const u8{ "zig", "test", "--test-no-exec", config.in_path },
    });
    if (exp_res_comp.term.Exited != 0) {
        in_behave.fail = Fail.Compile;
        in_behave.exec_res = exp_res_comp;

        try mainLogic(&config, &in_behave);
        std.process.exit(0);
    }

    //try std_out.writer().print("term : {}\nstdout: {s}\nstderr: {s}\n", .{ exp_res.term, exp_res.stdout, exp_res.stderr });
    const exp_res_run = try std.ChildProcess.exec(.{
        .allocator = arena,
        .argv = &[_][]const u8{ "zig", "test", config.in_path },
    });

    in_behave.fail = Fail.Run;
    in_behave.exec_res = exp_res_run;

    try mainLogic(&config, &in_behave);
    std.process.exit(0);
}

pub fn fatal(comptime format: []const u8, args: anytype) noreturn {
    std.log.err(format, args);
    std.process.exit(1);
}

const Parsed = struct {
    source: [:0]u8,
    tree: std.zig.Ast,
};

// caller owns memery of Ast
fn openAndParseFile(alloc: std.mem.Allocator, in_file: []const u8) !Parsed {
    var f = std.fs.cwd().openFile(in_file, .{}) catch |err| {
        fatal("unable to open file for zig-reduce '{s}': {s}", .{ in_file, @errorName(err) });
    };
    defer f.close();
    const stat = try f.stat();
    if (stat.size > std.math.maxInt(u32))
        return error.FileTooBig;
    const source = try alloc.allocSentinel(u8, @intCast(usize, stat.size), 0);
    errdefer alloc.free(source);
    const amt = try f.readAll(source);
    if (amt <= 1)
        return error.EmptyFile;
    if (amt != stat.size)
        return error.UnexpectedEndOfFile;
    var tree = try std.zig.parse(alloc, source);
    return Parsed{
        .source = source,
        .tree = tree,
    };
}

fn mainLogic(config: *Config, in_beh: *InBehave) !void {
    var general_purpose_allocator = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(!general_purpose_allocator.deinit());
    const gpa = general_purpose_allocator.allocator();

    var parsed = try openAndParseFile(gpa, config.in_path); // input file assumed to be valid Zig
    defer gpa.free(parsed.source);
    defer parsed.tree.deinit(gpa);

    std.debug.assert(in_beh.fail == Fail.Run);
    // 1. test block reduction

    const members = parsed.tree.rootDecls(); // Ast.Node.Index
    std.debug.assert(members.len > 0);
    for (members) |member| {
        const main_tokens = parsed.tree.nodes.items(.main_token);
        const datas = parsed.tree.nodes.items(.data);
        const node_tags = parsed.tree.nodes.items(.tag);
        const decl = member;
        switch (parsed.tree.nodes.items(.tag)[decl]) {
            .test_decl => {
                const test_token = main_tokens[decl];
                const src_loc = parsed.tree.tokenLocation(0, test_token);
                // test "text" or test func_decl
                std.debug.print("src_loc. line: {d}, col: {d}\n", .{ src_loc.line, src_loc.column });
                std.debug.print("src_loc. line_start: {d}, line_end: {d}\n", .{ src_loc.line_start, src_loc.line_end });
                // {} brackets + ;-separated statements inside
                const node = datas[decl].rhs; // std.Ast.Node.Index
                std.debug.assert(node_tags[node] == .block_two_semicolon);
                const block_node = node;
                const lbrace = parsed.tree.nodes.items(.main_token)[block_node];
                const lbrace_srcloc = parsed.tree.tokenLocation(0, lbrace);
                std.debug.print("lbrace_srcloc. line: {d}, col: {d}\n", .{ lbrace_srcloc.line, lbrace_srcloc.column });
                std.debug.print("lbrace_srcloc. line_start: {d}, line_end: {d}\n", .{ lbrace_srcloc.line_start, lbrace_srcloc.line_end });
                const rbrace = parsed.tree.lastToken(block_node);
                const rbrace_srcloc = parsed.tree.tokenLocation(0, rbrace);
                std.debug.print("rbrace_srcloc. line: {d}, col: {d}\n", .{ rbrace_srcloc.line, rbrace_srcloc.column });
                std.debug.print("rbrace_srcloc. line_start: {d}, line_end: {d}\n", .{ rbrace_srcloc.line_start, rbrace_srcloc.line_end });
            },
            else => {},
        }
    }
    // queue to iterate through all member of rootDecls
}

// void llvm::runDeltaPasses(TestRunner &Tester, int MaxPassIterations) {
//   uint64_t OldComplexity = Tester.getProgram().getComplexityScore();
//   for (int Iter = 0; Iter < MaxPassIterations; ++Iter) {
//     if (DeltaPasses.empty()) {
//       runAllDeltaPasses(Tester);
//     } else {
//       StringRef Passes = DeltaPasses;
//       while (!Passes.empty()) {
//         auto Split = Passes.split(",");
//         runDeltaPassName(Tester, Split.first);
//         Passes = Split.second;
//       }
//     }
//     uint64_t NewComplexity = Tester.getProgram().getComplexityScore();
//     if (NewComplexity >= OldComplexity)
//       break;
//     OldComplexity = NewComplexity;
//   }
// }

// llvm-reduce getComplexityScore
fn qualityEstimation() void {}

fn runDeltaPasses() void {
    // based on MaxPassIterations

}

/// Removes block by block: strict monotonic
/// assume: tests have no side effects
/// uses skip list internally: skip removal of test block, if error can not be
/// reproduced
fn testBlockReduction() void {
    // TODO: get start and end location of test block
}

test "simple test" {
    var list = std.ArrayList(i32).init(std.testing.allocator);
    defer list.deinit(); // try commenting this out and see if zig detects the memory leak!
    try list.append(42);
    try std.testing.expectEqual(@as(i32, 42), list.pop());
}
