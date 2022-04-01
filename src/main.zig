const std = @import("std");
const c = @import("c.zig");

pub fn main() !void {
    // Set the window as resizable. This is particularly important for
    // tiling window managers such as i3 since if they are not resizable they
    // usually default to floating and we do not want to float by default!
    c.SetConfigFlags(c.FLAG_WINDOW_RESIZABLE | c.FLAG_VSYNC_HINT);

    // Create our window
    c.InitWindow(640, 480, "ghostty");
    c.SetTargetFPS(60);
    defer c.CloseWindow();

    // Draw
    while (!c.WindowShouldClose()) {
        c.BeginDrawing();
        c.ClearBackground(c.BLACK);
        c.EndDrawing();
    }
}
