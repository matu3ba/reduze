const std = @import("std");
const main = @import("main.zig");
const Config = main.Config;

const stdout = std.io.getStdOut();
const stderr = std.io.getStdErr();

const usage: []const u8 =
    \\ -h | inputfile [prefixpath]
    \\ For now, only test blocks are supported.
;

const validateArgsErrorr = std.fs.File.OpenError;

pub fn validateArgs(args: [][]const u8) !Config {
    if (args.len <= 1) {
        try stderr.writer().print("Usage: {s} {s}\n", .{ args[0], usage });
        std.process.exit(0);
    }
    if (args.len < 2 or 3 < args.len) {
        try stderr.writer().print("Usage: {s} {s}\n", .{ args[0], usage });
        std.process.exit(0);
    }
    if (std.mem.eql(u8, args[1], "-h")) {
        try stdout.writer().print("Usage: {s} {s}\n", .{ args[0], usage });
        std.process.exit(0);
    }
    var config = main.Config{
        .in_path = args[1],
        .out_path = "tmp/",
    };

    if (args.len == 3) config.out_path = args[2];
    return config;
    // if (args.len >= 255) {
    //     try stdout.writer().writeAll("At maximum 255 arguments are supported\n");
    //     process.exit(1);
    // }
    // var i: u64 = 1; // skip program name
    // while (i < args.len) : (i += 1) {
    // }
}
