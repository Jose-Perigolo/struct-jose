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

// Return a defined value, or an alternative if the value is null.
pub fn getdef(val: JsonValue, alt: JsonValue) JsonValue {
    return switch (val) {
        .null => alt,
        else => val,
    };
}

// Get the type name string from type bits.
pub fn typename(t: i64) []const u8 {
    if (t <= 0 or t > std.math.maxInt(u32)) return S_any;
    const ut: u32 = @intCast(t);
    const idx = @clz(ut);
    if (idx < TYPENAME.len and TYPENAME[idx].len > 0) {
        return TYPENAME[idx];
    }
    return S_any;
}

// Determine the type of a value as a bit code.
pub fn typify(val: JsonValue) i64 {
    return switch (val) {
        .object => @as(i64, T_node | T_map),
        .array => @as(i64, T_node | T_list),
        .integer => @as(i64, T_scalar | T_number | T_integer),
        .float => |f| {
            if (!std.math.isNan(f) and !std.math.isInf(f) and f == @trunc(f)) {
                return @as(i64, T_scalar | T_number | T_integer);
            }
            return @as(i64, T_scalar | T_number | T_decimal);
        },
        .string => @as(i64, T_scalar | T_string),
        .bool => @as(i64, T_scalar | T_boolean),
        .null => @as(i64, T_scalar | T_null),
        .number_string => @as(i64, T_scalar | T_number),
    };
}

// Get the integer size of a value.
pub fn size(val: JsonValue) i64 {
    return switch (val) {
        .array => |a| @intCast(a.items.len),
        .object => |o| @intCast(o.count()),
        .string => |s| @intCast(s.len),
        .integer => |i| i,
        .float => |f| @intFromFloat(@floor(f)),
        .bool => |b| if (b) @as(i64, 1) else @as(i64, 0),
        .null => 0,
        .number_string => 0,
    };
}

// Convert a key to its string representation.
// Returns a slice into existing data or a static string, or
// an allocated string for integer/float keys.
pub fn strkey(allocator: Allocator, key: JsonValue) ![]const u8 {
    return switch (key) {
        .string => |s| s,
        .integer => |i| try std.fmt.allocPrint(allocator, "{d}", .{i}),
        .float => |f| try std.fmt.allocPrint(allocator, "{d}", .{@as(i64, @intFromFloat(f))}),
        else => S_MT,
    };
}

// Get a list element by integer index. Only works on lists.
pub fn getelem(allocator: Allocator, val: JsonValue, key: JsonValue, alt: JsonValue) !JsonValue {
    if (val == .null or key == .null) return alt;

    if (val != .array) return alt;

    const list = val.array.items;

    // Get the key as string first
    const ks = try strkey(allocator, key);

    // Parse as integer
    const nkey_raw = std.fmt.parseInt(i64, ks, 10) catch return alt;
    var nkey = nkey_raw;

    if (nkey < 0) {
        nkey = @as(i64, @intCast(list.len)) + nkey;
    }

    if (nkey >= 0 and nkey < @as(i64, @intCast(list.len))) {
        return list[@intCast(nkey)];
    }

    return alt;
}

// Safely get a property from a node (map or list).
pub fn getprop(allocator: Allocator, val: JsonValue, key: JsonValue, alt: JsonValue) !JsonValue {
    if (val == .null or key == .null) return alt;

    if (val == .object) {
        const ks = try strkey(allocator, key);
        if (val.object.get(ks)) |v| {
            return v;
        }
        return alt;
    }

    if (val == .array) {
        var ki: ?i64 = null;
        switch (key) {
            .integer => |i| ki = i,
            .float => |f| ki = @intFromFloat(f),
            .string => |s| {
                ki = std.fmt.parseInt(i64, s, 10) catch null;
            },
            else => {},
        }
        if (ki) |idx| {
            if (idx >= 0 and idx < @as(i64, @intCast(val.array.items.len))) {
                return val.array.items[@intCast(idx)];
            }
        }
        return alt;
    }

    return alt;
}

// Get sorted keys of a map, or indices (as strings) of a list.
// Returns a JsonValue array.
pub fn keysof(allocator: Allocator, val: JsonValue) !JsonValue {
    if (val == .object) {
        const obj = val.object;
        var key_strs = try std.ArrayList([]const u8).initCapacity(allocator, obj.count());
        defer key_strs.deinit();
        var it = obj.iterator();
        while (it.next()) |kv| {
            try key_strs.append(kv.key_ptr.*);
        }
        std.mem.sort([]const u8, key_strs.items, {}, stringLessThan);

        var arr = try JsonArray.initCapacity(allocator, obj.count());
        for (key_strs.items) |k| {
            try arr.append(allocator, JsonValue{ .string = k });
        }
        return JsonValue{ .array = arr };
    }

    if (val == .array) {
        const list = val.array.items;
        var arr = try JsonArray.initCapacity(allocator, list.len);
        for (0..list.len) |i| {
            const s = try std.fmt.allocPrint(allocator, "{d}", .{i});
            try arr.append(allocator, JsonValue{ .string = s });
        }
        return JsonValue{ .array = arr };
    }

    var arr = JsonArray{};
    return JsonValue{ .array = arr };
}

fn stringLessThan(_: void, a: []const u8, b: []const u8) bool {
    return std.mem.order(u8, a, b) == .lt;
}

// Check if a property with name key exists in node val.
pub fn haskey(allocator: Allocator, val: JsonValue, key: JsonValue) !bool {
    const result = try getprop(allocator, val, key, .null);
    return result != .null;
}

// List entries of a map or list as [key, value] pairs.
pub fn items(allocator: Allocator, val: JsonValue) !JsonValue {
    if (val == .object) {
        const obj = val.object;
        // Get sorted keys
        var key_strs = try std.ArrayList([]const u8).initCapacity(allocator, obj.count());
        defer key_strs.deinit();
        var it = obj.iterator();
        while (it.next()) |kv| {
            try key_strs.append(kv.key_ptr.*);
        }
        std.mem.sort([]const u8, key_strs.items, {}, stringLessThan);

        var arr = try JsonArray.initCapacity(allocator, obj.count());
        for (key_strs.items) |k| {
            var pair = try JsonArray.initCapacity(allocator, 2);
            try pair.append(allocator, JsonValue{ .string = k });
            try pair.append(allocator, obj.get(k).?);
            try arr.append(allocator, JsonValue{ .array = pair });
        }
        return JsonValue{ .array = arr };
    }

    if (val == .array) {
        const list = val.array.items;
        var arr = try JsonArray.initCapacity(allocator, list.len);
        for (list, 0..) |v, i| {
            var pair = try JsonArray.initCapacity(allocator, 2);
            const idx_str = try std.fmt.allocPrint(allocator, "{d}", .{i});
            try pair.append(allocator, JsonValue{ .string = idx_str });
            try pair.append(allocator, v);
            try arr.append(allocator, JsonValue{ .array = pair });
        }
        return JsonValue{ .array = arr };
    }

    var arr = JsonArray{};
    return JsonValue{ .array = arr };
}

