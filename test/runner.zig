const std = @import("std");

pub fn main() !void {
    var general_purpose_allocator = std.heap.GeneralPurposeAllocator(.{}){};
    const gpa = general_purpose_allocator.allocator();
    defer if (general_purpose_allocator.deinit()) std.process.exit(1);

    var args = try std.process.argsAlloc(gpa);
    defer std.process.argsFree(gpa, args);

    if (args.len != 4) {
        std.debug.print("expected arguments 1. reduze executable, 2. zig executable, 3. test case dir\n", .{});
        return error.InvalidArguments;
    }

    var buf = std.ArrayList(u8).init(gpa);
    var cases = std.ArrayList([]const u8).init(gpa);

    // collect all cases (with input and output relation)
    {
        var cases_dir = try std.fs.cwd().openIterableDir(args[3], .{});
        defer cases_dir.close();

        var it = cases_dir.iterate();
        while (try it.next()) |entry| {
            if (entry.kind == .Directory) continue;
            if (entry.kind != .File) {
                std.debug.print("found non file entry '{s}'\n", .{entry.name});
                return error.InvalidEntryInCasesDir;
            }

            defer buf.items.len = 0;
            // TODO: add logic for input <-> output pairs
            // and ignore logic for previous files with postfix _0 _1 _2 etc.
            try buf.writer().print("{s}{c}{s}", .{ args[3], std.fs.path.sep, entry.name });
            try cases.append(try gpa.dupe(u8, buf.items));
        }
    }
    // if (build_options.test_all_allocation_failures) {
    //     return testAllAllocationFailures(cases.items);
    // }

    var progress = std.Progress{};
    const root_node = progress.start("Test", cases.items.len);
    var ok_count: u32 = 0;
    var fail_count: u32 = 0;
    var skip_count: u32 = 0;

    for (cases.items) |path| {
        const case = std.mem.sliceTo(std.fs.path.basename(path), '.');
        var case_node = root_node.start(case, 0);
        case_node.activate();
        defer case_node.end();
        progress.refresh();

        const exec_res = try std.ChildProcess.exec(gpa, &.{ args[0], args[1], path });
        if (exec_res.term != .Exited or exec_res.term.Exited != 0) {
            fail_count += 1;
        }

        // TODO: call lib with correct steps

        // std.debug.print("expected arguments 1. reduze executable, 2. zig executable, 3. test case dir\n", .{});

        // 1. run item case and store output (later to be parallelized)
        // 2. compare output (path is send to testrunner)
        // 3. test runner compares expected output and output
        //    * if difference or unexpected error by child, print path to file + some context

        // ./zig-out/bin/reduze  -h | inputfile [prefixpath]
    }

    root_node.end();
    if (ok_count == cases.items.len and skip_count == 0) {
        std.debug.print("All {d} tests passed.\n", .{ok_count});
    } else if (fail_count == 0) {
        std.debug.print("{d} passed; {d} skipped.\n", .{ ok_count, skip_count });
    } else {
        std.debug.print("{d} passed; {d} failed.\n\n", .{ ok_count, fail_count });
        std.process.exit(1);
    }
}
