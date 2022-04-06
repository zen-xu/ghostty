const TextRenderer = @This();

const std = @import("std");
const ftc = @import("freetype/c.zig");
const gl = @import("opengl.zig");
const gb = @import("gb_math.zig");
const Atlas = @import("Atlas.zig");
const FontAtlas = @import("FontAtlas.zig");

alloc: std.mem.Allocator,
projection: gb.gbMat4 = undefined,

font: FontAtlas,
atlas: Atlas,

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
    var atlas = try Atlas.init(alloc, 512);
    errdefer atlas.deinit(alloc);
    var font = try FontAtlas.init(atlas);
    errdefer font.deinit(alloc);
    try font.loadFaceFromMemory(face_ttf, 48);

    // Load all visible ASCII characters.
    var i: u8 = 32;
    while (i < 127) : (i += 1) {
        try font.addGlyph(alloc, i);
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
        @intCast(c_int, atlas.size),
        @intCast(c_int, atlas.size),
        0,
        .Red,
        .UnsignedByte,
        atlas.data.ptr,
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

pub fn deinit(self: *TextRenderer, alloc: std.mem.Allocator) void {
    self.font.deinit(alloc);
    self.atlas.deinit(alloc);
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

    var vertices: std.ArrayListUnmanaged([4][9]f32) = .{};
    try vertices.ensureUnusedCapacity(self.alloc, text.len);
    defer vertices.deinit(self.alloc);

    var indices: std.ArrayListUnmanaged([6]u32) = .{};
    try indices.ensureUnusedCapacity(self.alloc, text.len);
    defer indices.deinit(self.alloc);

    var curx: f32 = x;
    for (text) |c, i| {
        if (self.font.getGlyph(c)) |glyph_ptr| {
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

            const vert = [4][9]f32{
                .{ x0, y0, 0, s0, t0, r, g, b, a },
                .{ x0, y1, 0, s0, t1, r, g, b, a },
                .{ x1, y1, 0, s1, t1, r, g, b, a },
                .{ x1, y0, 0, s1, t0, r, g, b, a },
            };

            vertices.appendAssumeCapacity(vert);

            const idx = @intCast(u32, 4 * i);
            indices.appendAssumeCapacity([6]u32{
                idx, idx + 1, idx + 2, // 0, 1, 2
                idx, idx + 2, idx + 3, // 0, 2, 3
            });

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

    // Array buffer
    const vbo = try gl.Buffer.create();
    defer vbo.destroy();
    var binding = try vbo.bind(.ArrayBuffer);
    defer binding.unbind();
    try binding.setData(vertices.items, .DynamicDraw);
    try binding.attribute(0, 3, [9]f32, 0);
    try binding.attribute(1, 2, [9]f32, 3);
    try binding.attribute(2, 4, [9]f32, 5);

    // Element buffer
    const ebo = try gl.Buffer.create();
    defer ebo.destroy();
    var ebobinding = try ebo.bind(.ElementArrayBuffer);
    defer ebobinding.unbind();
    try ebobinding.setData(indices.items, .DynamicDraw);

    //try gl.drawArrays(gl.c.GL_TRIANGLES, 0, @intCast(c_int, vertices.items.len * 6));
    try gl.drawElements(gl.c.GL_TRIANGLES, @intCast(c_int, indices.items.len * 6), gl.c.GL_UNSIGNED_INT, 0);
    try gl.VertexArray.unbind();
}

const face_ttf = @embedFile("../fonts/Inconsolata-Regular.ttf");
