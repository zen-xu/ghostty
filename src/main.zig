const std = @import("std");
const c = @import("c.zig");

pub fn main() !void {
    c.InitWindow(640, 480, "ghostty");
    c.SetTargetFPS(60);
    defer c.CloseWindow();

    while (!c.WindowShouldClose()) {}
}
