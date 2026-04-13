const voxgig_struct = @import("voxgig-struct");

// Re-export library tests so `zig build test` runs them.
test {
    _ = voxgig_struct;
}
