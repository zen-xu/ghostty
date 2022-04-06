//! Implements font loading and rendering into a texture atlas, using
//! Atlas as the backing implementation. The FontAtlas represents a single
//! face with a single size.
const FontAtlas = @This();

const std = @import("std");
const assert = std.debug.assert;
const testing = std.testing;
const Allocator = std.mem.Allocator;
const ftc = @import("freetype/c.zig");
const Atlas = @import("Atlas.zig");

const ftok = ftc.FT_Err_Ok;
const log = std.log.scoped(.font_atlas);

/// The texture atlas where all the font glyphs are rendered.
/// This is NOT owned by the FontAtlas, deinitialization must
/// be manually done.
atlas: Atlas,

/// The glyphs that are loaded into the atlas, keyed by codepoint.
glyphs: std.AutoHashMapUnmanaged(u32, Glyph),

/// The FreeType library
ft_library: ftc.FT_Library,

/// Our font face.
ft_face: ftc.FT_Face = null,

/// Information about a single glyph.
pub const Glyph = struct {
    /// width of glyph in pixels
    width: u32,

    /// height of glyph in pixels
    height: u32,

    /// left bearing
    offset_x: i32,

    /// top bearing
    offset_y: i32,

    /// normalized x, y (s, t) coordinates
    s0: f32,
    t0: f32,
    s1: f32,
    t1: f32,

    /// horizontal position to increase drawing position for strings
    advance_x: f32,
};

pub fn init(atlas: Atlas) !FontAtlas {
    var res = FontAtlas{
        .atlas = atlas,
        .ft_library = undefined,
        .glyphs = .{},
    };

    if (ftc.FT_Init_FreeType(&res.ft_library) != ftok)
        return error.FreeTypeInitFailed;

    return res;
}

pub fn deinit(self: *FontAtlas, alloc: Allocator) void {
    self.glyphs.deinit(alloc);

    if (self.ft_face != null) {
        if (ftc.FT_Done_Face(self.ft_face) != ftok)
            log.err("failed to clean up font face", .{});
    }

    if (ftc.FT_Done_FreeType(self.ft_library) != ftok)
        log.err("failed to clean up FreeType", .{});

    self.* = undefined;
}

/// Loads a font to use for the atlas.
///
/// This can only be called if a font is not already loaded.
pub fn loadFaceFromMemory(self: *FontAtlas, source: [:0]const u8, size: u32) !void {
    assert(self.ft_face == null);

    if (ftc.FT_New_Memory_Face(
        self.ft_library,
        source.ptr,
        @intCast(c_long, source.len),
        0,
        &self.ft_face,
    ) != ftok) return error.FaceLoadFailed;
    errdefer {
        _ = ftc.FT_Done_Face(self.ft_face);
        self.ft_face = null;
    }

    if (ftc.FT_Select_Charmap(self.ft_face, ftc.FT_ENCODING_UNICODE) != ftok)
        return error.FaceLoadFailed;

    if (ftc.FT_Set_Pixel_Sizes(self.ft_face, size, size) != ftok)
        return error.FaceLoadFailed;
}

/// Get the glyph for the given codepoint.
pub fn getGlyph(self: FontAtlas, v: anytype) ?*Glyph {
    const utf32 = codepoint(v);
    const entry = self.glyphs.getEntry(utf32) orelse return null;
    return entry.value_ptr;
}

/// Add a glyph to the font atlas. The codepoint can be either a u8 or
/// []const u8 depending on if you know it is ASCII or must be UTF-8 decoded.
pub fn addGlyph(self: *FontAtlas, alloc: Allocator, v: anytype) !void {
    assert(self.ft_face != null);

    // We need a UTF32 codepoint for freetype
    const utf32 = codepoint(v);

    // If we have this glyph loaded already then we're done.
    const gop = try self.glyphs.getOrPut(alloc, utf32);
    if (gop.found_existing) return;
    errdefer _ = self.glyphs.remove(utf32);

    const glyph_index = ftc.FT_Get_Char_Index(self.ft_face, utf32);

    // TODO: probably not an error because we want to add a box.
    if (glyph_index == 0) return error.CodepointNotFound;

    if (ftc.FT_Load_Glyph(
        self.ft_face,
        glyph_index,
        ftc.FT_LOAD_RENDER,
    ) != ftok) return error.LoadGlyphFailed;

    const glyph = self.ft_face.*.glyph;
    const bitmap = glyph.*.bitmap;

    const src_w = bitmap.width;
    const src_h = bitmap.rows;
    const tgt_w = src_w;
    const tgt_h = src_h;

    const region = try self.atlas.reserve(alloc, tgt_w, tgt_h);

    // Build our buffer
    const buffer = try alloc.alloc(u8, tgt_w * tgt_h);
    defer alloc.free(buffer);
    var dst_ptr = buffer;
    var src_ptr = bitmap.buffer;
    var i: usize = 0;
    while (i < src_h) : (i += 1) {
        std.mem.copy(u8, dst_ptr, src_ptr[0..bitmap.width]);
        dst_ptr = dst_ptr[tgt_w..];
        src_ptr += @intCast(usize, bitmap.pitch);
    }

    // Write the glyph information into the atlas
    assert(region.width == tgt_w);
    assert(region.height == tgt_h);
    self.atlas.set(region, buffer);

    gop.value_ptr.* = .{
        .width = tgt_w,
        .height = tgt_h,
        .offset_x = glyph.*.bitmap_left,
        .offset_y = glyph.*.bitmap_top,
        .s0 = @intToFloat(f32, region.x) / @intToFloat(f32, self.atlas.size),
        .t0 = @intToFloat(f32, region.y) / @intToFloat(f32, self.atlas.size),
        .s1 = @intToFloat(f32, region.x + tgt_w) / @intToFloat(f32, self.atlas.size),
        .t1 = @intToFloat(f32, region.y + tgt_h) / @intToFloat(f32, self.atlas.size),
        .advance_x = f26dot6ToFloat(glyph.*.advance.x),
    };

    log.debug("loaded glyph codepoint={} glyph={}", .{ utf32, gop.value_ptr.* });
}

/// Convert 26.6 pixel format to f32
fn f26dot6ToFloat(v: ftc.FT_F26Dot6) f32 {
    return @intToFloat(f32, v) / 64.0;
}

/// Returns the UTF-32 codepoint for the given value.
fn codepoint(v: anytype) u32 {
    // We need a UTF32 codepoint for freetype
    return switch (@TypeOf(v)) {
        comptime_int, u8 => @intCast(u32, v),
        []const u8 => @intCast(u32, try std.unicode.utfDecode(v)),
        else => @compileError("invalid codepoint type"),
    };
}

test {
    const alloc = testing.allocator;
    var font = try init(try Atlas.init(alloc, 512));
    defer font.deinit(alloc);
    defer font.atlas.deinit(alloc);

    try font.loadFaceFromMemory(testFont, 48);

    // Generate all visible ASCII
    var i: u8 = 32;
    while (i < 127) : (i += 1) {
        try font.addGlyph(alloc, i);
    }

    i = 32;
    while (i < 127) : (i += 1) {
        try testing.expect(font.getGlyph(i) != null);
    }
}

const testFont = @embedFile("../fonts/Inconsolata-Regular.ttf");
