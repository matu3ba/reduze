//! Utility functions for simpler AST handling. Since traversing AST is anyway
//! necessary, make it more otpimal with an explicit stack.
const std = @import("std");
const main = @import("main.zig");
const Ast = std.zig.Ast;

const AstStack = struct {
    /// Nodes range of Ast
    nodes: []const Ast.Node.Index,
    /// Index into nodes range of Ast for traversal
    /// Number-1 represents node range last completed visiting.
    /// 1 means node 0 has been visited including the children.
    nodes_i: u32,
};

/// Count test blocks without allocation via DFS
// error{OutOfMemory}
pub fn countTestBlocks(parsed: *main.Parsed) !u32 {
    var cnt_roottest: u32 = 0;
    const reserved_size = 4 * std.mem.page_size; // 4KB for perf.
    var testblock_buffer: [reserved_size]u8 = undefined;
    var fixedbuf_decl = std.heap.FixedBufferAllocator.init(&testblock_buffer);
    const testblock_alloc = fixedbuf_decl.allocator();
    var stack_decls = std.ArrayList(AstStack).init(testblock_alloc);
    defer stack_decls.deinit();

    const members = parsed.tree.rootDecls(); // Ast.Node.Index
    std.debug.assert(members.len > 0);
    try stack_decls.append(.{ .nodes = members, .nodes_i = 0 });

    // a
    // a    b    c
    // abcc def ghi
    //

    while (stack_decls.items.len > 0) dfs_push: {
        std.log.debug("stack_el num: {d}", .{stack_decls.items.len - 1});
        var stack_el: AstStack = stack_decls.items[stack_decls.items.len - 1];
        // cases
        // - 1. non-nesting stack_el => continue loop
        // - 2. nesting stack_el => add stack_el to stack and jump to start of loop
        //      without pop stack_el
        // - 3. no stack_els or end of loop => pop stack_el + update parent to look into next item

        // std.log.debug("enter range: [{d},{d}]", .{stack_decls[0], stack_decls[stack_decls.items.len-1]});
        while (stack_el.nodes_i < stack_el.nodes.len) {
            const node_tags = parsed.tree.nodes.items(.tag);
            const datas = parsed.tree.nodes.items(.data);

            const node = stack_el.nodes[stack_el.nodes_i];
            std.log.debug("stack_el.nodes_i: {d}, node {d} tag {}", .{ stack_el.nodes_i, stack_el.nodes[stack_el.nodes_i], node_tags[node] });
            try printRange(node, parsed, &main.stdout);
            std.debug.print("stack before execution[nodes_i [nodes_startptr, nodes_len]]:\n", .{});
            for (stack_decls.items) |prstack_item| {
                std.debug.print("[nodes_i {d} [nodes {*}, {d}]]", .{ prstack_item.nodes_i, &prstack_item.nodes[0], prstack_item.nodes.len });
            }
            std.debug.print("\n", .{});
            // std.log.debug("", .{  });
            // var inc_nodes: u8 = 0;
            var dfs_push = false;
            switch (node_tags[node]) {
                .root => {},
                .test_decl => {
                    cnt_roottest += 1;
                    std.log.debug("found test_decl, new count: {d}", .{cnt_roottest});
                    // inc_nodes = 1;
                },
                .block,
                .block_semicolon,
                => {
                    const statements = parsed.tree.extra_data[datas[node].lhs..datas[node].rhs];
                    try stack_decls.append(.{ .nodes = statements[0..], .nodes_i = 0 });
                    // inc_nodes = 1;
                    dfs_push = true;
                },
                .block_two,
                .block_two_semicolon,
                => {
                    const statements = [2]Ast.Node.Index{ datas[node].lhs, datas[node].rhs };
                    if (datas[node].lhs == 0) {
                        try stack_decls.append(.{ .nodes = statements[0..0], .nodes_i = 0 });
                        std.log.debug("0 container members", .{});
                    } else if (datas[node].rhs == 0) {
                        try stack_decls.append(.{ .nodes = statements[0..1], .nodes_i = 0 });
                        std.log.debug("1 container members", .{});
                    } else {
                        try stack_decls.append(.{ .nodes = statements[0..2], .nodes_i = 0 });
                        std.log.debug("2 container members", .{});
                    }
                    // inc_nodes = 1;
                    dfs_push = true;
                },
                .simple_var_decl => {
                    const node_slice = [1]Ast.Node.Index{datas[node].rhs};
                    try stack_decls.append(.{ .nodes = &node_slice, .nodes_i = 0 });
                    // inc_nodes = 1;
                    dfs_push = true;
                },
                .builtin_call_two => {
                    // inc_nodes = 1;
                },
                .field_access => {
                    // inc_nodes = 1;
                },
                .container_decl_two => {
                    const container_members = [2]Ast.Node.Index{ datas[node].lhs, datas[node].rhs };
                    if (datas[node].rhs != 0) {
                        try stack_decls.append(.{ .nodes = container_members[0..2], .nodes_i = 0 });
                        std.log.debug("2 container members", .{});
                    } else if (datas[node].lhs != 0) {
                        try stack_decls.append(.{ .nodes = container_members[0..1], .nodes_i = 0 });
                        std.log.debug("1 container members", .{});
                    } else {
                        try stack_decls.append(.{ .nodes = container_members[0..0], .nodes_i = 0 });
                        std.log.debug("0 container members", .{});
                    }
                    // inc_nodes = 1;
                    dfs_push = true;
                },
                .fn_decl => {
                    const fn_members = [1]Ast.Node.Index{datas[node].rhs};
                    try stack_decls.append(.{ .nodes = &fn_members, .nodes_i = 0 });
                    // inc_nodes = 1;
                    dfs_push = true;
                },
                .container_field_init => {
                    // inc_nodes = 1;
                },
                else => {
                    std.log.debug("unimplemented AST node tag {}", .{node_tags[node]});
                    @panic("unimplemented AST node");
                },
            }
            stack_el.nodes_i += 1;
            std.debug.print("stack after execution\n", .{});
            for (stack_decls.items) |prstack_item| {
                std.debug.print("[{d} [{*}, {d}]]", .{ prstack_item.nodes_i, &prstack_item.nodes[0], prstack_item.nodes.len });
            }
            std.debug.print("\n", .{});
            if (dfs_push) {
                std.log.debug("dfs_push", .{});
                break :dfs_push; // step 3
            }
        }
        // case 3 (pop stack element + update parent to look into next item)
        std.log.debug("pop stack element..", .{});
        if (stack_decls.items.len > 1) {
            stack_decls.items[stack_decls.items.len - 2].nodes_i += 1;
        }
        _ = stack_decls.popOrNull();
    }
    std.log.debug("exited loop..", .{});

    return cnt_roottest;
}

