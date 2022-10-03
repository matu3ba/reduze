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

fn countTestBlocks(parsed: *Parsed) u32 {
    // TODO: fixup for arbitrary test blocks
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
    return cnt_roottest;
}

/// Must be called with cnt_roottest generated from countTestBlocks
/// Caller owns memory.
fn getTestBlockDecls(alloc: std.mem.Allocator, parsed: *Parsed, cnt_roottest: u32) ![]std.zig.Ast.TokenIndex {
    var decls = try std.ArrayList(std.zig.Ast.TokenIndex).initCapacity(alloc, cnt_roottest);
    defer decls.deinit();
    const members = parsed.tree.rootDecls(); // Ast.Node.Index
    for (members) |member| {
        const decl = member;
        switch (parsed.tree.nodes.items(.tag)[decl]) {
            .test_decl => {
                decls.appendAssumeCapacity(decl);
            },
            else => {},
        }
    }
    std.debug.assert(cnt_roottest == decls.items.len);
    return decls.toOwnedSlice();
}

/// Must be called with cnt_roottest generated from countTestBlocks
/// Caller owns memory.
fn getTestBlockRanges(alloc: std.mem.Allocator, parsed: *Parsed, cnt_roottest: u32) ![]TokenRange {
    // TODO: fixup for arbitrary test blocks
    var test_blocks = try std.ArrayList(TokenRange).initCapacity(alloc, cnt_roottest);
    defer test_blocks.deinit();
    const members = parsed.tree.rootDecls(); // Ast.Node.Index
    for (members) |member| {
        const main_tokens = parsed.tree.nodes.items(.main_token);
        const datas = parsed.tree.nodes.items(.data);
        const node_tags = parsed.tree.nodes.items(.tag);
        const decl = member;
        switch (node_tags[decl]) {
            .test_decl => {
                const node = datas[decl].rhs; // std.Ast.Node.Index
                std.debug.assert(isBlock(parsed.tree, node));
                // std.debug.assert(node_tags[node] == .block_two_semicolon);
                const block_node = node;
                const lbrace = main_tokens[block_node];
                const lbrace_srcloc = parsed.tree.tokenLocation(0, lbrace);
                const rbrace = parsed.tree.lastToken(block_node);
                const rbrace_srcloc = parsed.tree.tokenLocation(0, rbrace);

                test_blocks.appendAssumeCapacity(TokenRange{
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
    std.debug.assert(cnt_roottest == test_blocks.items.len);
    return test_blocks.toOwnedSlice();
}

/// Tries to reduce a given statement of the overall file
/// Returns success status.
/// On success, skiplist is appended and skipl_index updated.
/// Caller must handle state change, if wanted.
fn reduceStatement(
    filepath: []const u8,
    parsed: *Parsed,
    config: *Config,
    state: *State,
    skiplist: std.ArrayList(TokenRange),
    skipl_index: std.ArrayList(u32),
    decl: std.Ast.TokenIndex,
) !bool {
    _ = filepath;
    _ = parsed;
    _ = config;
    _ = state;
    _ = skiplist;
    _ = skipl_index;
    _ = decl;
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

    const cnt_roottest = countTestBlocks(parsed);
    const test_blocks = try getTestBlockRanges(arena, parsed, cnt_roottest);
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
        for (test_blocks) |token_range, i| {
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
            std.debug.assert(res_run.term.Exited == 0);
            std.log.debug("'zig test --test-no-exec {s}' compiled", .{filepath});
        }
        {
            const res_run = try std.ChildProcess.exec(.{
                .allocator = arena,
                .argv = &[_][]const u8{ "zig", "test", filepath },
            });
            std.log.debug("'zig test {s}'", .{filepath});
            std.log.debug("expected term_exit: {d}, this term_exit: {d}", .{ in_behave.exec_res.term.Exited, res_run.term.Exited });
            if (in_behave.exec_res.term.Exited == res_run.term.Exited)
                test_blocks[state.out_nr].used = true;
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
    for (test_blocks) |skipentry| {
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
    for (test_blocks) |skipentry| {
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

fn isBlock(tree: std.zig.Ast, node: std.zig.Ast.Node.Index) bool {
    return switch (tree.nodes.items(.tag)[node]) {
        .block_two,
        .block_two_semicolon,
        .block,
        .block_semicolon,
        => true,
        else => false,
    };
}

/// returns a list of statements
pub fn blockStatements(
    tree: std.zig.Ast,
    node: std.zig.Ast.Node.Index,
    buf: *[2]std.zig.Ast.Node.Index,
) ?[]const std.zig.Ast.Node.Index {
    const node_data = tree.nodes.items(.data);
    return switch (tree.nodes.items(.tag)[node]) {
        .block_two, .block_two_semicolon => {
            buf[0] = node_data[node].lhs;
            buf[1] = node_data[node].rhs;
            if (node_data[node].lhs == 0) {
                return buf[0..0];
            } else if (node_data[node].rhs == 0) {
                return buf[0..1];
            } else {
                return buf[0..2];
            }
        },
        .block,
        .block_semicolon,
        => tree.extra_data[node_data[node].lhs..node_data[node].rhs],
        else => return null,
    };
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
        // From here on analysis is slow (bottom up approach):
        // Only removing top-decl, which is used to debug print, would
        // require complex analysis, for which we are missing semantic
        // information to not run into edge cases.
        //
        // Unused object analysis relies on compilation failure message:
        // If `test --test-no-exec` returns "unused error", parse
        // compilation error source locations to remove that object.
        //
        // Strategies:
        // - keep the file and only work with skiplist, because we identified
        //   necessary runtime contexts
        // - reduce imports with _ (heavily used in tests)
        // - bottom-up approach
        //   * from end to start of context:
        //     if (!has_inner_statement)
        //        removeCtx();
        //     else
        //        removeStmt();
        //   * start with end of test block; then traverse control flow

        // TODO: fixup for arbitrary test blocks
        var filepathbuf: [FILEPATHBUF]u8 = undefined;
        var filepath = try combineFilePath(filepathbuf[0..], config, &state);
        var parsed = try openAndParseFile(gpa, filepath);
        defer gpa.free(parsed.source);
        defer parsed.tree.deinit(gpa);

        var arena_instance = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer arena_instance.deinit();
        const arena = arena_instance.allocator();
        const cnt_roottest = countTestBlocks(&parsed);
        const test_block_decls = try getTestBlockDecls(arena, &parsed, cnt_roottest);

        // inserting can be at arbitrary position, but we want not
        // to iterate whole list: keep a separate index into skiplist range
        // |      ▲ ▲  ▲    |
        // |      │ └─┐└┐   |
        //        0   2 1
        // skiplist range insertion order: 0, 1, 2
        // sorting index into skiplist:    0, 2, 1
        var skiplist = try std.ArrayList(TokenRange).initCapacity(gpa, cnt_roottest);
        defer skiplist.deinit();
        var skipl_index = try std.ArrayList(TokenRange).initCapacity(gpa, cnt_roottest);
        defer skipl_index.deinit();

        // tests within tests are forbidden in Zig
        for (test_block_decls) |test_blk_decl| {
            const main_tokens = parsed.tree.nodes.items(.main_token);
            const datas = parsed.tree.nodes.items(.data);
            const node_tags = parsed.tree.nodes.items(.tag);
            const node_index = datas[test_blk_decl].rhs;
            std.log.debug("tag[{d}]: {}", .{ node_index, node_tags[node_index] });

            // only handle statements for now
            if (isBlock(parsed.tree, node_index)) {
                var buffer: [2]std.zig.Ast.Node.Index = undefined;
                var stmt_nodes = blockStatements(parsed.tree, node_index, &buffer).?;
                var i: usize = stmt_nodes.len;
                while (i > 0) {
                    i -= 1;
                    const stmt_node = stmt_nodes[i];
                    const lbrace = main_tokens[stmt_node];
                    const lbrace_srcloc = parsed.tree.tokenLocation(0, lbrace);
                    const rbrace = parsed.tree.lastToken(stmt_node);
                    const rbrace_srcloc = parsed.tree.tokenLocation(0, rbrace);
                    const src_range = parsed.source[lbrace_srcloc.line_start..rbrace_srcloc.line_end];

                    {
                        state.out_nr += 1;
                        //writeFileForStep(filepath, &parsed, config, &state, skiplist, tokenrange);
                        // filepathbuf gets overwritten here
                        //filepath = try combineFilePath(filepathbuf[0..], config, &state);
                        var file = try std.fs.cwd().createFile(filepath, .{});
                        defer file.close();

                        const res_run = try std.ChildProcess.exec(.{
                            .allocator = arena,
                            .argv = &[_][]const u8{ "zig", "test", "--test-no-exec", filepath },
                        });
                        std.debug.assert(res_run.term.Exited == 0);
                        std.log.debug("'zig test --test-no-exec {s}' compiled", .{filepath});
                    }

                    try skiplist.append(TokenRange{
                        .start = lbrace_srcloc.line_start,
                        .end = rbrace_srcloc.line_end,
                        .used = true,
                    });
                    std.sort.sort(TokenRange, skiplist.items, {}, sortTokenRange);
                    std.debug.print("stmt {d}: {s}\n", .{ i, src_range });
                }
            }
        }

        // TODO
        // - resolve packages: Sema as it relies on comptime
        //   Zir: import, c_import, no Zir: @This
        // - index all symbols
        // figure out how to store control flow
        // TODO

    }
}

/// assume: distinct TokenRanges
/// |----|
///      |----|
pub fn sortTokenRange(context: void, a: TokenRange, b: TokenRange) bool {
    _ = context;
    return a.start < b.start;
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
