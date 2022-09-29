const std = @import("std");
const useless_import1 = std.debug;
const useless_import2 = @import("builtin");
test "failure1" {
    std.debug.print("helpme123\n", .{});
    std.debug.assert(false);
}

test "failure11" {
    std.debug.print("helpme123\n", .{});
    std.debug.assert(false);
}
test "failure2" {
    std.debug.print("helpme123\n", .{});
}
test "failure3" {
    std.debug.print("helpme123\n", .{});
}

test failure4 {
    std.debug.print("helpme123\n", .{});
}
fn failure4() void {}

const st1 = struct {
    s: u8,
    test "st1" {
        std.debug.print("helpme123\n", .{});
    }
};