// Flatten nested arrays up to a specified depth.
pub fn flatten(allocator: Allocator, val: JsonValue, depth: i64) !JsonValue {
    if (val != .array) return val;
    const result = try flattenDepth(allocator, val.array.items, depth);
    return JsonValue{ .array = result };
}

fn flattenDepth(allocator: Allocator, arr: []const JsonValue, depth: i64) !JsonArray {
    var result = JsonArray{};
    for (arr) |item| {
        if (depth > 0 and item == .array) {
            const sub = try flattenDepth(allocator, item.array.items, depth - 1);
            for (sub.items) |subitem| {
                try result.append(allocator, subitem);
            }
        } else {
            try result.append(allocator, item);
        }
    }
    return result;
}

// Deep clone a JSON value.
pub fn clone(allocator: Allocator, val: JsonValue) !JsonValue {
    return switch (val) {
        .object => |obj| {
            var new_obj = JsonObjectMap{};
            try new_obj.ensureTotalCapacity(allocator, @intCast(obj.count()));
            var it = obj.iterator();
            while (it.next()) |kv| {
                const cloned_val = try clone(allocator, kv.value_ptr.*);
                try new_obj.put(allocator, kv.key_ptr.*, cloned_val);
            }
            return JsonValue{ .object = new_obj };
        },
        .array => |arr| {
            var new_arr = try JsonArray.initCapacity(allocator, arr.items.len);
            for (arr.items) |item| {
                const cloned_item = try clone(allocator, item);
                try new_arr.append(allocator, cloned_item);
            }
            return JsonValue{ .array = new_arr };
        },
        else => val,
    };
}

// Delete a property from a map or remove an element from a list.
pub fn delprop(allocator: Allocator, parent: JsonValue, key: JsonValue) !JsonValue {
    _ = allocator;
    if (!iskey(key)) return parent;

    if (parent == .object) {
        var obj = parent.object;
        var buf: [20]u8 = undefined;
        const ks = keyStr(&buf, key);
        _ = obj.fetchOrderedRemove(ks);
        return JsonValue{ .object = obj };
    }

    if (parent == .array) {
        var ki: ?i64 = null;
        switch (key) {
            .integer => |i| ki = i,
            .float => |f| ki = @intFromFloat(@trunc(f)),
            .string => |s| {
                ki = std.fmt.parseInt(i64, s, 10) catch null;
            },
            else => {},
        }
        if (ki) |idx| {
            const plen: i64 = @intCast(parent.array.items.len);
            // No negative index support for delprop
            if (idx >= 0 and idx < plen) {
                var arr = parent.array;
                _ = arr.orderedRemove(@intCast(idx));
                return JsonValue{ .array = arr };
            }
        }
        return parent;
    }

    return parent;
}

// Set a property value by key.
pub fn setprop(allocator: Allocator, parent: JsonValue, key: JsonValue, newval: JsonValue) !JsonValue {
    if (!iskey(key)) return parent;

    if (parent == .object) {
        var obj = parent.object;
        var buf: [20]u8 = undefined;
        const ks = keyStr(&buf, key);
        // Dupe the key if it was generated from the stack buffer (integer/float keys)
        const owned_key = if (key != .string)
            try allocator.dupe(u8, ks)
        else
            ks;
        try obj.put(allocator, owned_key, newval);
        return JsonValue{ .object = obj };
    }

    if (parent == .array) {
        var ki: ?i64 = null;
        switch (key) {
            .integer => |i| ki = i,
            .float => |f| ki = @intFromFloat(f),
            .string => |s| {
                ki = std.fmt.parseInt(i64, s, 10) catch null;
            },
            else => {},
        }
        if (ki) |idx| {
            var arr = parent.array;
            const plen: i64 = @intCast(arr.items.len);
            if (idx >= 0) {
                if (idx >= plen) {
                    // Append
                    try arr.append(allocator, newval);
                } else {
                    // Replace
                    arr.items[@intCast(idx)] = newval;
                }
            } else {
                // Prepend
                try arr.insert(allocator, 0, newval);
            }
            return JsonValue{ .array = arr };
        }
        return parent;
    }

    return parent;
}

// Convert key to string without allocation, using a stack buffer.
fn keyStr(buf: *[20]u8, key: JsonValue) []const u8 {
    return switch (key) {
        .string => |s| s,
        .integer => |i| std.fmt.bufPrint(buf, "{d}", .{i}) catch S_MT,
        .float => |f| std.fmt.bufPrint(buf, "{d}", .{@as(i64, @intFromFloat(f))}) catch S_MT,
        else => S_MT,
    };
}

// Escape regex special characters.
pub fn escre(allocator: Allocator, s: []const u8) ![]const u8 {
    if (s.len == 0) return S_MT;
    var result = std.ArrayList(u8).init(allocator);
    for (s) |c| {
        if (isReSpecial(c)) {
            try result.append('\\');
        }
        try result.append(c);
    }
    return result.items;
}

fn isReSpecial(c: u8) bool {
    return switch (c) {
        '.', '*', '+', '?', '^', '$', '{', '}', '(', ')', '|', '[', ']', '\\' => true,
        else => false,
    };
}

// URL-encode a string.
pub fn escurl(allocator: Allocator, s: []const u8) ![]const u8 {
    if (s.len == 0) return S_MT;
    var result = std.ArrayList(u8).init(allocator);
    for (s) |c| {
        if (isUrlSafe(c)) {
            try result.append(c);
        } else {
            try result.appendSlice(try std.fmt.allocPrint(allocator, "%{X:0>2}", .{c}));
        }
    }
    return result.items;
}

fn isUrlSafe(c: u8) bool {
    return switch (c) {
        'A'...'Z', 'a'...'z', '0'...'9', '-', '_', '.', '~' => true,
        else => false,
    };
}

// Join array elements into a string with separator handling.
pub fn join(allocator: Allocator, arr: JsonValue, sep: []const u8, urlMode: bool) ![]const u8 {
    if (arr != .array) return S_MT;

    const items_list = arr.array.items;
    const sarr: usize = items_list.len;

    // Filter to non-empty strings
    var filtered = std.ArrayList([]const u8).init(allocator);
    var indices = std.ArrayList(usize).init(allocator);
    for (items_list, 0..) |item, orig_idx| {
        if (item == .string and item.string.len > 0) {
            try filtered.append(item.string);
            try indices.append(orig_idx);
        }
    }

    if (filtered.items.len == 0) return S_MT;

    // Process separator handling
    var parts = std.ArrayList([]const u8).init(allocator);

    for (filtered.items, 0..) |s, fi| {
        var processed = s;
        const orig_idx = indices.items[fi];

        if (sep.len == 1) {
            const sep_c = sep[0];
            if (urlMode and orig_idx == 0) {
                // Remove trailing seps from first URL element
                processed = trimRight(processed, sep_c);
            } else {
                if (orig_idx > 0) {
                    // Remove leading seps
                    processed = trimLeft(processed, sep_c);
                }
                if (orig_idx < sarr - 1 or !urlMode) {
                    // Remove trailing seps
                    processed = trimRight(processed, sep_c);
                }
                // Collapse internal runs of sep
                processed = try collapseInternal(allocator, processed, sep_c);
            }
        }

        if (processed.len > 0) {
            try parts.append(processed);
        }
    }

    // Join with separator
    if (parts.items.len == 0) return S_MT;

    var total_len: usize = 0;
    for (parts.items) |p| total_len += p.len;
    total_len += sep.len * (parts.items.len - 1);

    var result = try std.ArrayList(u8).initCapacity(allocator, total_len);
    for (parts.items, 0..) |p, i| {
        try result.appendSlice(p);
        if (i < parts.items.len - 1) {
            try result.appendSlice(sep);
        }
    }
    return result.items;
}

