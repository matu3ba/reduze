//! Utility functions for simpler AST handling. Since traversing AST is anyway
//! necessary, make it more otpimal with an explicit stack.
const std = @import("std");
const main = @import("main.zig");
const Ast = std.zig.Ast;

const AstStack = struct {
    /// nodes range of Ast
    nodes: []const Ast.Node.Index,
    /// index into nodes range of Ast for traversal
    nodes_i: u32,
};

pub fn countTestBlocks(parsed: *main.Parsed) u32 {
    // TODO: fixup for arbitrary nested test blocks, not only top level ones
    // DFS: []const Node.Index + node_index

    const members = parsed.tree.rootDecls(); // Ast.Node.Index
    std.debug.assert(members.len > 0);
    var cnt_roottest: u32 = 0;
    for (members) |member| {
        const decl = member;
        switch (parsed.tree.nodes.items(.tag)[decl]) {
            .test_decl => {
                cnt_roottest += 1;
            },
            else => {},
        }
    }
    return cnt_roottest;
}
