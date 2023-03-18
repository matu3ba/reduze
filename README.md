#### Delta-debugging for Zig ####

Current status: Vaporware.

1. Assume: Input file is valid Zig code.
2. Test file input.
3. Expected behavior = capture output of reference file.
4. Until semantic information are available, use a simple strategy.
5. Be conservative on deletions to always have valid Zig syntax.
6. Parse compilation errors to simplify complexity, ie to detect unused vars.

#### Usage

```sh
# unit tests (currently unused)
zig build tunit
# reduction tests
zig build tred
```

###### Using semantic info for reduction

There is no official way to get Sema information out of the Zig compiler yet
and partial usage of type info creates many ugly corner cases, so reduction
is not type-based.

###### Packages

Resolving import path from packages requires to "try out which comptime path
a symbol resolves to by removing stuff and looking if result is identical"
or better a Zig interpreter like https://github.com/SuperAuguste/zint
and query the output.
Ideally, the compiler can tell us this info, but Zig is not stabilized yet,
so adding a complex query infrastructure for `Type+Value to Source location`
is unlikely in the near future.

###### Goal: Advanced reduction

The ultimate goal is to rewrite the source code with semantic information.
This would mean to utilize
- 0. Runtime trace (of used source locations) as preliminary step
- 1. Control flow graph
- 2. Symbol usage graph
- 3. Trace for each symbol
- 4. Source locations
- 5. Occurrence of side effects
     (everything, which indirectly calls stuff in `os` except for allocation)
- 6. Elimination strategy for side effects

It is unclear, what kind of representation is optimal as space-time trade-off.
A custom RVSDG https://arxiv.org/abs/1912.05036 would contain all information.
One inspiration for a tracing runner is rr https://github.com/rr-debugger/rr,
but rr is not portable.
Other solutions rely on modifying the code itself, which sounds like significant
additional complexity.

So this needs more research, when a "runner that prints something" is faster
or when "analysis" is better and what the complexity price is.

My gut feeling on this is that tightly coupled functions are faster to analyze,
but loosely coupled ones are faster with a separation and runner (with native backend)
due to less combinations being necessary.

Side-effects, especially of parallelized or asynchronous related behavior,
require manual intervention + more statistics.

###### (For now) Rejected ideas

- Use an index to remember which AST nodes should not be rendered

Idea: The simplest way to remove code, which is stored in memory, is to
not print it via `render.zig` and keep track of this.

Keeping track inside `render.zig` is very complex, because rendering works
via recursive traversal of the source code.
This is unlikely to change in the near future with the same justification of
the change of the iterative parser into a recursive one: Maintenance costs
are lower.
Further more, the spacing and bracket logic inside `render.zig` is complex.

- In-place modification of the AST

Idea: we can store separately an index into the AST of valid and invalid nodes
and modify internally the node structure to delete individual nodes.
Then node traversal could use the existing render infrastructure (render.zig).

If we already have the index into AST nodes, then we also have the TokenRange
and execution of `render.zig` is slower than slicing + printing the file already
stored inside memory.
Further more, `render.zig` invalidates the TokenRange due to formatting, which
in turn requires reparsing the emitted file to get correct AST info into the
source locations.

- Construction of a simplified AST

Idea: The C backend has a simplified AST, for which nodes are much simpler to
add or remove.

The simplified AST can not express `try` and other Zig-specific things like
`break` to a decl.
This makes is unsuitable as target for an AST-to-simplified AST translation.
This is a potential long-term solution, but in the long-term attaching semantic
information for more complex structures is needed.
Thus this is deferred due to complexity and additional upstream maintenance 
until the requirements becomes more clear.