fn trimLeft(s: []const u8, c: u8) []const u8 {
    var i: usize = 0;
    while (i < s.len and s[i] == c) : (i += 1) {}
    return s[i..];
}

fn trimRight(s: []const u8, c: u8) []const u8 {
    var end: usize = s.len;
    while (end > 0 and s[end - 1] == c) : (end -= 1) {}
    return s[0..end];
}

// Collapse internal runs of separator only when between non-separator chars.
// E.g. "c//d" → "c/d" but "//a" stays "//a".
fn collapseInternal(allocator: Allocator, s: []const u8, sep: u8) ![]const u8 {
    if (s.len < 3) return s;
    var result = std.ArrayList(u8).init(allocator);
    var i: usize = 0;
    while (i < s.len) {
        try result.append(s[i]);
        // If current char is not sep, look ahead for sep run followed by non-sep
        if (s[i] != sep) {
            if (i + 1 < s.len and s[i + 1] == sep) {
                var sep_end = i + 1;
                while (sep_end < s.len and s[sep_end] == sep) : (sep_end += 1) {}
                if (sep_end < s.len) {
                    // Sep run between two non-sep chars: collapse to single sep
                    try result.append(sep);
                    i = sep_end;
                    continue;
                }
                // Sep run at end: keep all
            }
        }
        i += 1;
    }
    return result.items;
}

// Output JSON with indentation.
pub fn jsonify(allocator: Allocator, val: JsonValue, indent_size: usize, offset: usize) ![]const u8 {
    if (val == .null) return "null";

    // Use the standard JSON stringify
    var result = std.ArrayList(u8).init(allocator);
    try jsonifyWrite(val, result.writer(), indent_size, offset, 0);
    return result.items;
}

fn jsonifyWrite(val: JsonValue, writer: anytype, indent_size: usize, offset: usize, depth: usize) !void {
    switch (val) {
        .null => try writer.writeAll("null"),
        .bool => |b| try writer.writeAll(if (b) "true" else "false"),
        .integer => |i| try writer.print("{d}", .{i}),
        .float => |f| {
            if (f == @trunc(f) and !std.math.isNan(f) and !std.math.isInf(f)) {
                try writer.print("{d}", .{@as(i64, @intFromFloat(f))});
            } else {
                try writer.print("{d}", .{f});
            }
        },
        .string => |s| {
            try writer.writeByte('"');
            for (s) |c| {
                switch (c) {
                    '"' => try writer.writeAll("\\\""),
                    '\\' => try writer.writeAll("\\\\"),
                    '\n' => try writer.writeAll("\\n"),
                    '\r' => try writer.writeAll("\\r"),
                    '\t' => try writer.writeAll("\\t"),
                    else => try writer.writeByte(c),
                }
            }
            try writer.writeByte('"');
        },
        .array => |arr| {
            if (arr.items.len == 0) {
                try writer.writeAll("[]");
                return;
            }
            try writer.writeAll("[\n");
            for (arr.items, 0..) |item, i| {
                try writeIndent(writer, offset + indent_size * (depth + 1));
                try jsonifyWrite(item, writer, indent_size, offset, depth + 1);
                if (i < arr.items.len - 1) {
                    try writer.writeByte(',');
                }
                try writer.writeByte('\n');
            }
            try writeIndent(writer, offset + indent_size * depth);
            try writer.writeByte(']');
        },
        .object => |obj| {
            if (obj.count() == 0) {
                try writer.writeAll("{}");
                return;
            }
            // Sort keys
            const allocator = std.heap.page_allocator;
            var key_list = std.ArrayList([]const u8).init(allocator);
            defer key_list.deinit();
            var it = obj.iterator();
            while (it.next()) |kv| {
                key_list.append(kv.key_ptr.*) catch return;
            }
            std.mem.sort([]const u8, key_list.items, {}, stringLessThan);

            try writer.writeAll("{\n");
            for (key_list.items, 0..) |k, i| {
                const v = obj.get(k).?;
                try writeIndent(writer, offset + indent_size * (depth + 1));
                try writer.writeByte('"');
                try writer.writeAll(k);
                try writer.writeAll("\": ");
                try jsonifyWrite(v, writer, indent_size, offset, depth + 1);
                if (i < key_list.items.len - 1) {
                    try writer.writeByte(',');
                }
                try writer.writeByte('\n');
            }
            try writeIndent(writer, offset + indent_size * depth);
            try writer.writeByte('}');
        },
        .number_string => |s| try writer.writeAll(s),
    }
}

fn writeIndent(writer: anytype, count: usize) !void {
    for (0..count) |_| {
        try writer.writeByte(' ');
    }
}

// Human-friendly string representation.
pub fn stringify(allocator: Allocator, val: JsonValue, maxlen: ?usize) ![]const u8 {
    const jsonStr = try stringifyInner(allocator, val);

    if (maxlen) |ml| {
        if (ml > 0 and jsonStr.len > ml) {
            if (ml >= 3) {
                var truncated = try allocator.alloc(u8, ml);
                @memcpy(truncated[0 .. ml - 3], jsonStr[0 .. ml - 3]);
                truncated[ml - 3] = '.';
                truncated[ml - 2] = '.';
                truncated[ml - 1] = '.';
                return truncated;
            }
            return jsonStr[0..ml];
        }
    }

    return jsonStr;
}

fn stringifyInner(allocator: Allocator, val: JsonValue) ![]const u8 {
    return switch (val) {
        .null => "null",
        .bool => |b| if (b) "true" else "false",
        .string => |s| s,
        .integer => |i| try std.fmt.allocPrint(allocator, "{d}", .{i}),
        .float => |f| {
            if (f == @trunc(f) and !std.math.isNan(f) and !std.math.isInf(f)) {
                return try std.fmt.allocPrint(allocator, "{d}", .{@as(i64, @intFromFloat(f))});
            }
            return try std.fmt.allocPrint(allocator, "{d}", .{f});
        },
        .array => |arr| {
            var result = std.ArrayList(u8).init(allocator);
            try result.append('[');
            for (arr.items, 0..) |item, i| {
                const s = try stringifyInner(allocator, item);
                try result.appendSlice(s);
                if (i < arr.items.len - 1) {
                    try result.append(',');
                }
            }
            try result.append(']');
            return result.items;
        },
        .object => |obj| {
            // Sort keys
            var key_list = std.ArrayList([]const u8).init(allocator);
            defer key_list.deinit();
            var it = obj.iterator();
            while (it.next()) |kv| {
                try key_list.append(kv.key_ptr.*);
            }
            std.mem.sort([]const u8, key_list.items, {}, stringLessThan);

            var result = std.ArrayList(u8).init(allocator);
            try result.append('{');
            for (key_list.items, 0..) |k, i| {
                const v = obj.get(k).?;
                try result.appendSlice(k);
                try result.append(':');
                const s = try stringifyInner(allocator, v);
                try result.appendSlice(s);
                if (i < key_list.items.len - 1) {
                    try result.append(',');
                }
            }
            try result.append('}');
            return result.items;
        },
        .number_string => |s| s,
    };
}

