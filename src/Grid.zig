//! Represents a single terminal grid.
const Grid = @This();

const std = @import("std");
const assert = std.debug.assert;
const testing = std.testing;
const Allocator = std.mem.Allocator;
const Atlas = @import("Atlas.zig");
const FontAtlas = @import("FontAtlas.zig");
const Terminal = @import("terminal/Terminal.zig");
const gl = @import("opengl.zig");
const gb = @import("gb_math.zig");

const log = std.log.scoped(.grid);

alloc: std.mem.Allocator,

/// Current dimensions for this grid.
size: GridSize,

/// Current cell dimensions for this grid.
cell_size: CellSize,

/// The current set of cells to render.
cells: std.ArrayListUnmanaged(GPUCell),

/// Shader program for cell rendering.
program: gl.Program,
vao: gl.VertexArray,
ebo: gl.Buffer,
vbo: gl.Buffer,
texture: gl.Texture,

/// The font atlas.
font_atlas: FontAtlas,

/// The raw structure that maps directly to the buffer sent to the vertex shader.
const GPUCell = struct {
    /// vec2 grid_coord
    grid_col: u16,
    grid_row: u16,

    /// vec2 glyph_pos
    glyph_x: u32 = 0,
    glyph_y: u32 = 0,

    /// vec2 glyph_size
    glyph_width: u32 = 0,
    glyph_height: u32 = 0,

    /// vec2 glyph_size
    glyph_offset_x: i32 = 0,
    glyph_offset_y: i32 = 0,

    /// vec4 fg_color_in
    fg_r: u8,
    fg_g: u8,
    fg_b: u8,
    fg_a: u8,

    /// vec4 bg_color_in
    bg_r: u8,
    bg_g: u8,
    bg_b: u8,
    bg_a: u8,

    /// uint mode
    mode: u8,
};

pub fn init(alloc: Allocator) !Grid {
    // Initialize our font atlas. We will initially populate the
    // font atlas with all the visible ASCII characters since they are common.
    var atlas = try Atlas.init(alloc, 512);
    errdefer atlas.deinit(alloc);
    var font = try FontAtlas.init(atlas);
    errdefer font.deinit(alloc);
    try font.loadFaceFromMemory(face_ttf, 30);

    // Load all visible ASCII characters and build our cell width based on
    // the widest character that we see.
    const cell_width: f32 = cell_width: {
        var cell_width: f32 = 0;
        var i: u8 = 32;
        while (i <= 126) : (i += 1) {
            const glyph = try font.addGlyph(alloc, i);
            if (glyph.advance_x > cell_width) {
                cell_width = @ceil(glyph.advance_x);
            }
        }

        break :cell_width cell_width;
    };

    // The cell height is the vertical height required to render underscore
    // '_' which should live at the bottom of a cell.
    const cell_height: f32 = cell_height: {
        // TODO(render): kitty does a calculation based on other font
        // metrics that we probably want to research more. For now, this is
        // fine.
        assert(font.ft_face != null);
        const glyph = font.getGlyph('_').?;
        var res: i32 = font.ft_face.*.ascender >> 6;
        res -= glyph.offset_y;
        res += @intCast(i32, glyph.height);
        break :cell_height @intToFloat(f32, res);
    };
    log.debug("cell dimensions w={d} h={d}", .{ cell_width, cell_height });

    // Create our shader
    const program = try gl.Program.createVF(
        @embedFile("../shaders/cell.v.glsl"),
        @embedFile("../shaders/cell.f.glsl"),
    );

    // Set our cell dimensions
    const pbind = try program.use();
    defer pbind.unbind();
    try program.setUniform("cell_size", @Vector(2, f32){ cell_width, cell_height });

    // Setup our VAO
    const vao = try gl.VertexArray.create();
    errdefer vao.destroy();
    try vao.bind();
    defer gl.VertexArray.unbind() catch null;

    // Element buffer (EBO)
    const ebo = try gl.Buffer.create();
    errdefer ebo.destroy();
    var ebobind = try ebo.bind(.ElementArrayBuffer);
    defer ebobind.unbind();
    try ebobind.setData([6]u8{
        0, 1, 3, // Top-left triangle
        1, 2, 3, // Bottom-right triangle
    }, .StaticDraw);

    // Vertex buffer (VBO)
    const vbo = try gl.Buffer.create();
    errdefer vbo.destroy();
    var vbobind = try vbo.bind(.ArrayBuffer);
    defer vbobind.unbind();
    var offset: usize = 0;
    try vbobind.attributeAdvanced(0, 2, gl.c.GL_UNSIGNED_SHORT, false, @sizeOf(GPUCell), offset);
    offset += 2 * @sizeOf(u16);
    try vbobind.attributeAdvanced(1, 2, gl.c.GL_UNSIGNED_INT, false, @sizeOf(GPUCell), offset);
    offset += 2 * @sizeOf(u32);
    try vbobind.attributeAdvanced(2, 2, gl.c.GL_UNSIGNED_INT, false, @sizeOf(GPUCell), offset);
    offset += 2 * @sizeOf(u32);
    try vbobind.attributeAdvanced(3, 2, gl.c.GL_INT, false, @sizeOf(GPUCell), offset);
    offset += 2 * @sizeOf(i32);
    try vbobind.attributeAdvanced(4, 4, gl.c.GL_UNSIGNED_BYTE, false, @sizeOf(GPUCell), offset);
    offset += 4 * @sizeOf(u8);
    try vbobind.attributeAdvanced(5, 4, gl.c.GL_UNSIGNED_BYTE, false, @sizeOf(GPUCell), offset);
    offset += 4 * @sizeOf(u8);
    try vbobind.attributeIAdvanced(6, 1, gl.c.GL_UNSIGNED_BYTE, @sizeOf(GPUCell), offset);
    try vbobind.enableAttribArray(0);
    try vbobind.enableAttribArray(1);
    try vbobind.enableAttribArray(2);
    try vbobind.enableAttribArray(3);
    try vbobind.enableAttribArray(4);
    try vbobind.enableAttribArray(5);
    try vbobind.enableAttribArray(6);
    try vbobind.attributeDivisor(0, 1);
    try vbobind.attributeDivisor(1, 1);
    try vbobind.attributeDivisor(2, 1);
    try vbobind.attributeDivisor(3, 1);
    try vbobind.attributeDivisor(4, 1);
    try vbobind.attributeDivisor(5, 1);
    try vbobind.attributeDivisor(6, 1);

    // Build our texture
    const tex = try gl.Texture.create();
    errdefer tex.destroy();
    const texbind = try tex.bind(.@"2D");
    try texbind.parameter(.WrapS, gl.c.GL_CLAMP_TO_EDGE);
    try texbind.parameter(.WrapT, gl.c.GL_CLAMP_TO_EDGE);
    try texbind.parameter(.MinFilter, gl.c.GL_LINEAR);
    try texbind.parameter(.MagFilter, gl.c.GL_LINEAR);
    try texbind.image2D(
        0,
        .Red,
        @intCast(c_int, atlas.size),
        @intCast(c_int, atlas.size),
        0,
        .Red,
        .UnsignedByte,
        atlas.data.ptr,
    );

    return Grid{
        .alloc = alloc,
        .cells = .{},
        .cell_size = .{ .width = cell_width, .height = cell_height },
        .size = .{ .rows = 0, .columns = 0 },
        .program = program,
        .vao = vao,
        .ebo = ebo,
        .vbo = vbo,
        .texture = tex,
        .font_atlas = font,
    };
}

