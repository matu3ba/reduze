#### Delta-debugging for Zig ####

Current status: Vaporware.

###### Using semantic info for reduction

There is no official way to get Sema information out of the Zig compiler yet
and partial usage of type info creates many ugly corner cases, so reduction 
is not type-based.

###### Packages

Resolving import path from packages requires to "try out which comptime-path
a symbol resolves to by removing stuff and looking if result is identical"
or better a Zig interpreter like https://github.com/SuperAuguste/zint
and query the output.
Ideally, the compiler can tell us this info, but Zig is not stabilized yet,
so adding a complex query infrastructure for `Type+Value to Source location`
is unlikely in the near future.

###### Goal: Advanced reduction

The ultimate goal is to rewrite the source code with semantic information.
This would mean to utilize
- 0. runtime trace (of used source locations) as preliminary step
- 1. control flow graph
- 2. symbol usage graph
- 3. trace for each symbol
- 4. source locations
- 5. occurence of side-effects
     (everything, which indirectly calls stuff in `os` except for allocation)
- 6. elimination strategy for side effects

It is unclear, what kind of representation is optimal as space-time tradeoff.
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
