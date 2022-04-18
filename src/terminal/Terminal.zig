//! The primary terminal emulation structure. This represents a single
//! "terminal" containing a grid of characters and exposes various operations
//! on that grid. This also maintains the scrollback buffer.
const Terminal = @This();

const std = @import("std");

/// Screen is the current screen state.
screen: Screen,

/// Cursor position.
cursor: Cursor,

/// The size of the terminal.
rows: usize,
cols: usize,

/// Screen represents a presentable terminal screen made up of lines and cells.
const Screen = std.ArrayListUnmanaged(Line);
const Line = std.ArrayListUnmanaged(Cell);

/// Cell is a single cell within the terminal.
const Cell = struct {
    /// Each cell contains exactly one character.
    char: u32,

    // TODO(mitchellh): this is where we'll track fg/bg and other attrs.
};

/// Cursor represents the cursor state.
const Cursor = struct {
    x: usize,
    y: usize,
};

/// Initialize a new terminal.
pub fn init(cols: usize, rows: usize) Terminal {
    return .{
        .cols = cols,
        .rows = rows,
        .screen = .{},
        .cursor = .{ .x = 0, .y = 0 },
    };
}

test {
    _ = @import("Parser.zig");
}
