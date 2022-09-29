
fn approachWithSema() !void {
    {
        // From here on analysis is more costly, so we need to sort the skip list
        // by indices on addition and merge skip list ranges.
        var filepathbuf: [FILEPATHBUF]u8 = undefined;
        const filepath = try combineFilePath(filepathbuf[0..], config, &state);
        var parsed = try openAndParseFile(gpa, filepath);
        defer gpa.free(parsed.source);
        defer parsed.tree.deinit(gpa);

        // Algorithm for building + unexpected runtime behavior:
        // As simplification for now, we
        // 1. index every symbol with code from ztags and store the offsets + amount
        // 2. repeat until no unexpected runtime behavior:
        //    - 2.1. unused global scope symbols are removed
        //    - 2.2. go from end to start of each test block statement by statement along control flow
        //    - 2.3. remove
        // 3. assume that we have now found the origin of the error
        //    - validate this and print success
        //    - without more semantic information we can not proceed on this
        //   => forward slicing boils down to identifying the code, which
        //      does not affect the result:
        //      * var a: u32 = 0;
        //      * std.debug.print("duck{d}\n",.{a});
        //      * std.debug.print("duck\n",.{});
        //        + before trying, this only applies to reading and we need
        //   => If we want to aggressively reduce, we assume the code is
        //      side-effect free and `writeAll` have no effect.
        //      * In theory this can be simulated by replacing writes and reads
        //        with memory and fseek with a counter

        // 2.
        // TODO: poke to resolve packages
        // 1. search for import
        //
        // Each block looks with 3 branches like this:
        //         *
        //       / | \
        //      /\ | /\
        // Here the 2. branch has no children.
        // It is undecidable, which branches are to be removed or we would need
        // Zir information.
        //
        //
        // * iterate into each block + remember if we are comptime
        //    * delete one or the other scope
        //    * PROBLEM:
        //      - distinguishment between
        //

    }
    {
        // From here on analysis is more costly, so we need to sort the skip list
        // by indices on addition and merge skip list ranges.
        // The main advantage is that once we have Zir or better information,
        // we can directly apply liveness, tracing and control flow information.
        //
        // Algorithm for building + unexpected runtime behavior:
        // As simplification for now, we
        // 1. index every symbol with code from ztags and store the offsets + amount
        // 2. repeat until no unexpected runtime behavior:
        //    - 2.1. unused global scope symbols are removed
        //    - 2.2. go from end to start of each test block statement by statement along control flow
        //    - 2.3. remove
        // 3. assume that we have now found the origin of the error
        //    - validate this and print success
        //    - without more semantic information we can not proceed on this
        //   => forward slicing boils down to identifying the code, which
        //      does not affect the result:
        //      * var a: u32 = 0;
        //      * std.debug.print("duck{d}\n",.{a});
        //      * std.debug.print("duck\n",.{});
        //        + before trying, this only applies to reading and we need
        //   => If we want to aggressively reduce, we assume the code is
        //      side-effect free and `writeAll` have no effect.
        //      * In theory this can be simulated by replacing writes and reads
        //        with memory and fseek with a counter

        var filepathbuf: [FILEPATHBUF]u8 = undefined;
        const filepath = try combineFilePath(filepathbuf[0..], config, &state);
        var parsed = try openAndParseFile(gpa, filepath);
        defer gpa.free(parsed.source);
        defer parsed.tree.deinit(gpa);
        // 2.
        // TODO: poke to resolve packages
        // 1. search for import
        //
        // Each block looks with 3 branches like this:
        //         *
        //       / | \
        //      /\ | /\
        // Here the 2. branch has no children.
        // It is undecidable, which branches are to be removed or we would need
        // Zir information.
        //
        //
        // * iterate into each block + remember if we are comptime
        //    * delete one or the other scope
        //    * PROBLEM:
        //      - distinguishment between
        //

    }
