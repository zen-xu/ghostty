const TextRenderer = @This();

const std = @import("std");
const ftc = @import("freetype/c.zig");
const gl = @import("opengl.zig");
const gb = @import("gb_math.zig");

alloc: std.mem.Allocator,
ft: ftc.FT_Library,
face: ftc.FT_Face,
chars: CharList,
vao: gl.VertexArray = undefined,
vbo: gl.Buffer = undefined,
program: gl.Program = undefined,
projection: gb.gbMat4 = undefined,

const CharList = std.ArrayListUnmanaged(Char);
const Char = struct {
    tex: gl.Texture,
    size: @Vector(2, f32),
    bearing: @Vector(2, f32),
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
    try gl.pixelStore(gl.c.GL_UNPACK_ALIGNMENT, 1);

    // Pre-render all the ASCII characters
    var chars = try CharList.initCapacity(alloc, 128);
    var i: usize = 0;
    while (i < chars.capacity) : (i += 1) {
        // Load the character
        if (ftc.FT_Load_Char(face, i, ftc.FT_LOAD_RENDER) != 0) {
            return error.GlyphLoadFailed;
        }

        // Generate the texture
        const tex = try gl.Texture.create();
        var binding = try tex.bind(.@"2D");
        defer binding.unbind();
        try binding.image2D(
            0,
            .Red,
            @intCast(c_int, face.*.glyph.*.bitmap.width),
            @intCast(c_int, face.*.glyph.*.bitmap.rows),
            0,
            .Red,
            .UnsignedByte,
            face.*.glyph.*.bitmap.buffer,
        );
        try binding.parameter(.WrapS, gl.c.GL_CLAMP_TO_EDGE);
        try binding.parameter(.WrapT, gl.c.GL_CLAMP_TO_EDGE);
        try binding.parameter(.MinFilter, gl.c.GL_LINEAR);
        try binding.parameter(.MagFilter, gl.c.GL_LINEAR);

        // Store the character
        chars.appendAssumeCapacity(.{
            .tex = tex,
            .size = .{
                @intToFloat(f32, face.*.glyph.*.bitmap.width),
                @intToFloat(f32, face.*.glyph.*.bitmap.rows),
            },
            .bearing = .{
                @intToFloat(f32, face.*.glyph.*.bitmap_left),
                @intToFloat(f32, face.*.glyph.*.bitmap_top),
            },
            .advance = @intCast(c_uint, face.*.glyph.*.advance.x),
        });
    }

    // Configure VAO/VBO for glyph rendering
    const vao = try gl.VertexArray.create();
    const vbo = try gl.Buffer.create();
    try vao.bind();
    var binding = try vbo.bind(.ArrayBuffer);
    try binding.setDataNull([6 * 4]f32, .DynamicDraw);
    try binding.enableVertexAttribArray(0);
    try binding.vertexAttribPointer(0, 4, gl.c.GL_FLOAT, false, 4 * @sizeOf(f32), null);
    binding.unbind();
    try gl.VertexArray.unbind();

    // Create our shader
    const program = try gl.Program.createVF(
        @embedFile("../shaders/text.v.glsl"),
        @embedFile("../shaders/text.f.glsl"),
    );

    var res = TextRenderer{
        .alloc = alloc,
        .ft = ft,
        .face = face,
        .chars = chars,
        .program = program,
        .vao = vao,
        .vbo = vbo,
        .projection = undefined,
    };

    // Update the initialize size so we have some projection. We
    // expect this will get updated almost immediately.
    try res.setScreenSize(3000, 1666);

    return res;
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
    scale: f32,
    color: @Vector(3, f32),
) !void {
    try self.program.use();
    try self.program.setUniform("textColor", color);
    try gl.Texture.active(gl.c.GL_TEXTURE0);
    try self.vao.bind();

    var curx: f32 = x;
    for (text) |c| {
        const char = self.chars.items[c];

        const xpos = curx + (char.bearing[0] * scale);
        const ypos = y - ((char.size[1] - char.bearing[1]) * scale);
        const w = char.size[0] * scale;
        const h = char.size[1] * scale;

        const vert = [6][4]f32{
            .{ xpos, ypos + h, 0.0, 0.0 },
            .{ xpos, ypos, 0.0, 1.0 },
            .{ xpos + w, ypos, 1.0, 1.0 },

            .{ xpos, ypos + h, 0.0, 0.0 },
            .{ xpos + w, ypos, 1.0, 1.0 },
            .{ xpos + w, ypos + h, 1.0, 0.0 },
        };

        var texbind = try char.tex.bind(.@"2D");
        defer texbind.unbind();
        var bind = try self.vbo.bind(.ArrayBuffer);
        try bind.setSubData(0, vert);
        bind.unbind();

        try gl.drawArrays(gl.c.GL_TRIANGLES, 0, 6);

        curx += @intToFloat(f32, char.advance >> 6) * scale;
    }

    try gl.VertexArray.unbind();
}

const face_ttf = @embedFile("../fonts/Inconsolata-Regular.ttf");
