const std = @import("std");
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
