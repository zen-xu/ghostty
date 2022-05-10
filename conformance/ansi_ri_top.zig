//! Reverse Index (RI) - ESC M at the top of the screen.
const std = @import("std");

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();
    try stdout.print("\x1B[H", .{}); // move to top-left
    try stdout.print("\x1B[J", .{}); // clear screen
    try stdout.print("\x1BM", .{});
    try stdout.print("D\n", .{});
}
