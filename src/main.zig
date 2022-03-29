const std = @import("std");
const c = @import("glfw/c.zig");

pub fn main() !void {
    if (c.glfwInit() != c.GLFW_TRUE) return error.GlfwInitFailed;
    defer c.glfwTerminate();
}
