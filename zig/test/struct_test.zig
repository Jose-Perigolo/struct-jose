// RUN: zig build test
// RUN-SOME: zig build test 2>&1 | head

// Test structure mirrors ts/test/utility/StructUtility.test.ts
// Uses shared spec from build/test/test.json via runner.

const std = @import("std");
const testing = std.testing;

const voxgig_struct = @import("voxgig-struct");
const runner = @import("runner.zig");

const Allocator = std.mem.Allocator;
const JsonValue = std.json.Value;
const JsonArray = std.json.Array;

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

// ---- Allocator-aware wrappers for new functions ----

fn wrap_typename(allocator: Allocator, val: JsonValue) JsonValue {
    _ = allocator;
    const t: i64 = switch (val) {
        .integer => |i| i,
        .float => |f| @intFromFloat(f),
        else => return JsonValue{ .string = voxgig_struct.S_any },
    };
    return JsonValue{ .string = voxgig_struct.typename(t) };
}

fn wrap_typify(allocator: Allocator, val: JsonValue) JsonValue {
    _ = allocator;
    // Handle UNDEF marker (missing input → T_noval)
    if (val == .string) {
        if (std.mem.eql(u8, val.string, runner.UNDEFMARK)) {
            return JsonValue{ .integer = @as(i64, voxgig_struct.T_noval) };
        }
    }
    return JsonValue{ .integer = voxgig_struct.typify(val) };
}

fn wrap_size(allocator: Allocator, val: JsonValue) JsonValue {
    _ = allocator;
    return JsonValue{ .integer = voxgig_struct.size(val) };
}

fn wrap_strkey(allocator: Allocator, val: JsonValue) JsonValue {
    const s = voxgig_struct.strkey(allocator, val) catch return JsonValue{ .string = voxgig_struct.S_MT };
    return JsonValue{ .string = s };
}

fn wrap_keysof(allocator: Allocator, val: JsonValue) JsonValue {
    return voxgig_struct.keysof(allocator, val) catch return JsonValue{ .array = JsonArray{} };
}

fn wrap_haskey(allocator: Allocator, val: JsonValue) JsonValue {
    // in: { src, key }
    if (val != .object) return JsonValue{ .bool = false };
    const m = val.object;
    const src = m.get("src") orelse .null;
    const key = m.get("key") orelse .null;
    const result = voxgig_struct.haskey(allocator, src, key) catch return JsonValue{ .bool = false };
    return JsonValue{ .bool = result };
}

fn wrap_items(allocator: Allocator, val: JsonValue) JsonValue {
    return voxgig_struct.items(allocator, val) catch return JsonValue{ .array = JsonArray{} };
}

fn wrap_getelem(allocator: Allocator, val: JsonValue) JsonValue {
    // in: { val, key, alt? }
    if (val != .object) return .null;
    const m = val.object;
    const v = m.get("val") orelse .null;
    const key = m.get("key") orelse return .null;
    const alt = m.get("alt") orelse .null;
    return voxgig_struct.getelem(allocator, v, key, alt) catch return .null;
}

fn wrap_getprop(allocator: Allocator, val: JsonValue) JsonValue {
    // in: { val, key, alt? }
    if (val != .object) return .null;
    const m = val.object;
    const v = m.get("val") orelse .null;
    const key = m.get("key") orelse return .null;
    const alt = m.get("alt") orelse .null;
    return voxgig_struct.getprop(allocator, v, key, alt) catch return .null;
}

fn wrap_clone(allocator: Allocator, val: JsonValue) JsonValue {
    // Handle UNDEF marker - return empty object
    if (val == .string) {
        if (std.mem.eql(u8, val.string, runner.UNDEFMARK)) {
            return .null;
        }
    }
    return voxgig_struct.clone(allocator, val) catch return .null;
}

fn wrap_flatten(allocator: Allocator, val: JsonValue) JsonValue {
    // in: { val, depth? }
    if (val != .object) return .null;
    const m = val.object;
    const v = m.get("val") orelse return .null;
    var depth: i64 = 1;
    if (m.get("depth")) |d| {
        switch (d) {
            .integer => |i| depth = i,
            .float => |f| depth = @intFromFloat(f),
            else => {},
        }
    }
    return voxgig_struct.flatten(allocator, v, depth) catch return .null;
}

