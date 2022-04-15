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
const Window = @import("Window.zig");

const log = std.log;

alloc: Allocator,

window: glfw.Window,

text: TextRenderer,
grid: Grid,

/// Initialize the main app instance. This creates the main window, sets
/// up the renderer state, compiles the shaders, etc. This is the primary
/// "startup" logic.
pub fn init(alloc: Allocator) !App {
    // Create the window
    const window = try Window.create(alloc);

    return App{
        .window = window,
    };
}

pub fn deinit(self: *App) void {
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
