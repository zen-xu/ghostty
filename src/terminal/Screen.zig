const Screen = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;
const color = @import("color.zig");

/// A line is a set of cells.
pub const Line = []Cell;

/// Cell is a single cell within the screen.
pub const Cell = struct {
    /// Each cell contains exactly one character. The character is UTF-32
    /// encoded (just the Unicode codepoint).
    char: u32,

    /// Foreground and background color. null means to use the default.
    fg: ?color.RGB = null,
    bg: ?color.RGB = null,

    /// True if the cell should be skipped for drawing
    pub fn empty(self: Cell) bool {
        return self.char == 0;
    }
};

pub const LineIterator = struct {
    screen: *const Screen,
    index: usize,

    pub fn next(self: *LineIterator) ?Line {
        if (self.index >= self.screen.lines) return null;

        // Get the index of the first byte of the the line at index.
        const idx = self.screen.lineIndex(self.index) * self.screen.cols;

        // The storage is sliced to return exactly the number of columns.
        const line = self.screen.storage[idx .. idx + self.screen.cols];

        self.index += 1;
        return line;
    }
};

/// The full list of lines, including any scrollback.
storage: []Cell,

/// The first visible line.
zero: usize,

/// The number of lines and columns in the visible space.
lines: usize,
cols: usize,

/// Initialize a new screen.
pub fn init(alloc: Allocator, lines: usize, cols: usize) !Screen {
    // Allocate enough storage to cover every line and column in the visible
    // area. This wastes some up front memory but saves allocations later.
    const buf = try alloc.alloc(Cell, lines * cols);
    std.mem.set(Cell, buf, .{ .char = 0 });

    return Screen{
        .storage = buf,
        .zero = 0,
        .lines = lines,
        .cols = cols,
    };
}

pub fn deinit(self: *Screen, alloc: Allocator) void {
    alloc.free(self.storage);
    self.* = undefined;
}

/// Returns an iterator that can be used to iterate over all of the lines
/// from index zero.
pub fn lineIterator(self: *const Screen) LineIterator {
    return .{ .screen = self, .index = 0 };
}

/// Returns the index for the given line (0-indexed) into the underlying
/// storage array.
pub fn lineIndex(self: Screen, line: usize) usize {
    const idx = self.zero + line;
    if (idx < self.storage.len) return idx;
    return idx - self.storage.len;
}

/// Turns the screen into a string.
fn testString(self: Screen, alloc: Allocator) ![]const u8 {
    const buf = try alloc.alloc(u8, self.storage.len + self.lines);
    var i: usize = 0;
    var lines = self.lineIterator();
    for (lines.next()) |line, y| {
        if (y > 0) {
            buf[i] = '\n';
            i += 1;
        }

        for (line) |cell| {
            // Turn NUL into space.
            const char = if (cell.char == 0) 0x20 else cell.char;
            i += try std.unicode.utf8Encode(@intCast(u21, char), buf[i..]);
        }
    }

    return buf[0..i];
}

test "Screen" {
    const testing = std.testing;
    const alloc = testing.allocator;

    var s = try init(alloc, 5, 10);
    defer s.deinit(alloc);

    var i: usize = 0;
    var iter = s.lineIterator();
    while (iter.next() != null) i += 1;

    try testing.expectEqual(@as(usize, 5), i);
}
