// Copyright (c) 2025-2026 Voxgig Ltd. MIT LICENSE.

// Voxgig Struct
// =============
//
// Utility functions to manipulate in-memory JSON-like data structures.
// Zig port from the canonical TypeScript implementation.

const std = @import("std");
const Allocator = std.mem.Allocator;
const JsonValue = std.json.Value;
const JsonArray = std.json.Array;
const JsonObjectMap = std.json.ObjectMap;

// Mode value for inject step (bitfield).
pub const M_KEYPRE: i32 = 1;
pub const M_KEYPOST: i32 = 2;
pub const M_VAL: i32 = 4;

// Special strings.
pub const S_BKEY = "`$KEY`";
pub const S_BANNO = "`$ANNO`";
pub const S_BEXACT = "`$EXACT`";
pub const S_BOPEN = "`$OPEN`";
pub const S_BVAL = "`$VAL`";

pub const S_DKEY = "$KEY";
pub const S_DTOP = "$TOP";
pub const S_DERRS = "$ERRS";
pub const S_DSPEC = "$SPEC";

// General strings.
pub const S_list = "list";
pub const S_base = "base";
pub const S_boolean = "boolean";
pub const S_function = "function";
pub const S_symbol = "symbol";
pub const S_instance = "instance";
pub const S_key = "key";
pub const S_any = "any";
pub const S_noval = "noval";
pub const S_nil = "nil";
pub const S_null = "null";
pub const S_number = "number";
pub const S_object = "object";
pub const S_string = "string";
pub const S_decimal = "decimal";
pub const S_integer = "integer";
pub const S_map = "map";
pub const S_scalar = "scalar";
pub const S_node = "node";
pub const S_parent = "parent";

// Character strings.
pub const S_BT = "`";
pub const S_CN = ":";
pub const S_CS = "]";
pub const S_DS = "$";
pub const S_DT = ".";
pub const S_FS = "/";
pub const S_KEY = "KEY";
pub const S_MT = "";
pub const S_OS = "[";
pub const S_SP = " ";
pub const S_CM = ",";
pub const S_VIZ = ": ";

// Type bits — using bit positions from 31 downward, matching the TS implementation.
pub const T_any: i32 = (1 << 31) - 1;
pub const T_noval: i32 = 1 << 30;
pub const T_boolean: i32 = 1 << 29;
pub const T_decimal: i32 = 1 << 28;
pub const T_integer: i32 = 1 << 27;
pub const T_number: i32 = 1 << 26;
pub const T_string: i32 = 1 << 25;
pub const T_function: i32 = 1 << 24;
pub const T_symbol: i32 = 1 << 23;
pub const T_null: i32 = 1 << 22;
// 7 bits reserved
pub const T_list: i32 = 1 << 14;
pub const T_map: i32 = 1 << 13;
pub const T_instance: i32 = 1 << 12;
// 4 bits reserved
pub const T_scalar: i32 = 1 << 7;
pub const T_node: i32 = 1 << 6;

// TYPENAME maps bit position (via leading zeros count) to type name string.
pub const TYPENAME = [_][]const u8{
    S_any,
    S_noval,
    S_boolean,
    S_decimal,
    S_integer,
    S_number,
    S_string,
    S_function,
    S_symbol,
    S_null,
    "", "", "",
    "", "", "", "",
    S_list,
    S_map,
    S_instance,
    "", "", "", "",
    S_scalar,
    S_node,
};

// Default max depth (for walk etc).
pub const MAXDEPTH: i32 = 32;

pub const MODENAME = std.StaticStringMap([]const u8).initComptime(.{
    .{ "4", "val" },
    .{ "1", "key:pre" },
    .{ "2", "key:post" },
});

// Value is a node — defined, and a map (object) or list (array).
pub fn isnode(val: JsonValue) bool {
    return switch (val) {
        .object, .array => true,
        else => false,
    };
}

// Value is a defined map (object) with string keys.
pub fn ismap(val: JsonValue) bool {
    return val == .object;
}

// Value is a defined list (array) with integer keys (indexes).
pub fn islist(val: JsonValue) bool {
    return val == .array;
}

