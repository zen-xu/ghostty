const std = @import("std");
const mem = std.mem;
const assert = std.debug.assert;

// TODO:
//   - Only `--long=value` format is accepted. Do we want to allow
//     `--long value`? Not currently allowed.

/// Parse the command line arguments from iter into dst.
///
/// dst must be a struct. The fields and their types will be used to determine
/// the valid CLI flags. See the tests in this file as an example. For field
/// types that are structs, the struct can implement the `parseCLI` function
/// to do custom parsing.
pub fn parse(comptime T: type, dst: *T, iter: anytype) !void {
    const info = @typeInfo(T);
    assert(info == .Struct);

    while (iter.next()) |arg| {
        if (mem.startsWith(u8, arg, "--")) {
            var key: []const u8 = arg[2..];
            const value: ?[]const u8 = value: {
                // If the arg has "=" then the value is after the "=".
                if (mem.indexOf(u8, key, "=")) |idx| {
                    defer key = key[0..idx];
                    break :value key[idx + 1 ..];
                }

                break :value null;
            };

            try parseIntoField(T, dst, key, value);
        }
    }
}

/// Parse a single key/value pair into the destination type T.
fn parseIntoField(comptime T: type, dst: *T, key: []const u8, value: ?[]const u8) !void {
    const info = @typeInfo(T);
    assert(info == .Struct);

    inline for (info.Struct.fields) |field| {
        if (mem.eql(u8, field.name, key)) {
            @field(dst, field.name) = field: {
                const Field = field.field_type;
                const fieldInfo = @typeInfo(Field);

                // If the type implements a parse function, call that.
                if (fieldInfo == .Struct and @hasDecl(Field, "parseCLI"))
                    break :field try Field.parseCLI(value);

                // Otherwise infer based on type
                break :field switch (Field) {
                    []const u8 => value orelse return error.ValueRequired,
                    bool => try parseBool(value orelse "t"),
                    else => unreachable,
                };
            };

            return;
        }
    }

    return error.InvalidFlag;
}

fn parseBool(v: []const u8) !bool {
    const t = &[_][]const u8{ "1", "t", "T", "true" };
    const f = &[_][]const u8{ "0", "f", "F", "false" };

    inline for (t) |str| {
        if (mem.eql(u8, v, str)) return true;
    }
    inline for (f) |str| {
        if (mem.eql(u8, v, str)) return false;
    }

    return error.InvalidBooleanValue;
}

test "parse: simple" {
    const testing = std.testing;

    var data: struct {
        a: []const u8,
        b: bool,
        @"b-f": bool,
    } = undefined;

    var iter = try std.process.ArgIteratorGeneral(.{}).init(
        testing.allocator,
        "--a=42 --b --b-f=false",
    );
    defer iter.deinit();
    try parse(@TypeOf(data), &data, &iter);
    try testing.expectEqualStrings("42", data.a);
    try testing.expect(data.b);
    try testing.expect(!data.@"b-f");
}

test "parseIntoField: string" {
    const testing = std.testing;

    var data: struct {
        a: []const u8,
    } = undefined;

    try parseIntoField(@TypeOf(data), &data, "a", "42");
    try testing.expectEqual(@as([]const u8, "42"), data.a);
}

test "parseIntoField: bool" {
    const testing = std.testing;

    var data: struct {
        a: bool,
    } = undefined;

    // True
    try parseIntoField(@TypeOf(data), &data, "a", "1");
    try testing.expectEqual(true, data.a);
    try parseIntoField(@TypeOf(data), &data, "a", "t");
    try testing.expectEqual(true, data.a);
    try parseIntoField(@TypeOf(data), &data, "a", "T");
    try testing.expectEqual(true, data.a);
    try parseIntoField(@TypeOf(data), &data, "a", "true");
    try testing.expectEqual(true, data.a);

    // False
    try parseIntoField(@TypeOf(data), &data, "a", "0");
    try testing.expectEqual(false, data.a);
    try parseIntoField(@TypeOf(data), &data, "a", "f");
    try testing.expectEqual(false, data.a);
    try parseIntoField(@TypeOf(data), &data, "a", "F");
    try testing.expectEqual(false, data.a);
    try parseIntoField(@TypeOf(data), &data, "a", "false");
    try testing.expectEqual(false, data.a);
}

test "parseIntoField: struct with parse func" {
    const testing = std.testing;

    var data: struct {
        a: struct {
            const Self = @This();

            v: []const u8,

            pub fn parseCLI(value: ?[]const u8) !Self {
                _ = value;
                return Self{ .v = "HELLO!" };
            }
        },
    } = undefined;

    try parseIntoField(@TypeOf(data), &data, "a", "42");
    try testing.expectEqual(@as([]const u8, "HELLO!"), data.a.v);
}
