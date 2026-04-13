// Test runner for Zig — loads build/test/test.json and drives specs
// against subject functions, mirroring the TS/Go runner pattern.

const std = @import("std");
const voxgig_struct = @import("voxgig-struct");

const Allocator = std.mem.Allocator;
const JsonValue = std.json.Value;
const JsonObjectMap = std.json.ObjectMap;
const JsonArray = std.json.Array;

pub const NULLMARK = "__NULL__";
pub const UNDEFMARK = "__UNDEF__";
pub const EXISTSMARK = "__EXISTS__";

pub const TEST_JSON_FILE = "../build/test/test.json";

pub const Subject = *const fn (JsonValue) JsonValue;

pub const Spec = struct {
    data: JsonValue,

    pub fn get(self: Spec, key: []const u8) ?JsonValue {
        return switch (self.data) {
            .object => |obj| obj.get(key),
            else => null,
        };
    }
};

pub const RunPack = struct {
    spec: Spec,
    allocator: Allocator,
    file_data: []const u8,
    parsed: std.json.Parsed(JsonValue),

    /// Run all entries in testspec.set against the subject function.
    pub fn runset(self: RunPack, testspec: JsonValue, subject: Subject) !void {
        try self.runsetflags(testspec, .{}, subject);
    }

    /// Run with flags (e.g. .{ .null_flag = false }).
    pub fn runsetflags(self: RunPack, testspec: JsonValue, flags: Flags, subject: Subject) !void {
        _ = self;
        const set = switch (testspec) {
            .object => |obj| obj.get("set") orelse return error.NoSetInSpec,
            else => return error.SpecNotObject,
        };
        const entries = switch (set) {
            .array => |arr| arr.items,
            else => return error.SetNotArray,
        };

        for (entries) |entry_val| {
            const entry = switch (entry_val) {
                .object => |obj| obj,
                else => continue,
            };

            // Resolve input: use "in" field if present, else null.
            const in_val: JsonValue = entry.get("in") orelse .null;

            // Resolve expected output.
            const raw_out = entry.get("out");
            const expected: JsonValue = if (raw_out) |o| o else if (flags.null_flag) JsonValue{ .string = NULLMARK } else .null;

            // Check for expected error.
            const err_field = entry.get("err");

            // Call subject.
            const result = subject(in_val);

            // If an error was expected, skip for now (subject returns a value,
            // not an error).
            if (err_field != null) continue;

            // Compare result with expected.
            try checkResult(expected, result);
        }
    }

    pub fn deinit(self: *RunPack) void {
        self.parsed.deinit();
        self.allocator.free(self.file_data);
    }
};

pub const Flags = struct {
    null_flag: bool = true,
};

/// Load test.json and return the "struct" spec.
pub fn makeRunner(allocator: Allocator) !RunPack {
    const path = TEST_JSON_FILE;
    const data = try std.fs.cwd().readFileAlloc(allocator, path, 10 * 1024 * 1024);
    const parsed = try std.json.parseFromSlice(JsonValue, allocator, data, .{});
    const root = parsed.value;

    // spec = root["struct"] (mirrors resolveSpec("struct", testfile) in TS)
    const spec_val = switch (root) {
        .object => |obj| obj.get("struct") orelse return error.NoStructInTestJson,
        else => return error.TestJsonNotObject,
    };

    return RunPack{
        .spec = Spec{ .data = spec_val },
        .allocator = allocator,
        .file_data = data,
        .parsed = parsed,
    };
}

// ---- Result comparison (mirrors checkResult / fixJSON in TS runner) ----

fn checkResult(expected: JsonValue, result: JsonValue) !void {
    // Direct equality fast-path.
    if (jsonEqual(expected, result)) return;

    // NULLMARK means we expect .null
    if (expected == .string) {
        if (std.mem.eql(u8, expected.string, NULLMARK)) {
            if (result == .null) return;
        }
    }

    // Mismatch.
    std.debug.print("\n  FAIL: expected {s} got {s}\n", .{
        fmtJson(expected),
        fmtJson(result),
    });
    return error.ResultMismatch;
}

fn fmtJson(val: JsonValue) []const u8 {
    return switch (val) {
        .null => "null",
        .bool => |b| if (b) "true" else "false",
        .integer => "integer",
        .float => "float",
        .string => |s| s,
        .array => "array",
        .object => "object",
        .number_string => |s| s,
    };
}

/// Deep equality for JsonValue.
pub fn jsonEqual(a: JsonValue, b: JsonValue) bool {
    const TagType = std.meta.Tag(JsonValue);
    const tag_a: TagType = a;
    const tag_b: TagType = b;
    if (tag_a != tag_b) return false;

    return switch (a) {
        .null => true,
        .bool => |av| av == b.bool,
        .integer => |av| av == b.integer,
        .float => |av| av == b.float,
        .string => |av| std.mem.eql(u8, av, b.string),
        .number_string => |av| std.mem.eql(u8, av, b.number_string),
        .array => |av| {
            const bv = b.array;
            if (av.items.len != bv.items.len) return false;
            for (av.items, bv.items) |ai, bi| {
                if (!jsonEqual(ai, bi)) return false;
            }
            return true;
        },
        .object => |av| {
            const bv = b.object;
            if (av.count() != bv.count()) return false;
            var it = av.iterator();
            while (it.next()) |kv| {
                const bval = bv.get(kv.key_ptr.*) orelse return false;
                if (!jsonEqual(kv.value_ptr.*, bval)) return false;
            }
            return true;
        },
    };
}