// Build a human-friendly path string.
pub fn pathify(allocator: Allocator, val: JsonValue, from: usize, end: usize) ![]const u8 {
    var path: ?std.ArrayList([]const u8) = null;

    if (val == .array) {
        path = std.ArrayList([]const u8).init(allocator);
        for (val.array.items) |item| {
            switch (item) {
                .string => |s| try path.?.append(s),
                .integer => |i| try path.?.append(try std.fmt.allocPrint(allocator, "{d}", .{i})),
                .float => |f| try path.?.append(try std.fmt.allocPrint(allocator, "{d}", .{@as(i64, @intFromFloat(f))})),
                else => {},
            }
        }
    } else if (val == .string) {
        path = std.ArrayList([]const u8).init(allocator);
        try path.?.append(val.string);
    } else if (val == .integer or val == .float) {
        path = std.ArrayList([]const u8).init(allocator);
        const num: i64 = if (val == .integer) val.integer else @intFromFloat(@floor(val.float));
        try path.?.append(try std.fmt.allocPrint(allocator, "{d}", .{num}));
    }

    if (path) |p| {
        const start = if (from > p.items.len) p.items.len else from;
        const end_idx = if (p.items.len < end) start else if (p.items.len - end < start) start else p.items.len - end;

        const sliced = p.items[start..end_idx];

        if (sliced.len == 0) {
            return "<root>";
        }

        // Map: replace dots in string parts
        var mapped = std.ArrayList([]const u8).init(allocator);
        for (sliced) |part| {
            var replaced = std.ArrayList(u8).init(allocator);
            for (part) |c| {
                if (c != '.') try replaced.append(c);
            }
            try mapped.append(replaced.items);
        }

        // Join with dots
        var result = std.ArrayList(u8).init(allocator);
        for (mapped.items, 0..) |part, i| {
            try result.appendSlice(part);
            if (i < mapped.items.len - 1) {
                try result.append('.');
            }
        }
        return result.items;
    }

    // Unknown path — always include colon and stringified value
    var result = std.ArrayList(u8).init(allocator);
    try result.appendSlice("<unknown-path:");
    const s = try stringify(allocator, val, 33);
    try result.appendSlice(s);
    try result.append('>');
    return result.items;
}

// Slice: extract part of an array, string, or clamp a number.
pub fn slice(allocator: Allocator, val: JsonValue, start_in: ?i64, end_in: ?i64) !JsonValue {
    // Number case: clamp
    if (val != .string and val != .array and val != .object) {
        if (val == .integer or val == .float) {
            const f: f64 = if (val == .integer) @floatFromInt(val.integer) else val.float;
            var lo: f64 = -std.math.floatMax(f64);
            var hi: f64 = std.math.floatMax(f64);
            if (start_in) |s| {
                lo = @floatFromInt(s);
            }
            if (end_in) |e| {
                hi = @floatFromInt(e - 1);
            }
            const clamped = @min(@max(f, lo), hi);
            // Return as integer if the original was integer
            if (clamped == @trunc(clamped)) {
                return JsonValue{ .integer = @intFromFloat(clamped) };
            }
            return JsonValue{ .float = clamped };
        }
        // bool, null, object: return as-is
        return val;
    }

    const vlen: i64 = size(val);

    // If end is specified but start is not, default start to 0
    var eff_start = start_in;
    if (end_in != null and eff_start == null) {
        eff_start = 0;
    }

    if (eff_start == null) return val;

    var start = eff_start.?;
    var end_val = vlen;

    if (start < 0) {
        end_val = vlen + start;
        if (end_val < 0) end_val = 0;
        start = 0;
    } else if (end_in) |e| {
        end_val = e;
        if (end_val < 0) {
            end_val = vlen + end_val;
            if (end_val < 0) end_val = 0;
        } else if (vlen < end_val) {
            end_val = vlen;
        }
    }

    if (vlen < start) start = vlen;

    if (start >= 0 and start <= end_val and end_val <= vlen) {
        if (val == .array) {
            const s_usize: usize = @intCast(start);
            const e_usize: usize = @intCast(end_val);
            const src = val.array.items[s_usize..e_usize];
            var new_arr = try JsonArray.initCapacity(allocator, src.len);
            for (src) |item| {
                try new_arr.append(allocator, item);
            }
            return JsonValue{ .array = new_arr };
        }
        if (val == .string) {
            const s_usize: usize = @intCast(start);
            const e_usize: usize = @intCast(end_val);
            return JsonValue{ .string = val.string[s_usize..e_usize] };
        }
    } else {
        if (val == .array) {
            var empty_arr = JsonArray{};
            _ = &empty_arr;
            return JsonValue{ .array = empty_arr };
        }
        if (val == .string) {
            return JsonValue{ .string = S_MT };
        }
    }

    return val;
}

// Pad a string to a target length.
pub fn pad(allocator: Allocator, s: []const u8, padding: i64, padchar: u8) ![]const u8 {
    if (padding >= 0) {
        const target: usize = @intCast(padding);
        if (s.len >= target) return s;
        var result = try allocator.alloc(u8, target);
        @memcpy(result[0..s.len], s);
        @memset(result[s.len..], padchar);
        return result;
    } else {
        const target: usize = @intCast(-padding);
        if (s.len >= target) return s;
        const pad_len = target - s.len;
        var result = try allocator.alloc(u8, target);
        @memset(result[0..pad_len], padchar);
        @memcpy(result[pad_len..], s);
        return result;
    }
}

// ============================================================================
// Walk — depth-first tree traversal with before/after callbacks.
// ============================================================================

pub const WalkApply = *const fn (
    allocator: Allocator,
    key: ?[]const u8,
    val: JsonValue,
    parent: JsonValue,
    path: []const []const u8,
) !JsonValue;

pub fn walk(
    allocator: Allocator,
    val: JsonValue,
    before: ?WalkApply,
    after: ?WalkApply,
    maxdepth: i32,
) !JsonValue {
    return walkDescend(allocator, val, before, after, maxdepth, null, .null, &.{});
}

