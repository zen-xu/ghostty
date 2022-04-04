const TextRenderer = @This();

const std = @import("std");
const ftc = @import("freetype/c.zig");
const gl = @import("opengl.zig");

alloc: std.mem.Allocator,
ft: ftc.FT_Library,
face: ftc.FT_Face,
chars: CharList,

const CharList = std.ArrayListUnmanaged(Char);
const Char = struct {
    tex: gl.Texture,
    size: @Vector(2, c_uint),
    bearing: @Vector(2, c_int),
    advance: c_uint,
};

pub fn init(alloc: std.mem.Allocator) !TextRenderer {
    var ft: ftc.FT_Library = undefined;
    if (ftc.FT_Init_FreeType(&ft) != 0) {
        return error.FreetypeInitFailed;
    }

    var face: ftc.FT_Face = undefined;
    if (ftc.FT_New_Memory_Face(
        ft,
        face_ttf,
        face_ttf.len,
        0,
        &face,
    ) != 0) {
        return error.FreetypeFaceFailed;
    }

    _ = ftc.FT_Set_Pixel_Sizes(face, 0, 48);

    // disable byte-alignment restriction
    gl.c.glPixelStorei(gl.c.GL_UNPACK_ALIGNMENT, 1);

    // Pre-render all the ASCII characters
    var chars = try CharList.initCapacity(alloc, 128);
    var i: usize = 0;
    while (i < chars.capacity) : (i += 1) {
        // Load the character
        if (ftc.FT_Load_Char(face, i, ftc.FT_LOAD_RENDER) != 0) {
            return error.GlyphLoadFailed;
        }

        if (face.*.glyph.*.bitmap.buffer == null) {
            // Unrenderable characters
            chars.appendAssumeCapacity(.{
                .tex = undefined,
                .size = undefined,
                .bearing = undefined,
                .advance = undefined,
            });
            continue;
        }

        // Generate the texture
        const tex = try gl.Texture.create();
        var binding = try tex.bind(gl.c.GL_TEXTURE_2D);
        defer binding.unbind();
        try binding.image2D(
            0,
            gl.c.GL_RED,
            @intCast(c_int, face.*.glyph.*.bitmap.width),
            @intCast(c_int, face.*.glyph.*.bitmap.rows),
            0,
            gl.c.GL_RED,
            gl.c.GL_UNSIGNED_BYTE,
            face.*.glyph.*.bitmap.buffer,
        );
        try binding.parameter(gl.c.GL_TEXTURE_WRAP_S, gl.c.GL_CLAMP_TO_EDGE);
        try binding.parameter(gl.c.GL_TEXTURE_WRAP_T, gl.c.GL_CLAMP_TO_EDGE);
        try binding.parameter(gl.c.GL_TEXTURE_MIN_FILTER, gl.c.GL_LINEAR);
        try binding.parameter(gl.c.GL_TEXTURE_MAG_FILTER, gl.c.GL_LINEAR);

        // Store the character
        chars.appendAssumeCapacity(.{
            .tex = tex,
            .size = .{
                face.*.glyph.*.bitmap.width,
                face.*.glyph.*.bitmap.rows,
            },
            .bearing = .{
                face.*.glyph.*.bitmap_left,
                face.*.glyph.*.bitmap_top,
            },
            .advance = @intCast(c_uint, face.*.glyph.*.advance.x),
        });
    }

    return TextRenderer{
        .alloc = alloc,
        .ft = ft,
        .face = face,
        .chars = chars,
    };
}

pub fn deinit(self: *TextRenderer) void {
    // TODO: delete textures
    self.chars.deinit(self.alloc);

    if (ftc.FT_Done_Face(self.face) != 0)
        std.log.err("freetype face deinitialization failed", .{});
    if (ftc.FT_Done_FreeType(self.ft) != 0)
        std.log.err("freetype library deinitialization failed", .{});

    self.* = undefined;
}

const face_ttf = @embedFile("../fonts/Inconsolata-Regular.ttf");