// Value is a defined string (non-empty) or integer key.
pub fn iskey(val: JsonValue) bool {
    return switch (val) {
        .string => |s| s.len > 0,
        .integer => true,
        .float => true,
        else => false,
    };
}

// Check for an "empty" value — null, empty string, empty array, empty object.
pub fn isempty(val: JsonValue) bool {
    return switch (val) {
        .null => true,
        .string => |s| s.len == 0,
        .array => |a| a.items.len == 0,
        .object => |o| o.count() == 0,
        else => false,
    };
}

// Value is a function. JSON values are never functions.
pub fn isfunc(_: JsonValue) bool {
    return false;
}

// ============================================================
// Tests
// ============================================================

const testing = std.testing;

fn makeTestArray(allocator: Allocator) !JsonValue {
    var arr = JsonArray.init(allocator);
    try arr.append(.{ .integer = 1 });
    return .{ .array = arr };
}

fn makeTestObject(allocator: Allocator) !JsonValue {
    var obj = JsonObjectMap.init(allocator);
    try obj.put("a", .{ .integer = 1 });
    return .{ .object = obj };
}

test "isnode" {
    const a = std.testing.allocator;
    const arr = try makeTestArray(a);
    defer arr.array.deinit(a);
    const obj = try makeTestObject(a);
    defer {
        var m = obj.object;
        m.deinit(a);
    }

    try testing.expect(!isnode(.{ .integer = 1 }));
    try testing.expect(!isnode(.{ .string = "a" }));
    try testing.expect(!isnode(.null));
    try testing.expect(!isnode(.{ .bool = true }));
    try testing.expect(isnode(arr));
    try testing.expect(isnode(obj));
}

test "ismap" {
    const a = std.testing.allocator;
    const obj = try makeTestObject(a);
    defer {
        var m = obj.object;
        m.deinit(a);
    }
    const arr = try makeTestArray(a);
    defer arr.array.deinit(a);

    try testing.expect(ismap(obj));
    try testing.expect(!ismap(arr));
    try testing.expect(!ismap(.null));
    try testing.expect(!ismap(.{ .integer = 1 }));
}

test "islist" {
    const a = std.testing.allocator;
    const arr = try makeTestArray(a);
    defer arr.array.deinit(a);
    const obj = try makeTestObject(a);
    defer {
        var m = obj.object;
        m.deinit(a);
    }

    try testing.expect(islist(arr));
    try testing.expect(!islist(obj));
    try testing.expect(!islist(.null));
    try testing.expect(!islist(.{ .string = "x" }));
}

test "iskey" {
    try testing.expect(iskey(.{ .string = "a" }));
    try testing.expect(!iskey(.{ .string = "" }));
    try testing.expect(iskey(.{ .integer = 0 }));
    try testing.expect(iskey(.{ .float = 1.5 }));
    try testing.expect(!iskey(.null));
    try testing.expect(!iskey(.{ .bool = true }));
}

test "isempty" {
    const a = std.testing.allocator;
    var empty_arr = JsonArray.init(a);
    defer empty_arr.deinit(a);
    var empty_obj = JsonObjectMap.init(a);
    defer empty_obj.deinit(a);
    const full_arr = try makeTestArray(a);
    defer full_arr.array.deinit(a);
    const full_obj = try makeTestObject(a);
    defer {
        var m = full_obj.object;
        m.deinit(a);
    }

    try testing.expect(isempty(.null));
    try testing.expect(isempty(.{ .string = "" }));
    try testing.expect(isempty(.{ .array = empty_arr }));
    try testing.expect(isempty(.{ .object = empty_obj }));
    try testing.expect(!isempty(.{ .string = "a" }));
    try testing.expect(!isempty(full_arr));
    try testing.expect(!isempty(full_obj));
    try testing.expect(!isempty(.{ .integer = 0 }));
}

test "isfunc" {
    try testing.expect(!isfunc(.null));
    try testing.expect(!isfunc(.{ .integer = 1 }));
    try testing.expect(!isfunc(.{ .string = "f" }));
}