fn walkDescend(
    allocator: Allocator,
    val_in: JsonValue,
    before: ?WalkApply,
    after: ?WalkApply,
    maxdepth: i32,
    key: ?[]const u8,
    parent: JsonValue,
    path: []const []const u8,
) !JsonValue {
    var out = val_in;

    // Apply before callback.
    if (before) |apply| {
        out = try apply(allocator, key, out, parent, path);
    }

    // Check depth limit.
    if (maxdepth == 0 or (path.len > 0 and maxdepth > 0 and maxdepth <= @as(i32, @intCast(path.len)))) {
        return out;
    }

    if (isnode(out)) {
        // Get items (sorted key-value pairs).
        const kv_pairs = try items(allocator, out);
        if (kv_pairs == .array) {
            for (kv_pairs.array.items) |pair| {
                if (pair != .array or pair.array.items.len < 2) continue;
                const ckey_val = pair.array.items[0];
                const child = pair.array.items[1];
                const ckey = if (ckey_val == .string) ckey_val.string else "";

                // Build new path.
                var new_path = try allocator.alloc([]const u8, path.len + 1);
                @memcpy(new_path[0..path.len], path);
                new_path[path.len] = ckey;

                const new_child = try walkDescend(
                    allocator,
                    child,
                    before,
                    after,
                    maxdepth,
                    ckey,
                    out,
                    new_path,
                );

                // Update the output with the new child value.
                out = try setprop(allocator, out, ckey_val, new_child);
            }
        }
    }

    // Apply after callback.
    if (after) |apply| {
        out = try apply(allocator, key, out, parent, path);
    }

    return out;
}

// ============================================================================
// Merge — deep-merge a list of values. Later values override.
// ============================================================================

pub fn merge(allocator: Allocator, val: JsonValue, maxdepth: i32) !JsonValue {
    if (val != .array) return val;

    const list = val.array.items;
    if (list.len == 0) return .null;
    if (list.len == 1) return list[0];

    const md: i32 = if (maxdepth < 0) 0 else maxdepth;

    // Special case: depth 0 returns empty container of last element's type.
    if (md == 0) {
        const last = list[list.len - 1];
        if (islist(last)) return JsonValue{ .array = JsonArray{} };
        if (ismap(last)) {
            var obj = JsonObjectMap{};
            _ = &obj;
            return JsonValue{ .object = obj };
        }
        return last;
    }

    var out = try clone(allocator, list[0]);

    for (list[1..]) |obj| {
        if (!isnode(obj)) {
            out = obj;
        } else {
            out = try mergeNodes(allocator, out, obj, md, 0);
        }
    }

    return out;
}

fn mergeNodes(
    allocator: Allocator,
    dst: JsonValue,
    src: JsonValue,
    maxdepth: i32,
    depth: i32,
) !JsonValue {
    // At depth limit: just replace.
    if (maxdepth > 0 and depth >= maxdepth) {
        return src;
    }

    if (!isnode(src)) return src;
    if (!isnode(dst)) return try clone(allocator, src);

    // Types differ: src wins.
    if ((ismap(src) and !ismap(dst)) or (islist(src) and !islist(dst))) {
        return try clone(allocator, src);
    }

    // Both maps: deep merge.
    if (ismap(src) and ismap(dst)) {
        var result = try clone(allocator, dst);
        var it = src.object.iterator();
        while (it.next()) |kv| {
            const key_str = kv.key_ptr.*;
            const src_val = kv.value_ptr.*;
            const key_json = JsonValue{ .string = key_str };

            if (result.object.get(key_str)) |dst_val| {
                if (isnode(src_val) and isnode(dst_val)) {
                    const merged = try mergeNodes(allocator, dst_val, src_val, maxdepth, depth + 1);
                    result = try setprop(allocator, result, key_json, merged);
                } else {
                    result = try setprop(allocator, result, key_json, src_val);
                }
            } else {
                result = try setprop(allocator, result, key_json, src_val);
            }
        }
        return result;
    }

    // Both lists: element-by-element overlay.
    if (islist(src) and islist(dst)) {
        var result = try clone(allocator, dst);
        for (src.array.items, 0..) |item, i| {
            const idx_json = JsonValue{ .integer = @intCast(i) };
            if (i < dst.array.items.len) {
                const dst_item = dst.array.items[i];
                if (isnode(item) and isnode(dst_item)) {
                    const merged = try mergeNodes(allocator, dst_item, item, maxdepth, depth + 1);
                    result = try setprop(allocator, result, idx_json, merged);
                } else {
                    result = try setprop(allocator, result, idx_json, item);
                }
            } else {
                result = try setprop(allocator, result, idx_json, item);
            }
        }
        return result;
    }

    return src;
}

// ============================================================================
// GetPath — resolve a dotted path string against a store.
// ============================================================================

pub fn getpath(allocator: Allocator, path_val: JsonValue, store: JsonValue) !JsonValue {
    return getpathInj(allocator, path_val, store, null);
}

pub fn getpathInj(allocator: Allocator, path_val: JsonValue, store: JsonValue, inj: ?*Injection) !JsonValue {
    var parts_buf: [64][]const u8 = undefined;
    var numparts: usize = 0;

    // Parse path into parts.
    switch (path_val) {
        .string => |s| {
            if (s.len == 0) {
                parts_buf[0] = S_MT;
                numparts = 1;
            } else {
                var it = std.mem.splitScalar(u8, s, '.');
                while (it.next()) |part| {
                    if (numparts < parts_buf.len) {
                        parts_buf[numparts] = part;
                        numparts += 1;
                    }
                }
            }
        },
        .array => |arr| {
            for (arr.items) |item| {
                if (numparts < parts_buf.len) {
                    parts_buf[numparts] = if (item == .string) item.string else "";
                    numparts += 1;
                }
            }
        },
        .null => return getpropFromStore(store),
        else => return .null,
    }

    const parts = parts_buf[0..numparts];

    // Empty path → return the source.
    if (numparts == 1 and parts[0].len == 0) {
        // Single dot → return dparent if available.
        if (inj) |ij| {
            return ij.dparent;
        }
        return getpropFromStore(store);
    }

    // Single part: check store directly first (for $ commands etc).
    if (numparts == 1) {
        if (store == .object) {
            if (store.object.get(parts[0])) |v| {
                return v;
            }
        }
    }

    // Resolve through $TOP (or dparent for relative paths).
    var val = getpropFromStore(store);

    // Check for relative path: first part is empty string (from leading dot).
    if (numparts > 0 and parts[0].len == 0 and inj != null) {
        val = inj.?.dparent;
        // Skip the empty first part.
        const rel_parts = parts[1..];
        for (rel_parts) |part| {
            if (val == .null) break;
            val = try resolvePart(allocator, val, part, inj);
        }
        return val;
    }

    for (parts) |part| {
        if (val == .null) break;
        val = try resolvePart(allocator, val, part, inj);
    }

    return val;
}

fn resolvePart(allocator: Allocator, val: JsonValue, part_in: []const u8, inj: ?*const Injection) !JsonValue {
    _ = allocator;
    // Handle $$ escape → $.
    var part = part_in;
    if (std.mem.indexOf(u8, part, "$$")) |_| {
        var buf = std.ArrayList(u8).init(std.heap.page_allocator);
        var i: usize = 0;
        while (i < part.len) {
            if (i + 1 < part.len and part[i] == '$' and part[i + 1] == '$') {
                buf.append('$') catch {};
                i += 2;
            } else {
                buf.append(part[i]) catch {};
                i += 1;
            }
        }
        part = buf.items;
    }

    // Handle $KEY → replace with injection key.
    if (std.mem.eql(u8, part, "$KEY")) {
        if (inj) |ij| {
            part = ij.key;
        }
    }

    if (val == .object) {
        return val.object.get(part) orelse .null;
    } else if (val == .array) {
        const idx = std.fmt.parseInt(i64, part, 10) catch return .null;
        if (idx >= 0 and idx < @as(i64, @intCast(val.array.items.len))) {
            return val.array.items[@intCast(idx)];
        }
        return .null;
    }
    return .null;
}