fn wrap_filter(allocator: Allocator, val: JsonValue) JsonValue {
    // in: { val, check }
    // check is "gt3" or "lt3" - simple test-only checks
    if (val != .object) return .null;
    const m = val.object;
    const v = m.get("val") orelse return .null;
    const check_name = (m.get("check") orelse return .null).string;

    if (v != .array) return .null;
    const list = v.array.items;

    var result = JsonArray{};
    for (list) |item| {
        const num: f64 = switch (item) {
            .integer => |i| @floatFromInt(i),
            .float => |f| f,
            else => continue,
        };

        const keep = if (std.mem.eql(u8, check_name, "gt3"))
            num > 3
        else if (std.mem.eql(u8, check_name, "lt3"))
            num < 3
        else
            false;

        if (keep) {
            result.append(allocator, item) catch continue;
        }
    }
    return JsonValue{ .array = result };
}

fn wrap_delprop(allocator: Allocator, val: JsonValue) JsonValue {
    // in: { parent, key }
    if (val != .object) return .null;
    const m = val.object;
    const parent = m.get("parent") orelse return .null;
    const key = m.get("key") orelse return parent;
    return voxgig_struct.delprop(allocator, parent, key) catch return parent;
}

fn wrap_setprop(allocator: Allocator, val: JsonValue) JsonValue {
    // in: { parent, key, val }
    if (val != .object) return .null;
    const m = val.object;
    const parent = m.get("parent") orelse return .null;
    const key = m.get("key") orelse return parent;
    const newval = m.get("val") orelse return parent;
    return voxgig_struct.setprop(allocator, parent, key, newval) catch return parent;
}

fn wrap_escre(allocator: Allocator, val: JsonValue) JsonValue {
    const s = switch (val) {
        .string => |str| str,
        else => return JsonValue{ .string = voxgig_struct.S_MT },
    };
    const result = voxgig_struct.escre(allocator, s) catch return JsonValue{ .string = voxgig_struct.S_MT };
    return JsonValue{ .string = result };
}

fn wrap_escurl(allocator: Allocator, val: JsonValue) JsonValue {
    const s = switch (val) {
        .string => |str| str,
        else => return JsonValue{ .string = voxgig_struct.S_MT },
    };
    const result = voxgig_struct.escurl(allocator, s) catch return JsonValue{ .string = voxgig_struct.S_MT };
    return JsonValue{ .string = result };
}

fn wrap_join(allocator: Allocator, val: JsonValue) JsonValue {
    // in: { val, sep?, url? }
    if (val != .object) return JsonValue{ .string = voxgig_struct.S_MT };
    const m = val.object;
    const arr = m.get("val") orelse return JsonValue{ .string = voxgig_struct.S_MT };
    const sep = if (m.get("sep")) |s| switch (s) {
        .string => |str| str,
        else => ",",
    } else ",";
    const urlMode = if (m.get("url")) |u| switch (u) {
        .bool => |b| b,
        else => false,
    } else false;
    const result = voxgig_struct.join(allocator, arr, sep, urlMode) catch return JsonValue{ .string = voxgig_struct.S_MT };
    return JsonValue{ .string = result };
}

fn wrap_jsonify(allocator: Allocator, val: JsonValue) JsonValue {
    // in: { val?, flags?: { indent?, offset? } }
    if (val != .object) return JsonValue{ .string = "null" };
    const m = val.object;
    const v = m.get("val") orelse .null;

    var indent: usize = 2;
    var offset: usize = 0;
    if (m.get("flags")) |flags| {
        if (flags == .object) {
            if (flags.object.get("indent")) |ind| {
                switch (ind) {
                    .integer => |i| indent = @intCast(i),
                    .float => |f| indent = @intFromFloat(f),
                    else => {},
                }
            }
            if (flags.object.get("offset")) |off| {
                switch (off) {
                    .integer => |i| offset = @intCast(i),
                    .float => |f| offset = @intFromFloat(f),
                    else => {},
                }
            }
        }
    }
    const result = voxgig_struct.jsonify(allocator, v, indent, offset) catch return JsonValue{ .string = "null" };
    return JsonValue{ .string = result };
}