pub fn deinit(self: *Grid) void {
    self.font_atlas.atlas.deinit(self.alloc);
    self.font_atlas.deinit(self.alloc);
    self.texture.destroy();
    self.vbo.destroy();
    self.ebo.destroy();
    self.vao.destroy();
    self.program.destroy();
    self.cells.deinit(self.alloc);
    self.* = undefined;
}

/// TODO: remove, this is for testing
pub fn demoCells(self: *Grid) !void {
    self.cells.clearRetainingCapacity();
    try self.cells.ensureUnusedCapacity(self.alloc, self.size.columns * self.size.rows);

    var row: u32 = 0;
    while (row < self.size.rows) : (row += 1) {
        var col: u32 = 0;
        while (col < self.size.columns) : (col += 1) {
            self.cells.appendAssumeCapacity(.{
                .grid_col = @intCast(u16, col),
                .grid_row = @intCast(u16, row),
                .bg_r = @intCast(u8, @mod(col * row, 255)),
                .bg_g = @intCast(u8, @mod(col, 255)),
                .bg_b = @intCast(u8, 255 - @mod(col, 255)),
                .bg_a = 255,
            });
        }
    }
}

/// updateCells updates our GPU cells from the current terminal view.
/// The updated cells will take effect on the next render.
pub fn updateCells(self: *Grid, term: Terminal) !void {
    // For now, we just ensure that we have enough cells for all the lines
    // we have plus a full width. This is very likely too much but its
    // the probably close enough while guaranteeing no more allocations.
    self.cells.clearRetainingCapacity();
    try self.cells.ensureTotalCapacity(
        self.alloc,
        term.screen.items.len * term.cols,
    );

    // Build each cell
    for (term.screen.items) |line, y| {
        for (line.items) |cell, x| {
            // It can be zero if the cell is empty
            if (cell.empty()) continue;

            // Get our glyph
            // TODO: if we add a glyph, I think we need to rerender the texture.
            const glyph = try self.font_atlas.addGlyph(self.alloc, cell.char);

            // TODO: for background colors, add another cell with mode = 1
            self.cells.appendAssumeCapacity(.{
                .grid_col = @intCast(u16, x),
                .grid_row = @intCast(u16, y),
                .glyph_x = glyph.atlas_x,
                .glyph_y = glyph.atlas_y,
                .glyph_width = glyph.width,
                .glyph_height = glyph.height,
                .glyph_offset_x = glyph.offset_x,
                .glyph_offset_y = glyph.offset_y,
                .fg_r = 0xFF,
                .fg_g = 0xA5,
                .fg_b = 0,
                .fg_a = 255,
                .bg_r = 0x0,
                .bg_g = 0xA5,
                .bg_b = 0,
                .bg_a = 0,
                .mode = 2,
            });
        }
    }

    // Draw the cursor
    self.cells.appendAssumeCapacity(.{
        .grid_col = @intCast(u16, term.cursor.x),
        .grid_row = @intCast(u16, term.cursor.y),
        .fg_r = 0,
        .fg_g = 0,
        .fg_b = 0,
        .fg_a = 0,
        .bg_r = 0xFF,
        .bg_g = 0xFF,
        .bg_b = 0xFF,
        .bg_a = 255,
        .mode = 1,
    });
}

