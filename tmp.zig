const std = @import("std");
const useless_import1 = std.debug;
const useless_import2 = @import("builtin");
test "failure1" {
    std.debug.assert(false);
    std.debug.print("helpme1\n", .{});
    std.debug.assert(false);
}

fn failure4() void {}

const st1 = struct {
    s: u8,
    test "st1" {
        std.debug.print("helpme123\n", .{});
    }
};