fn wrap_stringify(allocator: Allocator, val: JsonValue) JsonValue {
    // in: { val?, max? }
    if (val != .object) return JsonValue{ .string = voxgig_struct.S_MT };
    const m = val.object;
    const v = m.get("val") orelse return JsonValue{ .string = voxgig_struct.S_MT };

    // Handle __NULL__ as "null"
    if (v == .string) {
        if (std.mem.eql(u8, v.string, runner.NULLMARK)) {
            const result = voxgig_struct.stringify(allocator, JsonValue{ .string = "null" }, null) catch return JsonValue{ .string = voxgig_struct.S_MT };
            return JsonValue{ .string = result };
        }
    }

    var maxlen: ?usize = null;
    if (m.get("max")) |max_val| {
        switch (max_val) {
            .integer => |i| maxlen = @intCast(i),
            .float => |f| maxlen = @intFromFloat(f),
            else => {},
        }
    }
    const result = voxgig_struct.stringify(allocator, v, maxlen) catch return JsonValue{ .string = voxgig_struct.S_MT };
    return JsonValue{ .string = result };
}

fn wrap_pathify(allocator: Allocator, val: JsonValue) JsonValue {
    // in: { path?, from? }
    if (val != .object) return JsonValue{ .string = "<unknown-path>" };
    const m = val.object;
    const path = m.get("path") orelse {
        // No path field - return unknown-path
        var result = std.ArrayList(u8).init(allocator);
        result.appendSlice("<unknown-path>") catch return JsonValue{ .string = "<unknown-path>" };
        return JsonValue{ .string = result.items };
    };

    var from: usize = 0;
    if (m.get("from")) |f| {
        switch (f) {
            .integer => |i| from = if (i < 0) 0 else @intCast(i),
            .float => |fv| from = @intFromFloat(@max(0, fv)),
            else => {},
        }
    }
    const result = voxgig_struct.pathify(allocator, path, from, 0) catch return JsonValue{ .string = "<unknown-path>" };
    return JsonValue{ .string = result };
}

fn wrap_slice(allocator: Allocator, val: JsonValue) JsonValue {
    // in: { val, start?, end? }
    if (val != .object) return .null;
    const m = val.object;
    const v = m.get("val") orelse return .null;

    var start: ?i64 = null;
    var end_val: ?i64 = null;
    if (m.get("start")) |s| {
        switch (s) {
            .integer => |i| start = i,
            .float => |f| start = @intFromFloat(f),
            else => {},
        }
    }
    if (m.get("end")) |e| {
        switch (e) {
            .integer => |i| end_val = i,
            .float => |f| end_val = @intFromFloat(f),
            else => {},
        }
    }

    return voxgig_struct.slice(allocator, v, start, end_val) catch return v;
}

fn wrap_pad(allocator: Allocator, val: JsonValue) JsonValue {
    // in: { val, pad?, char? }
    if (val != .object) return JsonValue{ .string = voxgig_struct.S_MT };
    const m = val.object;
    const v = m.get("val") orelse return JsonValue{ .string = voxgig_struct.S_MT };
    const s = switch (v) {
        .string => |str| str,
        else => return JsonValue{ .string = voxgig_struct.S_MT },
    };

    var padding: i64 = 44;
    if (m.get("pad")) |p| {
        switch (p) {
            .integer => |i| padding = i,
            .float => |f| padding = @intFromFloat(f),
            else => {},
        }
    }

    var padchar: u8 = ' ';
    if (m.get("char")) |c| {
        if (c == .string and c.string.len > 0) {
            padchar = c.string[0];
        }
    }

    const result = voxgig_struct.pad(allocator, s, padding, padchar) catch return JsonValue{ .string = voxgig_struct.S_MT };
    return JsonValue{ .string = result };
}

// ---- Allocator-aware minor tests ----

test "minor-typename" {
    var r = try runner.makeRunner(testing.allocator);
    defer r.deinit();
    try r.runsetAlloc(try getMinorSpec(r, "typename"), wrap_typename);
}

test "minor-typify" {
    var r = try runner.makeRunner(testing.allocator);
    defer r.deinit();
    try r.runsetAllocFlags(try getMinorSpec(r, "typify"), .{ .null_flag = false, .undef_as_null = false }, wrap_typify);
}

test "minor-size" {
    var r = try runner.makeRunner(testing.allocator);
    defer r.deinit();
    try r.runsetAllocFlags(try getMinorSpec(r, "size"), .{ .null_flag = false }, wrap_size);
}

