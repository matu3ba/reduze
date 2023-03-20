//! State of reduction program to speedup diagnosis and rerunning
//! assume: Steps from one state to another are reproducible via execution policy.
//! assume: Statement based reduction.
const std = @import("std");
const State = @This();

pub const Fail = enum {
    Compile,
    Run,
    NoFail,
};

pub const RangeEntry = struct {
    /// input file path of original file
    /// used one is either 1. NUMBERoriginal.zig, where NUMBER is used index.
    /// or 2. a tmp file generated from the previous tmp file + action
    /// or 3. a tmp file generated from history
    filepaths_i: u32,
    /// skip begin
    begin: u32,
    /// skip end
    end: u32,
    /// null means reduction step is incomplete due to pending fixups
    reduce_ok: ?bool,
    /// last step leading to generation of this entry (also easifies reverse-stack generation)
    parent_entry: ?u32,
};

pub const StackEntry = struct {
    rentry: RangeEntry,
    hist_i: u32,
};

/// append-only list of filepaths
filepaths: std.ArrayList([]const u8),
/// append-only reduction history (successes and failures on reduction)
history: std.ArrayList(RangeEntry),
/// indexes into history with reduce_ok=true (if not exist reduce_ok=null) sorted by skip_begin
/// invariant: for all i,j: (i!=j and skip_begin_i < skip_begin_j => skip_end_i < skip_end_j),
/// invariant: for all i,j: (i!=j and skip_begin_i < skip_begin_j => skip_end_i < skip_begin_j),
sorted_skips: std.ArrayList(u32),
/// Logical stack of program steps to track and replay (neccessary) follow-up reductions
/// outside of current scope. Reduction is always from last to first item of a scope.
step_stack: std.ArrayList(StackEntry),

// Note: Symbol locations are planned to be lazily computed via zls to keep the
// state and complexity simple.

// Example growing downwards for simplicity:
// toplvl_block8 + history_index
// block1 + history_indexstory
// test_block + history_indexstory
// stmt10 + history_indexstory for fixup

/// cli input path to root file (test blocks or start or main)
cli_path: ?[]const u8,
/// final result output path
result_dir_path: ?[]const u8,
/// final result output Dir + handle
result_dir: ?std.fs.Dir,
/// type of failure on running executable defined by cli_path
fail_t: ?Fail,
/// result of running executable defined by cli_path
run_res: std.ChildProcess.ExecResult,

pub fn init(alloc: std.mem.Allocator) State {
    return .{
        .filepaths = std.ArrayList([]const u8).init(alloc),
        .history = std.ArrayList(RangeEntry).init(alloc),
        .sorted_skips = std.ArrayList(u32).init(alloc),
        .step_stack = std.ArrayList(StackEntry).init(alloc),
        .cli_path = null,
        .result_dir_path = null,
        .result_dir = null,
        .fail_t = null,
        .run_res = undefined,
    };
}

pub fn deinit(state: *State) void {
    state.filepaths.deinit();
    state.history.deinit();
    state.sorted_skips.deinit();
    state.step_stack.deinit();
    if (state.result_dir != null) {
        state.result_dir.?.close();
    }
}