/// Must be called with cnt_roottest generated from countTestBlocks
/// Caller owns memory.
pub fn getTestBlockRanges(alloc: std.mem.Allocator, parsed: *main.Parsed, cnt_roottest: u32) ![]main.TokenRange {
    // TODO: fixup for arbitrary test blocks
    var test_blocks = try std.ArrayList(main.TokenRange).initCapacity(alloc, cnt_roottest);
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

                test_blocks.appendAssumeCapacity(main.TokenRange{
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

// TOOD think of how to unify above logic in a simple manner.

/// Must be called with cnt_roottest generated from countTestBlocks
/// Caller owns memory.
fn getTestBlockDecls(alloc: std.mem.Allocator, parsed: *main.Parsed, cnt_roottest: u32) ![]std.zig.Ast.TokenIndex {
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
    // std.debug.assert(cnt_roottest == decls.items.len);
    return decls.toOwnedSlice();
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

inline fn tokenRange(node: std.zig.Ast.Node.Index, parsed: *main.Parsed) []u8 {
    const main_tokens = parsed.tree.nodes.items(.main_token);
    const lbrace = main_tokens[node];
    const lbrace_srcloc = parsed.tree.tokenLocation(0, lbrace);
    const rbrace = parsed.tree.lastToken(node);
    const rbrace_srcloc = parsed.tree.tokenLocation(0, rbrace);
    return parsed.source[lbrace_srcloc.line_start..rbrace_srcloc.line_end];
}

fn printRange(node: std.zig.Ast.Node.Index, parsed: *main.Parsed, file: *const std.fs.File) !void {
    const token_range = tokenRange(node, parsed);
    try file.writeAll(token_range);
    try file.writeAll("\n");
}
