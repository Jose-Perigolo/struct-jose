// RUN: zig build test
// RUN-SOME: zig build test 2>&1 | head

// Test structure mirrors ts/test/utility/StructUtility.test.ts
// Uses shared spec from build/test/test.json via runner.

const std = @import("std");
const testing = std.testing;

const voxgig_struct = @import("voxgig-struct");
const runner = @import("runner.zig");

const JsonValue = std.json.Value;

// NOTE: tests are (mostly) in order of increasing dependence.

// Wrap library functions as runner.Subject (fn(JsonValue) JsonValue).

fn wrap_isnode(val: JsonValue) JsonValue {
    return .{ .bool = voxgig_struct.isnode(val) };
}

fn wrap_ismap(val: JsonValue) JsonValue {
    return .{ .bool = voxgig_struct.ismap(val) };
}

fn wrap_islist(val: JsonValue) JsonValue {
    return .{ .bool = voxgig_struct.islist(val) };
}

fn wrap_iskey(val: JsonValue) JsonValue {
    return .{ .bool = voxgig_struct.iskey(val) };
}

fn wrap_isempty(val: JsonValue) JsonValue {
    return .{ .bool = voxgig_struct.isempty(val) };
}

fn wrap_isfunc(val: JsonValue) JsonValue {
    return .{ .bool = voxgig_struct.isfunc(val) };
}

// Helper: get a nested spec section.
fn getMinorSpec(r: runner.RunPack, name: []const u8) !JsonValue {
    const minor = r.spec.get("minor") orelse return error.NoMinorSpec;
    return switch (minor) {
        .object => |obj| obj.get(name) orelse return error.NoSpec,
        else => return error.MinorNotObject,
    };
}

// ---- minor tests ----

test "minor-isnode" {
    var r = try runner.makeRunner(testing.allocator);
    defer r.deinit();
    try r.runset(try getMinorSpec(r, "isnode"), wrap_isnode);
}

test "minor-ismap" {
    var r = try runner.makeRunner(testing.allocator);
    defer r.deinit();
    try r.runset(try getMinorSpec(r, "ismap"), wrap_ismap);
}

test "minor-islist" {
    var r = try runner.makeRunner(testing.allocator);
    defer r.deinit();
    try r.runset(try getMinorSpec(r, "islist"), wrap_islist);
}

test "minor-iskey" {
    var r = try runner.makeRunner(testing.allocator);
    defer r.deinit();
    try r.runsetflags(try getMinorSpec(r, "iskey"), .{ .null_flag = false }, wrap_iskey);
}

test "minor-isempty" {
    var r = try runner.makeRunner(testing.allocator);
    defer r.deinit();
    try r.runsetflags(try getMinorSpec(r, "isempty"), .{ .null_flag = false }, wrap_isempty);
}

test "minor-isfunc" {
    var r = try runner.makeRunner(testing.allocator);
    defer r.deinit();
    try r.runset(try getMinorSpec(r, "isfunc"), wrap_isfunc);
}