/// Set the screen size for rendering. This will update the projection
/// used for the shader so that the scaling of the grid is correct.
pub fn setScreenSize(self: *Grid, dim: ScreenSize) !void {
    // Create a 2D orthographic projection matrix with the full width/height.
    var projection: gb.gbMat4 = undefined;
    gb.gb_mat4_ortho2d(
        &projection,
        0,
        @intToFloat(f32, dim.width),
        @intToFloat(f32, dim.height),
        0,
    );

    // Update the projection uniform within our shader
    const bind = try self.program.use();
    defer bind.unbind();
    try self.program.setUniform("projection", projection);

    // Recalculate the rows/columns.
    self.size.update(dim, self.cell_size);

    log.debug("screen size screen={} grid={}", .{ dim, self.size });
}

pub fn render(self: Grid) !void {
    // If we have no cells to render, then we render nothing.
    if (self.cells.items.len == 0) return;

    const pbind = try self.program.use();
    defer pbind.unbind();

    // Setup our VAO
    try self.vao.bind();
    defer gl.VertexArray.unbind() catch null;

    // Bind EBO
    var ebobind = try self.ebo.bind(.ElementArrayBuffer);
    defer ebobind.unbind();

    // Bind VBO and set data
    var binding = try self.vbo.bind(.ArrayBuffer);
    defer binding.unbind();
    try binding.setData(self.cells.items, .StaticDraw);

    // Bind our texture
    try gl.Texture.active(gl.c.GL_TEXTURE0);
    var texbind = try self.texture.bind(.@"2D");
    defer texbind.unbind();

    try gl.drawElementsInstanced(
        gl.c.GL_TRIANGLES,
        6,
        gl.c.GL_UNSIGNED_BYTE,
        self.cells.items.len,
    );
}

/// The dimensions of a single "cell" in the terminal grid.
///
/// The dimensions are dependent on the current loaded set of font glyphs.
/// We calculate the width based on the widest character and the height based
/// on the height requirement for an underscore (the "lowest" -- visually --
/// character).
///
/// The units for the width and height are in world space. They have to
/// be normalized using the screen projection.
///
/// TODO(mitchellh): we should recalculate cell dimensions when new glyphs
/// are loaded.
const CellSize = struct {
    width: f32,
    height: f32,
};

/// The dimensions of the screen that the grid is rendered to. This is the
/// terminal screen, so it is likely a subset of the window size. The dimensions
/// should be in pixels.
const ScreenSize = struct {
    width: u32,
    height: u32,
};

/// The dimensions of the grid itself, in rows/columns units.
const GridSize = struct {
    const Unit = u32;

    columns: Unit = 0,
    rows: Unit = 0,

    /// Update the columns/rows for the grid based on the given screen and
    /// cell size.
    fn update(self: *GridSize, screen: ScreenSize, cell: CellSize) void {
        self.columns = @floatToInt(Unit, @intToFloat(f32, screen.width) / cell.width);
        self.rows = @floatToInt(Unit, @intToFloat(f32, screen.height) / cell.height);
    }
};

test "GridSize update exact" {
    var grid: GridSize = .{};
    grid.update(.{
        .width = 100,
        .height = 40,
    }, .{
        .width = 5,
        .height = 10,
    });

    try testing.expectEqual(@as(GridSize.Unit, 20), grid.columns);
    try testing.expectEqual(@as(GridSize.Unit, 4), grid.rows);
}

test "GridSize update rounding" {
    var grid: GridSize = .{};
    grid.update(.{
        .width = 20,
        .height = 40,
    }, .{
        .width = 6,
        .height = 15,
    });

    try testing.expectEqual(@as(GridSize.Unit, 3), grid.columns);
    try testing.expectEqual(@as(GridSize.Unit, 2), grid.rows);
}

const face_ttf = @embedFile("../fonts/FiraCode-Regular.ttf");
