//! SGR (Select Graphic Rendition) attribute parsing and types.

const std = @import("std");
const testing = std.testing;

/// Attribute type for SGR
pub const Attribute = union(enum) {
    /// Unset all attributes
    unset: void,

    /// Unknown attribute, the raw CSI command parameters are here.
    unknown: []const u16,

    /// Set foreground color as RGB values.
    direct_color_fg: RGB,

    /// Set background color as RGB values.
    direct_color_bg: RGB,

    pub const RGB = struct {
        r: u8,
        g: u8,
        b: u8,
    };
};

/// Parse a set of parameters to a SGR command into an attribute.
pub fn parse(params: []const u16) Attribute {
    // No parameters means unset
    if (params.len == 0) return .{ .unset = {} };

    switch (params[0]) {
        0 => if (params.len == 1) return .{ .unset = {} },

        38 => if ((params.len == 5 or params.len == 6) and params[1] == 2) {
            // In the 6-len form, ignore the 3rd param.
            const rgb = params[params.len - 3 .. params.len];

            // We use @truncate because the value should be 0 to 255. If
            // it isn't, the behavior is undefined so we just... truncate it.
            return .{
                .direct_color_fg = .{
                    .r = @truncate(u8, rgb[0]),
                    .g = @truncate(u8, rgb[1]),
                    .b = @truncate(u8, rgb[2]),
                },
            };
        },

        48 => if ((params.len == 5 or params.len == 6) and params[1] == 2) {
            // In the 6-len form, ignore the 3rd param.
            const rgb = params[params.len - 3 .. params.len];

            // We use @truncate because the value should be 0 to 255. If
            // it isn't, the behavior is undefined so we just... truncate it.
            return .{
                .direct_color_bg = .{
                    .r = @truncate(u8, rgb[0]),
                    .g = @truncate(u8, rgb[1]),
                    .b = @truncate(u8, rgb[2]),
                },
            };
        },

        else => {},
    }

    return .{ .unknown = params };
}

test "sgr: parse" {
    try testing.expect(parse(&[_]u16{}) == .unset);
    try testing.expect(parse(&[_]u16{0}) == .unset);
    try testing.expect(parse(&[_]u16{ 0, 1 }) == .unknown);

    {
        const v = parse(&[_]u16{ 38, 2, 40, 44, 52 });
        try testing.expect(v == .direct_color_fg);
        try testing.expectEqual(@as(u8, 40), v.direct_color_fg.r);
        try testing.expectEqual(@as(u8, 44), v.direct_color_fg.g);
        try testing.expectEqual(@as(u8, 52), v.direct_color_fg.b);
    }

    {
        const v = parse(&[_]u16{ 38, 2, 22, 40, 44, 52 });
        try testing.expect(v == .direct_color_fg);
        try testing.expectEqual(@as(u8, 40), v.direct_color_fg.r);
        try testing.expectEqual(@as(u8, 44), v.direct_color_fg.g);
        try testing.expectEqual(@as(u8, 52), v.direct_color_fg.b);
    }

    try testing.expect(parse(&[_]u16{ 38, 2, 44, 52 }) == .unknown);
    try testing.expect(parse(&[_]u16{ 38, 2, 22, 22, 40, 44, 52 }) == .unknown);

    {
        const v = parse(&[_]u16{ 48, 2, 40, 44, 52 });
        try testing.expect(v == .direct_color_bg);
        try testing.expectEqual(@as(u8, 40), v.direct_color_bg.r);
        try testing.expectEqual(@as(u8, 44), v.direct_color_bg.g);
        try testing.expectEqual(@as(u8, 52), v.direct_color_bg.b);
    }

    {
        const v = parse(&[_]u16{ 48, 2, 22, 40, 44, 52 });
        try testing.expect(v == .direct_color_bg);
        try testing.expectEqual(@as(u8, 40), v.direct_color_bg.r);
        try testing.expectEqual(@as(u8, 44), v.direct_color_bg.g);
        try testing.expectEqual(@as(u8, 52), v.direct_color_bg.b);
    }

    try testing.expect(parse(&[_]u16{ 48, 2, 44, 52 }) == .unknown);
    try testing.expect(parse(&[_]u16{ 48, 2, 22, 22, 40, 44, 52 }) == .unknown);
}
