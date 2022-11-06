const std = @import("std");
const TestContext = @import("../src/test.zig").TestContext;

pub fn addCases(ctx: *TestContext) !void {
    // ---- version 0.1.0 (get things running) ----
    try @import("initial_reduction.zig").addCases(ctx);
    // try @import("inblock_reduction.zig").addCases(ctx);
    // try @import("outblock_reduction.zig").addCases(ctx);
    // try @import("outblock_reduction.zig").addCases(ctx);
    // try @import("error_parse.zig").addCases(ctx);
    // try @import("error_fixup.zig").addCases(ctx);
    // => naive TokenRange approach with "limited and expected compile error" fixups
    // ---- version 0.2.0 (full AST, [parallelized] graph traversal) ----
    // try @import("package_resolve.zig").addCases(ctx);
    // try @import("indexing_symbols.zig").addCases(ctx);
    // try @import("tracing.zig").addCases(ctx);
    // try @import("trace_reduction.zig").addCases(ctx);
    // try @import("graph_construction.zig").addCases(ctx);
    // try @import("graph_reduction.zig").addCases(ctx);
    // => combined trace + graph approach
    // ---- version 0.3.0 (full Sema, speculative) ----
    // try @import("semantic_trace.zig").addCases(ctx);
    // try @import("semtrace_reduction.zig").addCases(ctx);
    // try @import("semantic_graph.zig").addCases(ctx);
    // try @import("semgraph_reduction.zig").addCases(ctx);
    // => combined semtrace + semgraph approach
    // ---- version 1.0.0 (deterministic execution and reasonable simple) ----
    // * only simple program rewrites (eliminate function calls etc)
    // * bring your own compilation/run/fixer steps
    // ---- version x (research things) ----
    // * side effects: occurence and elimination
    // * comptime reduction
    // * assembly, linker graph/tracer and their reduction?
}
