const std = @import("std");
const dawn = @import("dawn");
const glfw = @import("glfw");
const gpu = @import("gpu");

const setup = @import("setup.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var allocator = gpa.allocator();

    const s = try setup.setup(allocator);
    defer glfw.terminate();

    // Wait for the user to close the window.
    while (!s.window.shouldClose()) {
        try glfw.pollEvents();
    }
}
