const std = @import("std");
test "failure1" {
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
