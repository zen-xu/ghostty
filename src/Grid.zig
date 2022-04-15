//! Represents a single terminal grid.
const Grid = @This();

const std = @import("std");
const assert = std.debug.assert;
const testing = std.testing;
const Allocator = std.mem.Allocator;
const Atlas = @import("Atlas.zig");
const FontAtlas = @import("FontAtlas.zig");
const gl = @import("opengl.zig");
const gb = @import("gb_math.zig");

const log = std.log.scoped(.grid);

alloc: std.mem.Allocator,

/// Current dimensions for this grid.
size: GridSize,

/// Current cell dimensions for this grid.
cell_size: CellSize,

/// Shader program for cell rendering.
program: gl.Program,

pub fn init(alloc: Allocator) !Grid {
    // Initialize our font atlas. We will initially populate the
    // font atlas with all the visible ASCII characters since they are common.
    var atlas = try Atlas.init(alloc, 512);
    defer atlas.deinit(alloc);
    var font = try FontAtlas.init(atlas);
    defer font.deinit(alloc);
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

    return Grid{
        .alloc = alloc,
        .cell_size = .{ .width = cell_width, .height = cell_height },
        .size = .{ .rows = 0, .columns = 0 },
        .program = program,
    };
}

pub fn deinit(self: *Grid) void {
    self.program.destroy();
    self.* = undefined;
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
    const pbind = try self.program.use();
    defer pbind.unbind();

    // Setup our VAO
    const vao = try gl.VertexArray.create();
    defer vao.destroy();
    try vao.bind();

    // Element buffer (EBO)
    const ebo = try gl.Buffer.create();
    defer ebo.destroy();
    var ebobinding = try ebo.bind(.ElementArrayBuffer);
    defer ebobinding.unbind();
    try ebobinding.setData([6]u32{
        0, 1, 3,
        1, 2, 3,
    }, .StaticDraw);

    // Build our data
    var vertices: std.ArrayListUnmanaged([6]f32) = .{};
    try vertices.ensureUnusedCapacity(self.alloc, self.size.columns * self.size.rows);
    defer vertices.deinit(self.alloc);
    var row: u32 = 0;
    while (row < self.size.rows) : (row += 1) {
        var col: u32 = 0;
        while (col < self.size.columns) : (col += 1) {
            const rowf = @intToFloat(f32, row);
            const colf = @intToFloat(f32, col);
            const hue = ((colf * @intToFloat(f32, self.size.rows)) + rowf) / @intToFloat(f32, self.size.columns * self.size.rows);
            vertices.appendAssumeCapacity([6]f32{
                colf,
                rowf,
                hue,
                0.7,
                0.8,
                1.0,
            });
        }
    }

    // Vertex buffer (VBO)
    const vbo = try gl.Buffer.create();
    defer vbo.destroy();
    var binding = try vbo.bind(.ArrayBuffer);
    defer binding.unbind();
    try binding.setData(vertices.items, .StaticDraw);
    try binding.attribute(0, 2, [6]f32, 0);
    try binding.attribute(1, 4, [6]f32, 2);
    try binding.attributeDivisor(0, 1);
    try binding.attributeDivisor(1, 1);

    try gl.drawElementsInstanced(
        gl.c.GL_TRIANGLES,
        6,
        gl.c.GL_UNSIGNED_INT,
        vertices.items.len,
    );
    try gl.VertexArray.unbind();
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
