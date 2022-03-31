const std = @import("std");
const glfw = @import("glfw");

pub fn main() !void {
    try glfw.init(.{});
    defer glfw.terminate();

    // Create our window
    const window = try glfw.Window.create(640, 480, "ghostty", null, null, .{});
    defer window.destroy();

    // Wait for the user to close the window.
    while (!window.shouldClose()) {
        try glfw.pollEvents();
    }
}