fn getpropFromStore(store: JsonValue) JsonValue {
    if (store == .object) {
        return store.object.get(S_DTOP) orelse store;
    }
    return store;
}

// ============================================================================
// SetPath — set a value at a dotted path in a store.
// ============================================================================

pub fn setpath(allocator: Allocator, store: JsonValue, path_val: JsonValue, val: JsonValue) !JsonValue {
    var parts_buf: [64][]const u8 = undefined;
    var numparts: usize = 0;

    switch (path_val) {
        .string => |s| {
            var it = std.mem.splitScalar(u8, s, '.');
            while (it.next()) |part| {
                if (numparts < parts_buf.len) {
                    parts_buf[numparts] = part;
                    numparts += 1;
                }
            }
        },
        else => return store,
    }

    if (numparts == 0) return store;

    const parts = parts_buf[0..numparts];
    var parent = getpropFromStore(store);

    // Navigate to the parent of the final key, creating nodes as needed.
    var i: usize = 0;
    while (i < numparts - 1) : (i += 1) {
        const part = parts[i];
        const key_json = JsonValue{ .string = part };
        var next = try getprop(allocator, parent, key_json, .null);
        if (!isnode(next)) {
            next = JsonValue{ .object = JsonObjectMap{} };
            parent = try setprop(allocator, parent, key_json, next);
        }
        parent = next;
    }

    // Set the final value.
    const last_key = JsonValue{ .string = parts[numparts - 1] };
    _ = try setprop(allocator, parent, last_key, val);

    return store;
}

// ============================================================================
// Injection — state carried through recursive spec injection.
// Mirrors the Go/TS Injection struct for three-phase key processing.
// ============================================================================

pub const Injection = struct {
    allocator: Allocator,
    mode: i32 = M_VAL,
    full: bool = false,
    key_i: usize = 0,
    key: []const u8 = S_DTOP,
    val: JsonValue = .null,
    parent: JsonValue = .null,
    base: []const u8 = S_DTOP,
    prior: ?*Injection = null,
    dparent: JsonValue = .null,

    // Heap-allocated slices from the arena.
    keys: [][]const u8,
    path: [][]const u8,
    nodes: []JsonValue,
    dpath: [][]const u8,

    // Shared error collector (pointer so all children share it).
    errs: *std.ArrayList([]const u8),

    // Create a child injection for processing key at keys[key_i].
    pub fn child(self: *Injection, key_i: usize, keys: []const []const u8) !*Injection {
        const a = self.allocator;
        const k = if (key_i < keys.len) keys[key_i] else S_MT;

        // Extend path: parent path + new key.
        var new_path = try a.alloc([]const u8, self.path.len + 1);
        @memcpy(new_path[0..self.path.len], self.path);
        new_path[self.path.len] = k;

        // Extend nodes: parent nodes + current val.
        var new_nodes = try a.alloc(JsonValue, self.nodes.len + 1);
        @memcpy(new_nodes[0..self.nodes.len], self.nodes);
        new_nodes[self.nodes.len] = self.val;

        // Copy dpath.
        var new_dpath = try a.alloc([]const u8, self.dpath.len);
        @memcpy(new_dpath, self.dpath);

        // Copy keys.
        var new_keys = try a.alloc([]const u8, keys.len);
        @memcpy(new_keys, keys);

        const c = try a.create(Injection);
        c.* = Injection{
            .allocator = a,
            .mode = self.mode,
            .full = false,
            .key_i = key_i,
            .key = k,
            .val = getprop(a, self.val, JsonValue{ .string = k }, .null) catch .null,
            .parent = self.val,
            .base = self.base,
            .prior = self,
            .dparent = self.dparent,
            .keys = new_keys,
            .path = new_path,
            .nodes = new_nodes,
            .dpath = new_dpath,
            .errs = self.errs,
        };
        return c;
    }

    // Set a value in the parent node (or an ancestor).
    pub fn setval(self: *Injection, val: JsonValue, ancestor: usize) !JsonValue {
        const a = self.allocator;
        if (ancestor < 2) {
            if (val == .null) {
                self.parent = delprop(a, self.parent, JsonValue{ .string = self.key }) catch self.parent;
            } else {
                self.parent = setprop(a, self.parent, JsonValue{ .string = self.key }, val) catch self.parent;
            }
            return self.parent;
        } else {
            // Ancestor access via nodes/path.
            const nlen = self.nodes.len;
            const plen = self.path.len;
            if (ancestor > nlen or ancestor > plen) return self.parent;
            const aval = self.nodes[nlen - ancestor];
            const akey = self.path[plen - ancestor];
            if (val == .null) {
                _ = delprop(a, aval, JsonValue{ .string = akey }) catch {};
            } else {
                _ = setprop(a, aval, JsonValue{ .string = akey }, val) catch {};
            }
            return aval;
        }
    }

    // Advance dparent down the data tree based on the current path.
    pub fn descend(self: *Injection) void {
        const a = self.allocator;
        var parentkey: []const u8 = S_MT;
        if (self.path.len >= 2) {
            parentkey = self.path[self.path.len - 2];
        }

        if (self.dparent == .null) {
            if (self.dpath.len > 1) {
                self.dpath = appendSlice(a, []const u8, self.dpath, parentkey) catch self.dpath;
            }
        } else {
            if (parentkey.len > 0) {
                self.dparent = getprop(a, self.dparent, JsonValue{ .string = parentkey }, .null) catch .null;

                const lastpart: []const u8 = if (self.dpath.len > 0)
                    self.dpath[self.dpath.len - 1]
                else
                    S_MT;

                // Check for synthetic path marker "$:key".
                const marker = std.fmt.allocPrint(a, "$:{s}", .{parentkey}) catch S_MT;
                if (std.mem.eql(u8, lastpart, marker)) {
                    // Pop synthetic marker.
                    self.dpath = self.dpath[0 .. self.dpath.len - 1];
                } else {
                    self.dpath = appendSlice(a, []const u8, self.dpath, parentkey) catch self.dpath;
                }
            }
        }
    }
};

fn appendSlice(allocator: Allocator, comptime T: type, existing: []const T, item: T) ![]T {
    var new = try allocator.alloc(T, existing.len + 1);
    @memcpy(new[0..existing.len], existing);
    new[existing.len] = item;
    return new;
}

// ============================================================================
// Inject — core injection function with three-phase key processing.
// ============================================================================

