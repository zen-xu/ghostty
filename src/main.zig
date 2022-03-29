const std = @import("std");
const glfw = @import("glfw/glfw.zig");

pub fn main() !void {
    // Iniialize GLFW
    if (glfw.c.glfwInit() != glfw.c.GLFW_TRUE) return glfw.errors.getError();
    defer glfw.c.glfwTerminate();

    // Create our initial window
    const window = glfw.c.glfwCreateWindow(640, 480, "My Title", null, null) orelse
        return glfw.errors.getError();
    defer glfw.c.glfwDestroyWindow(window);

    // Setup OpenGL
    glfw.c.glfwMakeContextCurrent(window);

    while (glfw.c.glfwWindowShouldClose(window) == glfw.c.GLFW_FALSE) {
        glfw.c.glfwWaitEvents();
    }
}
