//! Window represents a single OS window.
//!
//! NOTE(multi-window): This may be premature, but this abstraction is here
//! to pave the way One Day(tm) for multi-window support. At the time of
//! writing, we support exactly one window.
const Window = @This();

const std = @import("std");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;
const Grid = @import("Grid.zig");
const glfw = @import("glfw");
const gl = @import("opengl.zig");

const log = std.log.scoped(.window);

/// The glfw window handle.
window: glfw.Window,

/// The terminal grid attached to this window.
grid: Grid,

/// Create a new window. This allocates and returns a pointer because we
/// need a stable pointer for user data callbacks. Therefore, a stack-only
/// initialization is not currently possible.
pub fn create(alloc: Allocator) !*Window {
    var self = try alloc.create(Window);
    errdefer alloc.destroy(self);

    // Create our window
    const window = try glfw.Window.create(640, 480, "ghostty", null, null, .{
        .context_version_major = 3,
        .context_version_minor = 3,
        .opengl_profile = .opengl_core_profile,
        .opengl_forward_compat = true,
    });
    errdefer window.destroy();

    // NOTE(multi-window): We'll need to extract all the below into a
    // dedicated renderer and consider the multi-threading (or at the very
    // least: multi-OpenGL-context) implications. Since we don't support
    // multiple windows right now, we just do it all here.

    // Setup OpenGL
    try glfw.makeContextCurrent(window);
    try glfw.swapInterval(1);

    // Load OpenGL bindings
    const version = try gl.glad.load(glfw.getProcAddress);
    log.info("loaded OpenGL {}.{}", .{
        gl.glad.versionMajor(version),
        gl.glad.versionMinor(version),
    });

    // Culling, probably not necessary. We have to change the winding
    // order since our 0,0 is top-left.
    gl.c.glEnable(gl.c.GL_CULL_FACE);
    gl.c.glFrontFace(gl.c.GL_CW);

    // Blending for text
    gl.c.glEnable(gl.c.GL_BLEND);
    gl.c.glBlendFunc(gl.c.GL_SRC_ALPHA, gl.c.GL_ONE_MINUS_SRC_ALPHA);

    // Create our terminal grid with a bogus initial size.
    var grid = try Grid.init(alloc);
    try grid.setScreenSize(.{ .width = 640, .height = 480 });

    self.* = .{
        .window = window,
        .grid = grid,
    };

    // Setup our callbacks and user data
    window.setUserPointer(self);
    window.setSizeCallback(sizeCallback);

    return self;
}

pub fn destroy(self: *Window, alloc: Allocator) void {
    self.grid.deinit();
    self.window.destroy();
    alloc.destroy(self);
}

pub fn run(self: Window) !void {
    while (!self.window.shouldClose()) {
        // Set our background
        gl.clearColor(0.2, 0.3, 0.3, 1.0);
        gl.clear(gl.c.GL_COLOR_BUFFER_BIT);

        // Render the grid
        try self.grid.render();

        // Swap
        try self.window.swapBuffers();
        try glfw.waitEvents();
    }
}

fn sizeCallback(window: glfw.Window, width: i32, height: i32) void {
    // glfw gives us signed integers, but negative width/height is n
    // non-sensical so we use unsigned throughout, so assert.
    assert(width >= 0);
    assert(height >= 0);

    // Update our grid so that the projections on render are correct.
    const win = window.getUserPointer(Window) orelse return;
    win.grid.setScreenSize(.{
        .width = @intCast(u32, width),
        .height = @intCast(u32, height),
    }) catch |err| log.err("error updating grid screen size err={}", .{err});

    // Update our viewport for this context to be the entire window
    gl.viewport(0, 0, width, height) catch |err|
        log.err("error updating OpenGL viewport err={}", .{err});
}
