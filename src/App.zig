//! App is the primary GUI application for ghostty. This builds the window,
//! sets up the renderer, etc. The primary run loop is started by calling
//! the "run" function.
const App = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;
const glfw = @import("glfw");
const gl = @import("opengl.zig");
const TextRenderer = @import("TextRenderer.zig");
const Grid = @import("Grid.zig");

const log = std.log;

alloc: Allocator,

window: glfw.Window,

text: TextRenderer,
grid: Grid,

/// Initialize the main app instance. This creates the main window, sets
/// up the renderer state, compiles the shaders, etc. This is the primary
/// "startup" logic.
pub fn init(alloc: Allocator) !App {
    // Create our window
    const window = try glfw.Window.create(640, 480, "ghostty", null, null, .{
        .context_version_major = 3,
        .context_version_minor = 3,
        .opengl_profile = .opengl_core_profile,
        .opengl_forward_compat = true,
    });
    errdefer window.destroy();

    // Setup OpenGL
    // NOTE(mitchellh): we probably want to extract this to a dedicated
    // renderer at some point.
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

    // Setup our text renderer
    var texter = try TextRenderer.init(alloc);
    errdefer texter.deinit(alloc);

    var grid = try Grid.init(alloc);
    try grid.setScreenSize(.{ .width = 3000, .height = 1666 });

    window.setSizeCallback((struct {
        fn callback(_: glfw.Window, width: i32, height: i32) void {
            log.info("set viewport {} {}", .{ width, height });
            try gl.viewport(0, 0, width, height);
        }
    }).callback);

    return App{
        .alloc = alloc,
        .window = window,
        .text = texter,
        .grid = grid,
    };
}

pub fn deinit(self: *App) void {
    self.text.deinit(self.alloc);
    self.window.destroy();
    self.* = undefined;
}

pub fn run(self: App) !void {
    while (!self.window.shouldClose()) {
        // Setup basic OpenGL settings
        gl.clearColor(0.2, 0.3, 0.3, 1.0);
        gl.clear(gl.c.GL_COLOR_BUFFER_BIT);

        try self.grid.render();
        //try self.text.render("sh $ /bin/bash -c \"echo hello\"", 25.0, 25.0, .{ 0.5, 0.8, 0.2 });

        try self.window.swapBuffers();
        try glfw.waitEvents();
    }
}

const vs_source = @embedFile("../shaders/shape.v.glsl");
const fs_source = @embedFile("../shaders/shape.f.glsl");