pub fn injectVal(allocator: Allocator, val: JsonValue, store: JsonValue, inj_opt: ?*Injection) !JsonValue {
    var inj: *Injection = undefined;

    if (inj_opt == null or (inj_opt != null and inj_opt.?.mode == 0)) {
        // Root injection: wrap val in a virtual parent.
        var parent_obj = JsonObjectMap{};
        try parent_obj.put(allocator, S_DTOP, val);
        const parent_val = JsonValue{ .object = parent_obj };

        var errs: *std.ArrayList([]const u8) = undefined;
        if (inj_opt) |existing| {
            errs = existing.errs;
        } else {
            errs = try allocator.create(std.ArrayList([]const u8));
            errs.* = std.ArrayList([]const u8).init(allocator);
        }

        var init_keys = try allocator.alloc([]const u8, 1);
        init_keys[0] = S_DTOP;
        var init_path = try allocator.alloc([]const u8, 1);
        init_path[0] = S_DTOP;
        var init_nodes = try allocator.alloc(JsonValue, 1);
        init_nodes[0] = parent_val;
        var init_dpath = try allocator.alloc([]const u8, 1);
        init_dpath[0] = S_DTOP;

        inj = try allocator.create(Injection);
        inj.* = Injection{
            .allocator = allocator,
            .mode = M_VAL,
            .key = S_DTOP,
            .val = val,
            .parent = parent_val,
            .base = S_DTOP,
            .dparent = store,
            .keys = init_keys,
            .path = init_path,
            .nodes = init_nodes,
            .dpath = init_dpath,
            .errs = errs,
        };

        // Merge in partial init if provided.
        if (inj_opt) |existing| {
            if (existing.dparent != .null) inj.dparent = existing.dparent;
            if (existing.dpath.len > 0) inj.dpath = existing.dpath;
        }
    } else {
        inj = inj_opt.?;
    }

    inj.descend();
    var current = val;

    if (isnode(val)) {
        // Get sorted keys: normal first, then $ transform keys.
        var normal_keys = std.ArrayList([]const u8).init(allocator);
        var transform_keys = std.ArrayList([]const u8).init(allocator);

        const all_keys = try keysof(allocator, current);
        if (all_keys == .array) {
            for (all_keys.array.items) |k| {
                if (k != .string) continue;
                const ks = k.string;
                if (std.mem.indexOf(u8, ks, S_DS) != null) {
                    try transform_keys.append(ks);
                } else {
                    try normal_keys.append(ks);
                }
            }
        }

        var node_keys = std.ArrayList([]const u8).init(allocator);
        for (normal_keys.items) |k| try node_keys.append(k);
        for (transform_keys.items) |k| try node_keys.append(k);

        var nkI: usize = 0;
        while (nkI < node_keys.items.len) {
            const nodekey = node_keys.items[nkI];

            var childinj = try inj.child(nkI, node_keys.items);
            childinj.mode = M_KEYPRE;

            // Phase 1: KEYPRE — inject the key string.
            const pre_key = try injectStr(allocator, nodekey, store, childinj);

            // Injection may modify child processing state.
            nkI = childinj.key_i;
            node_keys = blk: {
                var nk = std.ArrayList([]const u8).init(allocator);
                for (childinj.keys) |k| try nk.append(k);
                break :blk nk;
            };
            current = childinj.parent;

            if (pre_key != .null) {
                const prekey_str = if (pre_key == .string) pre_key.string else nodekey;
                const childval = try getprop(allocator, current, JsonValue{ .string = prekey_str }, .null);
                childinj.val = childval;
                childinj.mode = M_VAL;

                // Phase 2: VAL — inject the child value.
                _ = try injectVal(allocator, childval, store, childinj);

                nkI = childinj.key_i;
                node_keys = blk: {
                    var nk = std.ArrayList([]const u8).init(allocator);
                    for (childinj.keys) |k| try nk.append(k);
                    break :blk nk;
                };
                current = childinj.parent;

                // Phase 3: KEYPOST — post-process the key.
                childinj.mode = M_KEYPOST;
                _ = try injectStr(allocator, nodekey, store, childinj);

                nkI = childinj.key_i;
                node_keys = blk: {
                    var nk = std.ArrayList([]const u8).init(allocator);
                    for (childinj.keys) |k| try nk.append(k);
                    break :blk nk;
                };
                current = childinj.parent;
            }

            nkI += 1;
        }
    } else if (val == .string) {
        // Inject paths into string scalars.
        inj.mode = M_VAL;
        const result = try injectStr(allocator, val.string, store, inj);
        if (result != .null or val != .null) {
            _ = try inj.setval(result, 0);
        }
        current = result;
    }

    inj.val = current;

    // Return value is the top-level result.
    return try getprop(allocator, inj.parent, JsonValue{ .string = S_DTOP }, .null);
}

// ============================================================================
// injectStr — resolve backtick path references using the Injection context.
// ============================================================================

fn injectStr(allocator: Allocator, val: []const u8, store: JsonValue, inj: *Injection) !JsonValue {
    if (val.len == 0) return JsonValue{ .string = S_MT };

    // Full injection: entire string is `path` (possibly with trailing digits).
    if (val.len >= 2 and val[0] == '`' and val[val.len - 1] == '`') {
        var inner_bt: usize = 0;
        for (val[1 .. val.len - 1]) |c| {
            if (c == '`') inner_bt += 1;
        }
        if (inner_bt == 0) {
            inj.full = true;
            var pathref = val[1 .. val.len - 1];
            pathref = stripCmdDigits(pathref);
            pathref = resolveSpecialEscapes(allocator, pathref);
            return try resolvePathOrCmd(allocator, pathref, store, inj);
        }
    }

    // No backticks → return as-is.
    if (std.mem.indexOf(u8, val, "`") == null) {
        return JsonValue{ .string = val };
    }

    // Partial injection: replace each `ref` segment.
    inj.full = false;
    var result = std.ArrayList(u8).init(allocator);
    var i: usize = 0;
    while (i < val.len) {
        if (val[i] == '`') {
            const close = std.mem.indexOfScalarPos(u8, val, i + 1, '`');
            if (close) |end| {
                var ref = val[i + 1 .. end];
                ref = resolveSpecialEscapes(allocator, ref);
                const found = try resolvePathOnly(allocator, ref, store, inj);
                if (found == .string) {
                    try result.appendSlice(found.string);
                } else if (found == .null) {
                    // Check if the key actually exists in the store with a null value
                    // vs being absent. If present, stringify as "null".
                    const exists = blk: {
                        if (store == .object) {
                            if (store.object.get(ref) != null) break :blk true;
                            // Check in $TOP
                            if (store.object.get(S_DTOP)) |top| {
                                if (top == .object and top.object.get(ref) != null) break :blk true;
                            }
                        }
                        break :blk false;
                    };
                    if (exists) try result.appendSlice("null");
                } else {
                    try result.appendSlice(try stringifyInner(allocator, found));
                }
                i = end + 1;
            } else {
                try result.append(val[i]);
                i += 1;
            }
        } else {
            try result.append(val[i]);
            i += 1;
        }
    }
    return JsonValue{ .string = result.items };
}

// Resolve a path reference that may be a command or a data path.
fn resolvePathOrCmd(allocator: Allocator, pathref: []const u8, store: JsonValue, inj: *Injection) !JsonValue {
    // Built-in escape commands (always resolve regardless of mode).
    if (std.mem.eql(u8, pathref, "$BT")) return JsonValue{ .string = S_BT };
    if (std.mem.eql(u8, pathref, "$DS")) return JsonValue{ .string = S_DS };

    // Command dispatch — mode-sensitive.
    if (pathref.len > 0 and pathref[0] == '$') {
        return try dispatchCmd(allocator, pathref, store, inj);
    }

    // Relative path.
    if (pathref.len > 0 and pathref[0] == '.') {
        return try resolveRelativePath(allocator, pathref, inj.dparent);
    }

    // Absolute path from store.
    return try getpath(allocator, JsonValue{ .string = pathref }, store);
}

