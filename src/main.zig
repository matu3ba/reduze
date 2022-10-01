const std = @import("std");
const cli_args = @import("cli_args.zig");

const FILEPATHBUF = 100;

pub const Config = struct {
    in_path: []const u8,
    out_path: []const u8,
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
    // split_queue
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

// Assume: Input file is valid Zig code
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
    // for not spamming the ramdisk with useless stuff
    // related: How to compile from string without cache?
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

const TokenRange = struct {
    start: usize,
    end: usize,
    used: bool,
};

inline fn combineFilePath(filepathbuf: []u8, config: *Config, state: *State) ![]u8 {
    std.mem.copy(u8, filepathbuf[0..], config.out_path[0..]);
    const pathprefnr = try std.fmt.bufPrint(filepathbuf[config.out_path.len..], "{d}", .{state.out_nr});
    const len_prefix0path = config.out_path.len + pathprefnr.len;
    std.debug.assert(len_prefix0path < filepathbuf.len);
    std.mem.copy(u8, filepathbuf[len_prefix0path..], config.in_path);
    const len_filepath = len_prefix0path + config.in_path.len;
    return filepathbuf[0..len_filepath];
}

/// Reduces test blocks, assume: tests have no side effects (on each other)
///
/// Removes all but one block in each operation for each block, writes file
/// for `zig test` and compares against the expected execution result.
/// Caller owns returned memory
fn testBlockReduction(
    alloc: std.mem.Allocator,
    parsed: *Parsed,
    config: *Config,
    in_behave: *InBehave,
    state: *State,
) ![:0]u8 {
    // TODO: use zig test --test-no-exec, zig test
    std.debug.assert(in_behave.fail == Fail.Run);
    // idea: skip removal of test block, if error can not be reproduced
    var arena_instance = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena_instance.deinit();
    const arena = arena_instance.allocator();

    const members = parsed.tree.rootDecls(); // Ast.Node.Index
    std.debug.assert(members.len > 0);
    var cnt_roottest: u32 = 0;
    for (members) |member| {
        const decl = member;
        switch (parsed.tree.nodes.items(.tag)[decl]) {
            .test_decl => {
                cnt_roottest += 1;
            },
            else => {},
        }
    }
    var test_ranges = try std.ArrayList(TokenRange).initCapacity(arena, cnt_roottest);
    defer test_ranges.deinit();
    for (members) |member| {
        // const main_tokens = parsed.tree.nodes.items(.main_token);
        const datas = parsed.tree.nodes.items(.data);
        const node_tags = parsed.tree.nodes.items(.tag);
        const decl = member;
        switch (parsed.tree.nodes.items(.tag)[decl]) {
            .test_decl => {
                const node = datas[decl].rhs; // std.Ast.Node.Index
                std.debug.assert(node_tags[node] == .block_two_semicolon);
                const block_node = node;
                const lbrace = parsed.tree.nodes.items(.main_token)[block_node];
                const lbrace_srcloc = parsed.tree.tokenLocation(0, lbrace);
                const rbrace = parsed.tree.lastToken(block_node);
                const rbrace_srcloc = parsed.tree.tokenLocation(0, rbrace);

                test_ranges.appendAssumeCapacity(TokenRange{
                    .start = lbrace_srcloc.line_start,
                    .end = rbrace_srcloc.line_end,
                    .used = false,
                });

                // try stdout.writeAll(parsed.source[lbrace_srcloc.line_start..rbrace_srcloc.line_end]);
                // try stdout.writer().writeAll("\n");
            },
            else => {},
        }
    }
    std.debug.assert(cnt_roottest == test_ranges.items.len);

    try std.fs.cwd().makePath(config.out_path);

    // write file to path with only the investigated token_range (without other
    // test blocks) and rest of file
    // Then compile+run to compare if error reproduces
    // TODO: separate state out_nr from loop
    var filepathbuf: [FILEPATHBUF]u8 = undefined;
    while (state.out_nr < cnt_roottest) : (state.out_nr += 1) {
        var print_start: usize = 0;
        const filepath = try combineFilePath(filepathbuf[0..], config, state);
        var file = try std.fs.cwd().createFile(filepath, .{});
        defer file.close();
        for (test_ranges.items) |token_range, i| {
            if (i == state.out_nr) {
                try file.writeAll(parsed.source[print_start..token_range.end]);
                print_start = token_range.end;
                continue;
            }
            try file.writeAll(parsed.source[print_start..token_range.start]);
            print_start = token_range.end;
        }
        if (print_start != parsed.source.len) {
            try file.writeAll(parsed.source[print_start..parsed.source.len]);
            print_start = parsed.source.len;
        }
        {
            const res_run = try std.ChildProcess.exec(.{
                .allocator = arena,
                .argv = &[_][]const u8{ "zig", "test", "--test-no-exec", filepath },
            });
            std.log.debug("zig test {s}\n", .{filepath});
            std.debug.assert(res_run.term.Exited == 0);
        }
        {
            const res_run = try std.ChildProcess.exec(.{
                .allocator = arena,
                .argv = &[_][]const u8{ "zig", "test", filepath },
            });
            std.log.debug("zig test {s}\n", .{filepath});
            std.log.debug("in term_exit: {d}, this term_exit: {d}\n", .{ in_behave.exec_res.term.Exited, res_run.term.Exited });
            if (in_behave.exec_res.term.Exited == res_run.term.Exited)
                test_ranges.items[state.out_nr].used = true;
            // This could also compare the output etc, but keep it simple
        }
    }

    // track from where we last printed to get needed capacity + printing
    // s1         s2
    // -------|xxx|------|------
    // d1
    // -------|------|------
    var src_start: usize = 0;
    var total_len: usize = 0;
    for (test_ranges.items) |skipentry| {
        if (skipentry.used == false) {
            total_len += skipentry.start - src_start;
            src_start = skipentry.end;
        }
    }
    if (src_start != parsed.source.len) {
        total_len += parsed.source.len - src_start;
    }
    var redtest: [:0]u8 = try alloc.allocSentinel(u8, total_len, 0);
    src_start = 0;
    var dest_start: usize = 0;
    for (test_ranges.items) |skipentry| {
        if (skipentry.used == false) {
            std.mem.copy(u8, redtest[dest_start..], parsed.source[src_start..skipentry.start]);
            dest_start = dest_start + (skipentry.start - src_start);
            src_start = skipentry.end;
        }
    }
    if (src_start != parsed.source.len) {
        std.mem.copy(u8, redtest[dest_start..], parsed.source[src_start..]);
    }
    // std.debug.print("total_len {d}, src_start: {d}, parsed_src.len: {d}\n", .{ total_len, src_start, parsed.source.len });

    return redtest;
}

fn mainLogic(config: *Config, in_beh: *InBehave) !void {
    var general_purpose_allocator = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(!general_purpose_allocator.deinit());
    const gpa = general_purpose_allocator.allocator();
    var state = State.init();

    std.debug.assert(in_beh.fail == Fail.Run);
    {
        // reduce root test decls, which should always succeed
        var parsed = try openAndParseFile(gpa, config.in_path);
        defer gpa.free(parsed.source);
        defer parsed.tree.deinit(gpa);

        var testred = try testBlockReduction(gpa, &parsed, config, in_beh, &state);
        defer gpa.free(testred);

        var tree = std.zig.parse(gpa, testred) catch |err| {
            stdout.writer().print("--------INITIAL REDUCTION--------\n{s}---------------------------------\n", .{testred}) catch {};
            fatal("error parsing reduced test: {}", .{err});
        };
        defer tree.deinit(gpa);

        const formatted = try tree.render(gpa);
        defer gpa.free(formatted);

        try stdout.writer().print("--------INITIAL REDUCTION--------\n{s}---------------------------------\n", .{formatted});
        var filepathbuf: [FILEPATHBUF]u8 = undefined;
        const filepath = try combineFilePath(filepathbuf[0..], config, &state);
        var file = try std.fs.cwd().createFile(filepath, .{});
        defer file.close();
        try file.writeAll(formatted);
    }

    {
        // From here on analysis is more costly, so we need to sort the skip list
        // by indices on addition and merge skip list ranges.

        // TODO:
        // - resolve packages (check how autodoc does it with ZIR)
        //   Zir: import, c_import,
        //   no Zir: @This
        // - index all symbols
        // - find all used files
        // - detect unused functions
        // TODO: index all symbols

        // 1. test block reduction
        // queue to iterate through all member of rootDecls
    }
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
