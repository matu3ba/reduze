const std = @import("std");
const main = @import("main.zig");
const State = @import("State.zig");

const stdout = std.io.getStdOut();
const stderr = std.io.getStdErr();

const usage: []const u8 =
    \\ -h | inputfile [prefixpath]
    \\ For now, only test blocks are supported.
;

pub fn validateArgs(args: [][]const u8, state: *State) !void {
    if (args.len <= 1) {
        try stderr.writer().print("Usage: {s} {s}\n", .{ args[0], usage });
        return error.InvalidArguments;
    }
    if (args.len < 2 or 3 < args.len) {
        try stderr.writer().print("Usage: {s} {s}\n", .{ args[0], usage });
        return error.InvalidArguments;
    }
    if (std.mem.eql(u8, args[1], "-h")) {
        try stdout.writer().print("Usage: {s} {s}\n", .{ args[0], usage });
        std.process.exit(0);
    }
    state.cli_path = args[1];
    state.result_dir_path = "tmp/";

    if (args.len == 3) state.result_dir_path = args[2];
}
