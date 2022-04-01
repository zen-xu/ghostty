const std = @import("std");
const glfw = @import("glfw");
const c = @cImport({
    @cInclude("epoxy/gl.h");
});

pub fn main() !void {
    try glfw.init(.{});
    defer glfw.terminate();

    // Create our window
    const window = try glfw.Window.create(640, 480, "ghostty", null, null, .{});
    defer window.destroy();

    // Setup OpenGL
    try glfw.makeContextCurrent(window);
    try glfw.swapInterval(1);

    // Setup basic OpenGL settings
    c.glClearColor(0.0, 0.0, 0.0, 0.0);

    // Wait for the user to close the window.
    while (!window.shouldClose()) {
        const pos = try window.getCursorPos();
        std.log.info("CURSOR: {}", .{pos});

        try window.swapBuffers();
        try glfw.waitEvents();
    }
}
