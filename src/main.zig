const std = @import("std");
const glfw = @import("glfw");
const gl = @import("opengl.zig");
const stb = @import("stb.zig");
const fonts = @import("fonts.zig");

const App = @import("App.zig");

pub fn main() !void {
    // List our fonts
    try glfw.init(.{});
    defer glfw.terminate();

    // Run our app
    var app = try App.init();
    defer app.deinit();
    try app.run();
}
