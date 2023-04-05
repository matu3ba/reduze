// const useless_import1 = std.debug;
// const useless_import2 = @import("builtin");
// test "failure1" {
//     std.debug.print("helpme1\n", .{});
//     std.debug.print("helpme2\n", .{});
//     std.debug.print("helpme3\n", .{});
//     std.debug.print("helpme4\n", .{});
//     std.debug.print("helpme5\n", .{});
//     std.debug.assert(false);
// }

const shouldwork2 = enum {
    test "ok2" {
        @import("std").debug.assert(false);
    }
};
// const shouldwork1 = struct {
//     const shouldalso1 = struct {
//         test "alsook1" {
//             std.debug.assert(false);
//         }
//     };
//     test "ok1" {
//         std.debug.assert(false);
//     }
//     test "ok2" {
//         std.debug.assert(true);
//     }
// };
// const shouldwork3 = union {
//     test "ok3" {
//         std.debug.assert(true);
//     }
// };
//
// test "failure2" {
//     std.debug.print("helpme1\n", .{});
//     std.debug.assert(false);
// }
// fn failure4() void {}

// const st1 = struct {
//     s1: u8,
//     s2: u8,
//     test "st1" {
//         std.debug.print("helpme123\n", .{});
//     }
// };
