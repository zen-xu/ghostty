const TextRenderer = @This();

const std = @import("std");
const ftc = @import("freetype/c.zig");
const gl = @import("opengl.zig");
const gb = @import("gb_math.zig");
const ftgl = @import("freetype-gl/c.zig");

alloc: std.mem.Allocator,
projection: gb.gbMat4 = undefined,
font: *ftgl.texture_font_t,
atlas: *ftgl.texture_atlas_t,

program: gl.Program,
tex: gl.Texture,

const CharList = std.ArrayListUnmanaged(Char);
const Char = struct {
    tex: gl.Texture,
    size: @Vector(2, f32),
    bearing: @Vector(2, f32),
    advance: c_uint,
};

pub fn init(alloc: std.mem.Allocator) !TextRenderer {
    const atlas = ftgl.texture_atlas_new(512, 512, 1);
    if (atlas == null) return error.FontAtlasFail;
    errdefer ftgl.texture_atlas_delete(atlas);
    const font = ftgl.texture_font_new_from_memory(
        atlas,
        48,
        face_ttf,
        face_ttf.len,
    );
    if (font == null) return error.FontInitFail;
    errdefer ftgl.texture_font_delete(font);

    // Load all visible ASCII characters.
    var i: u8 = 32;
    while (i < 127) : (i += 1) {
        // Load the character
        if (ftgl.texture_font_load_glyph(font, &i) == 0) {
            return error.GlyphLoadFailed;
        }
    }

    // Build our texture
    const tex = try gl.Texture.create();
    errdefer tex.destroy();
    const binding = try tex.bind(.@"2D");
    try binding.parameter(.WrapS, gl.c.GL_CLAMP_TO_EDGE);
    try binding.parameter(.WrapT, gl.c.GL_CLAMP_TO_EDGE);
    try binding.parameter(.MinFilter, gl.c.GL_LINEAR);
    try binding.parameter(.MagFilter, gl.c.GL_LINEAR);
    try binding.image2D(
        0,
        .Red,
        @intCast(c_int, atlas.*.width),
        @intCast(c_int, atlas.*.height),
        0,
        .Red,
        .UnsignedByte,
        atlas.*.data,
    );

    // Create our shader
    const program = try gl.Program.createVF(
        @embedFile("../shaders/text-atlas.v.glsl"),
        @embedFile("../shaders/text-atlas.f.glsl"),
    );

    var res = TextRenderer{
        .alloc = alloc,
        .font = font,
        .atlas = atlas,
        .program = program,
        .tex = tex,
    };

    // Update the initialize size so we have some projection. We
    // expect this will get updated almost immediately.
    try res.setScreenSize(3000, 1666);

    return res;
}

pub fn deinit(self: *TextRenderer) void {
    ftgl.texture_font_delete(self.font);
    ftgl.texture_atlas_delete(self.atlas);
    self.* = undefined;
}

pub fn setScreenSize(self: *TextRenderer, w: i32, h: i32) !void {
    gb.gb_mat4_ortho2d(
        &self.projection,
        0,
        @intToFloat(f32, w),
        0,
        @intToFloat(f32, h),
    );

    try self.program.use();
    try self.program.setUniform("projection", self.projection);
}

pub fn render(
    self: TextRenderer,
    text: []const u8,
    x: f32,
    y: f32,
    color: @Vector(3, f32),
) !void {
    const r = color[0];
    const g = color[1];
    const b = color[2];
    const a: f32 = 1.0;

    var vertices: std.ArrayListUnmanaged([6][9]f32) = .{};
    try vertices.ensureUnusedCapacity(self.alloc, text.len);
    defer vertices.deinit(self.alloc);

    var curx: f32 = x;
    for (text) |c| {
        if (ftgl.texture_font_get_glyph(self.font, &c)) |glyph_ptr| {
            const glyph = glyph_ptr.*;
            const kerning = 0; // for now
            curx += kerning;

            const x0 = curx + @intToFloat(f32, glyph.offset_x);
            const y0 = y + @intToFloat(f32, glyph.offset_y);
            const x1 = x0 + @intToFloat(f32, glyph.width);
            const y1 = y0 - @intToFloat(f32, glyph.height);
            const s0 = glyph.s0;
            const t0 = glyph.t0;
            const s1 = glyph.s1;
            const t1 = glyph.t1;

            std.log.info("CHAR ch={} x0={} y0={} x1={} y1={}", .{ c, x0, y0, x1, y1 });

            const vert = [6][9]f32{
                .{ x0, y0, 0, s0, t0, r, g, b, a },
                .{ x0, y1, 0, s0, t1, r, g, b, a },
                .{ x1, y1, 0, s1, t1, r, g, b, a },
                .{ x0, y0, 0, s0, t0, r, g, b, a },
                .{ x1, y1, 0, s1, t1, r, g, b, a },
                .{ x1, y0, 0, s1, t0, r, g, b, a },
            };

            vertices.appendAssumeCapacity(vert);

            curx += glyph.advance_x;
        }
    }

    try self.program.use();

    // Bind our texture and set our data
    try gl.Texture.active(gl.c.GL_TEXTURE0);
    var texbind = try self.tex.bind(.@"2D");
    defer texbind.unbind();

    // Configure VAO/VBO for glyph rendering
    const vao = try gl.VertexArray.create();
    defer vao.destroy();
    try vao.bind();
    const vbo = try gl.Buffer.create();
    defer vbo.destroy();
    var binding = try vbo.bind(.ArrayBuffer);
    defer binding.unbind();
    try binding.setData(vertices.items, .DynamicDraw);
    try binding.attribute(0, 3, [9]f32, 0);
    try binding.attribute(1, 2, [9]f32, 3);
    try binding.attribute(2, 4, [9]f32, 5);

    try gl.drawArrays(gl.c.GL_TRIANGLES, 0, @intCast(c_int, vertices.items.len * 6));
    try gl.VertexArray.unbind();
}

const face_ttf = @embedFile("../fonts/Inconsolata-Regular.ttf");