test "minor-strkey" {
    var r = try runner.makeRunner(testing.allocator);
    defer r.deinit();
    try r.runsetAllocFlags(try getMinorSpec(r, "strkey"), .{ .null_flag = false }, wrap_strkey);
}

test "minor-keysof" {
    var r = try runner.makeRunner(testing.allocator);
    defer r.deinit();
    try r.runsetAllocFlags(try getMinorSpec(r, "keysof"), .{ .null_flag = false }, wrap_keysof);
}

test "minor-haskey" {
    var r = try runner.makeRunner(testing.allocator);
    defer r.deinit();
    try r.runsetAllocFlags(try getMinorSpec(r, "haskey"), .{ .null_flag = false }, wrap_haskey);
}

test "minor-items" {
    var r = try runner.makeRunner(testing.allocator);
    defer r.deinit();
    try r.runsetAllocFlags(try getMinorSpec(r, "items"), .{ .null_flag = false }, wrap_items);
}

test "minor-getelem" {
    var r = try runner.makeRunner(testing.allocator);
    defer r.deinit();
    try r.runsetAllocFlags(try getMinorSpec(r, "getelem"), .{ .null_flag = false }, wrap_getelem);
}

test "minor-getprop" {
    var r = try runner.makeRunner(testing.allocator);
    defer r.deinit();
    try r.runsetAllocFlags(try getMinorSpec(r, "getprop"), .{ .null_flag = false }, wrap_getprop);
}

test "minor-clone" {
    var r = try runner.makeRunner(testing.allocator);
    defer r.deinit();
    try r.runsetAllocFlags(try getMinorSpec(r, "clone"), .{ .null_flag = false, .undef_as_null = false }, wrap_clone);
}

test "minor-flatten" {
    var r = try runner.makeRunner(testing.allocator);
    defer r.deinit();
    try r.runsetAlloc(try getMinorSpec(r, "flatten"), wrap_flatten);
}

test "minor-filter" {
    var r = try runner.makeRunner(testing.allocator);
    defer r.deinit();
    try r.runsetAlloc(try getMinorSpec(r, "filter"), wrap_filter);
}

test "minor-delprop" {
    var r = try runner.makeRunner(testing.allocator);
    defer r.deinit();
    try r.runsetAllocFlags(try getMinorSpec(r, "delprop"), .{ .null_flag = false }, wrap_delprop);
}

test "minor-setprop" {
    var r = try runner.makeRunner(testing.allocator);
    defer r.deinit();
    try r.runsetAllocFlags(try getMinorSpec(r, "setprop"), .{ .null_flag = false }, wrap_setprop);
}

test "minor-escre" {
    var r = try runner.makeRunner(testing.allocator);
    defer r.deinit();
    try r.runsetAlloc(try getMinorSpec(r, "escre"), wrap_escre);
}

test "minor-escurl" {
    var r = try runner.makeRunner(testing.allocator);
    defer r.deinit();
    try r.runsetAlloc(try getMinorSpec(r, "escurl"), wrap_escurl);
}

test "minor-join" {
    var r = try runner.makeRunner(testing.allocator);
    defer r.deinit();
    try r.runsetAllocFlags(try getMinorSpec(r, "join"), .{ .null_flag = false }, wrap_join);
}

test "minor-jsonify" {
    var r = try runner.makeRunner(testing.allocator);
    defer r.deinit();
    try r.runsetAlloc(try getMinorSpec(r, "jsonify"), wrap_jsonify);
}

test "minor-stringify" {
    var r = try runner.makeRunner(testing.allocator);
    defer r.deinit();
    try r.runsetAllocFlags(try getMinorSpec(r, "stringify"), .{ .null_flag = false }, wrap_stringify);
}

test "minor-pathify" {
    var r = try runner.makeRunner(testing.allocator);
    defer r.deinit();
    try r.runsetAllocFlags(try getMinorSpec(r, "pathify"), .{ .null_flag = false }, wrap_pathify);
}

test "minor-slice" {
    var r = try runner.makeRunner(testing.allocator);
    defer r.deinit();
    try r.runsetAllocFlags(try getMinorSpec(r, "slice"), .{ .null_flag = false }, wrap_slice);
}

test "minor-pad" {
    var r = try runner.makeRunner(testing.allocator);
    defer r.deinit();
    try r.runsetAllocFlags(try getMinorSpec(r, "pad"), .{ .null_flag = false }, wrap_pad);
}