// Resolve a path reference (no command dispatch — used for partial injections).
fn resolvePathOnly(allocator: Allocator, pathref: []const u8, store: JsonValue, inj: *Injection) !JsonValue {
    if (std.mem.eql(u8, pathref, "$BT")) return JsonValue{ .string = S_BT };
    if (std.mem.eql(u8, pathref, "$DS")) return JsonValue{ .string = S_DS };

    if (pathref.len > 0 and pathref[0] == '.') {
        return try resolveRelativePath(allocator, pathref, inj.dparent);
    }

    return try getpath(allocator, JsonValue{ .string = pathref }, store);
}

// ============================================================================
// Command dispatch — routes $ commands to handlers based on mode.
// ============================================================================

fn dispatchCmd(allocator: Allocator, cmd: []const u8, store: JsonValue, inj: *Injection) !JsonValue {
    if (std.mem.eql(u8, cmd, "$COPY")) return cmdCopy(allocator, inj);
    if (std.mem.eql(u8, cmd, "$DELETE")) return cmdDelete(inj);
    if (std.mem.eql(u8, cmd, "$KEY")) return cmdKey(inj);
    if (std.mem.eql(u8, cmd, "$MERGE")) return try cmdMerge(allocator, inj, store);
    if (std.mem.eql(u8, cmd, "$ANNO")) return cmdAnno(inj);

    // Commands not yet implemented return null.
    // TODO: $EACH, $PACK, $REF, $FORMAT, $APPLY
    return .null;
}

fn cmdCopy(allocator: Allocator, inj: *Injection) JsonValue {
    if (inj.mode != M_VAL) return .null;
    const out = getprop(allocator, inj.dparent, JsonValue{ .string = inj.key }, .null) catch .null;
    _ = inj.setval(out, 0) catch {};
    return out;
}

fn cmdDelete(inj: *Injection) JsonValue {
    _ = inj.setval(.null, 0) catch {};
    return .null;
}

fn cmdKey(inj: *Injection) JsonValue {
    if (inj.mode != M_VAL) return .null;

    // Check for `$KEY` meta property on the parent.
    if (inj.parent == .object) {
        if (inj.parent.object.get(S_BKEY)) |keyspec| {
            _ = inj.parent.object.fetchOrderedRemove(S_BKEY);
            return getprop(inj.allocator, inj.dparent, keyspec, .null) catch .null;
        }
        // Check for $KEY inside $ANNO.
        if (inj.parent.object.get(S_BANNO)) |anno| {
            if (anno == .object) {
                if (anno.object.get(S_KEY)) |pkey| {
                    return pkey;
                }
            }
        }
    }

    // Fallback: second-to-last path element.
    if (inj.path.len >= 2) {
        return JsonValue{ .string = inj.path[inj.path.len - 2] };
    }
    return .null;
}

fn cmdMerge(allocator: Allocator, inj: *Injection, store: JsonValue) !JsonValue {
    if (inj.mode == M_KEYPRE) {
        // In KEYPRE, just return the key so processing continues.
        return JsonValue{ .string = inj.key };
    }

    if (inj.mode == M_KEYPOST) {
        const args = try getprop(allocator, inj.parent, JsonValue{ .string = inj.key }, .null);

        // Remove the $MERGE key from parent.
        if (inj.parent == .object) {
            _ = inj.parent.object.fetchOrderedRemove(inj.key);
        }

        var merge_list = JsonArray{};
        try merge_list.append(allocator, inj.parent);

        if (args == .string and args.string.len == 0) {
            const top = getpropFromStore(store);
            if (top != .null) try merge_list.append(allocator, try clone(allocator, top));
        } else if (args == .array) {
            for (args.array.items) |item| {
                if (item != .null) try merge_list.append(allocator, item);
            }
        } else if (args != .null) {
            try merge_list.append(allocator, args);
        }

        // Literals in parent have precedence.
        try merge_list.append(allocator, try clone(allocator, inj.parent));

        const merged = try merge(allocator, JsonValue{ .array = merge_list }, MAXDEPTH);
        inj.parent = merged;

        return JsonValue{ .string = inj.key };
    }

    // M_VAL for $MERGE in a list context → remove it.
    return .null;
}

fn cmdAnno(inj: *Injection) JsonValue {
    if (inj.parent == .object) {
        _ = inj.parent.object.fetchOrderedRemove(S_BANNO);
    }
    return .null;
}

// ============================================================================
// Transform — public API. Builds store and calls Inject.
// ============================================================================

pub fn transform(allocator: Allocator, data: JsonValue, spec: JsonValue) !JsonValue {
    if (spec == .null) return spec;

    var spec_clone = try clone(allocator, spec);
    const data_clone = if (data == .null) JsonValue{ .null = {} } else try clone(allocator, data);

    var store = JsonObjectMap{};
    try store.put(allocator, S_DTOP, data_clone);
    const store_val = JsonValue{ .object = store };

    return try injectVal(allocator, spec_clone, store_val, null);
}

// ============================================================================
// Helpers retained from previous implementation.
// ============================================================================

fn stripCmdDigits(pathref: []const u8) []const u8 {
    if (pathref.len == 0 or pathref[0] != '$') return pathref;
    var end: usize = pathref.len;
    while (end > 1 and pathref[end - 1] >= '0' and pathref[end - 1] <= '9') end -= 1;
    return pathref[0..end];
}

fn resolveSpecialEscapes(allocator: Allocator, pathref: []const u8) []const u8 {
    if (pathref.len <= 3) return pathref;
    if (std.mem.indexOf(u8, pathref, "$BT") == null and
        std.mem.indexOf(u8, pathref, "$DS") == null) return pathref;
    var result = std.ArrayList(u8).init(allocator);
    var i: usize = 0;
    while (i < pathref.len) {
        if (i + 3 <= pathref.len and std.mem.eql(u8, pathref[i .. i + 3], "$BT")) {
            result.append('`') catch {};
            i += 3;
        } else if (i + 3 <= pathref.len and std.mem.eql(u8, pathref[i .. i + 3], "$DS")) {
            result.append('$') catch {};
            i += 3;
        } else {
            result.append(pathref[i]) catch {};
            i += 1;
        }
    }
    return result.items;
}

fn resolveRelativePath(allocator: Allocator, pathref: []const u8, dparent: JsonValue) !JsonValue {
    var dots: usize = 0;
    while (dots < pathref.len and pathref[dots] == '.') dots += 1;

    const rest = pathref[dots..];
    if (rest.len == 0) return dparent;

    var val = dparent;
    var it = std.mem.splitScalar(u8, rest, '.');
    while (it.next()) |part| {
        if (val == .null) break;
        val = try getprop(allocator, val, JsonValue{ .string = part }, .null);
    }
    return val;
}


