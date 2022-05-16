//! The primary terminal emulation structure. This represents a single
//!
//! "terminal" containing a grid of characters and exposes various operations
//! on that grid. This also maintains the scrollback buffer.
const Terminal = @This();

const std = @import("std");
const builtin = @import("builtin");
const testing = std.testing;
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;
const ansi = @import("ansi.zig");
const csi = @import("csi.zig");
const sgr = @import("sgr.zig");
const Tabstops = @import("Tabstops.zig");
const trace = @import("../tracy/tracy.zig").trace;

const log = std.log.scoped(.terminal);

/// Screen is the current screen state.
screen: Screen,

/// Cursor position.
cursor: Cursor,

/// Where the tabstops are.
tabstops: Tabstops,

/// The size of the terminal.
rows: usize,
cols: usize,

/// The current scrolling region.
scrolling_region: ScrollingRegion,

/// Modes
// TODO: turn into a bitset probably
mode_origin: bool = false,

/// Screen represents a presentable terminal screen made up of lines and cells.
const Screen = std.ArrayListUnmanaged(Line);
const Line = std.ArrayListUnmanaged(Cell);

/// Scrolling region is the area of the screen designated where scrolling
/// occurs. Wen scrolling the screen, only this viewport is scrolled.
const ScrollingRegion = struct {
    // Precondition: top < bottom
    top: usize,
    bottom: usize,
};

/// Cell is a single cell within the terminal.
const Cell = struct {
    /// Each cell contains exactly one character. The character is UTF-8 encoded.
    char: u32,

    /// Foreground and background color. null means to use the default.
    fg: ?RGB = null,
    bg: ?RGB = null,

    /// True if the cell should be skipped for drawing
    pub fn empty(self: Cell) bool {
        return self.char == 0;
    }
};

/// Cursor represents the cursor state.
const Cursor = struct {
    // x, y where the cursor currently exists (0-indexed).
    x: usize,
    y: usize,

    // pen is the current cell styling to apply to new cells.
    pen: Cell = .{ .char = 0 },
};

pub const RGB = struct {
    r: u8,
    g: u8,
    b: u8,
};

/// Initialize a new terminal.
pub fn init(alloc: Allocator, cols: usize, rows: usize) !Terminal {
    return Terminal{
        .cols = cols,
        .rows = rows,
        .screen = .{},
        .cursor = .{ .x = 0, .y = 0 },
        .tabstops = try Tabstops.init(alloc, cols, 8),
        .scrolling_region = .{
            .top = 0,
            .bottom = rows - 1,
        },
    };
}

pub fn deinit(self: *Terminal, alloc: Allocator) void {
    self.tabstops.deinit(alloc);
    for (self.screen.items) |*line| line.deinit(alloc);
    self.screen.deinit(alloc);
    self.* = undefined;
}

/// Resize the underlying terminal.
pub fn resize(self: *Terminal, alloc: Allocator, cols: usize, rows: usize) !void {
    // TODO: test, wrapping, etc.

    // Resize our tabstops
    // TODO: use resize, but it doesn't set new tabstops
    if (self.cols != cols) {
        self.tabstops.deinit(alloc);
        self.tabstops = try Tabstops.init(alloc, cols, 8);
    }

    // If we're making the screen smaller, dealloc the unused items.
    // TODO: we probably want to wrap in the future.
    if (rows < self.rows and self.screen.items.len > rows) {
        for (self.screen.items[rows..self.screen.items.len]) |*line|
            line.deinit(alloc);
        self.screen.shrinkRetainingCapacity(rows);
    }
    if (cols < self.cols) {
        for (self.screen.items) |*line| {
            if (line.items.len < cols) continue;
            line.shrinkRetainingCapacity(cols);
        }
    }

    // Set our size
    self.cols = cols;
    self.rows = rows;

    // Reset the scrolling region
    self.scrolling_region = .{
        .top = 0,
        .bottom = rows - 1,
    };
}

/// Return the current string value of the terminal. Newlines are
/// encoded as "\n". This omits any formatting such as fg/bg.
///
/// The caller must free the string.
pub fn plainString(self: Terminal, alloc: Allocator) ![]const u8 {
    // Create a buffer that has the number of lines we have times the maximum
    // width it could possibly be. In all likelihood we aren't using the full
    // width (of at least the last line) but the error margine here won't be
    // much.
    const buffer = try alloc.alloc(u8, self.screen.items.len * self.cols * 4);
    var i: usize = 0;
    for (self.screen.items) |line, y| {
        if (y > 0) {
            buffer[i] = '\n';
            i += 1;
        }

        for (line.items) |cell| {
            if (cell.char > 0) {
                i += try std.unicode.utf8Encode(@intCast(u21, cell.char), buffer[i..]);
            }
        }
    }

    return buffer[0..i];
}

/// TODO: test
pub fn setAttribute(self: *Terminal, attr: sgr.Attribute) !void {
    switch (attr) {
        .unset => {
            self.cursor.pen.fg = null;
            self.cursor.pen.bg = null;
        },

        .direct_color_fg => |rgb| {
            self.cursor.pen.fg = .{
                .r = rgb.r,
                .g = rgb.g,
                .b = rgb.b,
            };
        },

        .direct_color_bg => |rgb| {
            self.cursor.pen.bg = .{
                .r = rgb.r,
                .g = rgb.g,
                .b = rgb.b,
            };
        },

        else => return error.InvalidAttribute,
    }
}

pub fn print(self: *Terminal, alloc: Allocator, c: u21) !void {
    const tracy = trace(@src());
    defer tracy.end();

    // Build our cell
    const cell = try self.getOrPutCell(alloc, self.cursor.x, self.cursor.y);
    cell.* = self.cursor.pen;
    cell.char = @intCast(u32, c);

    // Move the cursor
    self.cursor.x += 1;

    // TODO: wrap
    if (self.cursor.x == self.cols) {
        self.cursor.x -= 1;
    }
}

// TODO: test
pub fn reverseIndex(self: *Terminal, alloc: Allocator) !void {
    if (self.cursor.y == 0)
        try self.scrollDown(alloc)
    else
        self.cursor.y -|= 1;
}

// Set Cursor Position. Move cursor to the position indicated
// by row and column (1-indexed). If column is 0, it is adjusted to 1.
// If column is greater than the right-most column it is adjusted to
// the right-most column. If row is 0, it is adjusted to 1. If row is
// greater than the bottom-most row it is adjusted to the bottom-most
// row.
pub fn setCursorPos(self: *Terminal, row: usize, col: usize) void {
    self.cursor.x = @minimum(self.cols, col) -| 1;
    self.cursor.y = @minimum(self.rows, row) -| 1;
}

/// Erase the display.
/// TODO: test
pub fn eraseDisplay(
    self: *Terminal,
    alloc: Allocator,
    mode: csi.EraseDisplay,
) !void {
    switch (mode) {
        .complete => {
            var y: usize = 0;
            while (y < self.rows) : (y += 1) {
                var x: usize = 0;
                while (x < self.cols) : (x += 1) {
                    const cell = try self.getOrPutCell(alloc, x, y);
                    cell.* = self.cursor.pen;
                    cell.char = 0;
                }
            }
        },

        .below => {
            // All lines to the right (including the cursor)
            var x: usize = self.cursor.x;
            while (x < self.cols) : (x += 1) {
                const cell = try self.getOrPutCell(alloc, x, self.cursor.y);
                cell.* = self.cursor.pen;
                cell.char = 0;
            }

            // All lines below
            var y: usize = self.cursor.y + 1;
            while (y < self.rows) : (y += 1) {
                x = 0;
                while (x < self.cols) : (x += 1) {
                    const cell = try self.getOrPutCell(alloc, x, y);
                    cell.* = self.cursor.pen;
                    cell.char = 0;
                }
            }
        },

        else => {
            log.err("unimplemented display mode: {}", .{mode});
            @panic("unimplemented");
        },
    }
}

/// Erase the line.
/// TODO: test
pub fn eraseLine(
    self: *Terminal,
    alloc: Allocator,
    mode: csi.EraseLine,
) !void {
    switch (mode) {
        .right => {
            var x: usize = self.cursor.x;
            while (x < self.cols) : (x += 1) {
                const cell = try self.getOrPutCell(alloc, x, self.cursor.y);
                cell.* = self.cursor.pen;
                cell.char = 0;
            }
        },

        .left => {
            var x: usize = self.cursor.x;
            while (x >= 0) : (x -= 1) {
                const cell = try self.getOrPutCell(alloc, x, self.cursor.y);
                cell.* = self.cursor.pen;
                cell.char = 0;
            }
        },

        else => {
            log.err("unimplemented erase line mode: {}", .{mode});
            @panic("unimplemented");
        },
    }
}

/// Removes amount characters from the current cursor position to the right.
/// The remaining characters are shifted to the left and space from the right
/// margin is filled with spaces.
///
/// If amount is greater than the remaining number of characters in the
/// scrolling region, it is adjusted down.
///
/// Does not change the cursor position.
///
/// TODO: test
pub fn deleteChars(self: *Terminal, count: usize) !void {
    var line = &self.screen.items[self.cursor.y];

    // Our last index is at most the end of the number of chars we have
    // in the current line.
    const end = @minimum(line.items.len, self.cols - count);

    // Do nothing if we have no values.
    if (self.cursor.x >= line.items.len) return;

    // Shift
    var i: usize = self.cursor.x;
    while (i < end) : (i += 1) {
        const j = i + count;
        if (j < line.items.len) {
            line.items[i] = line.items[j];
        } else {
            line.items[i].char = 0;
        }
    }
}

// TODO: test, docs
pub fn eraseChars(self: *Terminal, alloc: Allocator, count: usize) !void {
    // Our last index is at most the end of the number of chars we have
    // in the current line.
    const end = @minimum(self.cols, self.cursor.x + count);

    // Shift
    var x: usize = self.cursor.x;
    while (x < end) : (x += 1) {
        const cell = try self.getOrPutCell(alloc, x, self.cursor.y);
        cell.* = self.cursor.pen;
        cell.char = 0;
    }
}

/// Move the cursor right amount columns. If amount is greater than the
/// maximum move distance then it is internally adjusted to the maximum.
/// This sequence will not scroll the screen or scroll region. If amount is
/// 0, adjust it to 1.
/// TODO: test
pub fn cursorRight(self: *Terminal, count: usize) void {
    const tracy = trace(@src());
    defer tracy.end();

    self.cursor.x += count;
    if (self.cursor.x >= self.cols) {
        self.cursor.x = self.cols - 1;
    }
}

/// Move the cursor down amount lines. If amount is greater than the maximum
/// move distance then it is internally adjusted to the maximum. This sequence
/// will not scroll the screen or scroll region. If amount is 0, adjust it to 1.
// TODO: test
pub fn cursorDown(self: *Terminal, count: usize) void {
    const tracy = trace(@src());
    defer tracy.end();

    self.cursor.y += count;
    if (self.cursor.y >= self.rows) {
        self.cursor.y = self.rows - 1;
    }
}

/// Move the cursor up amount lines. If amount is greater than the maximum
/// move distance then it is internally adjusted to the maximum. If amount is
/// 0, adjust it to 1.
// TODO: test
pub fn cursorUp(self: *Terminal, count: usize) void {
    const tracy = trace(@src());
    defer tracy.end();

    self.cursor.y -|= count;
}

/// Backspace moves the cursor back a column (but not less than 0).
pub fn backspace(self: *Terminal) void {
    const tracy = trace(@src());
    defer tracy.end();

    self.cursor.x -|= 1;
}

/// Horizontal tab moves the cursor to the next tabstop, clearing
/// the screen to the left the tabstop.
pub fn horizontalTab(self: *Terminal, alloc: Allocator) !void {
    const tracy = trace(@src());
    defer tracy.end();

    while (self.cursor.x < self.cols) {
        // Clear
        try self.print(alloc, ' ');

        // If the last cursor position was a tabstop we return. We do
        // "last cursor position" because we want a space to be written
        // at the tabstop unless we're at the end (the while condition).
        if (self.tabstops.get(self.cursor.x - 1)) return;
    }
}

/// Carriage return moves the cursor to the first column.
pub fn carriageReturn(self: *Terminal) void {
    const tracy = trace(@src());
    defer tracy.end();

    self.cursor.x = 0;
}

/// Linefeed moves the cursor to the next line.
pub fn linefeed(self: *Terminal, alloc: Allocator) void {
    const tracy = trace(@src());
    defer tracy.end();

    // If we're at the end of the screen, scroll up. This is surprisingly
    // common because most terminals live with a full screen so we do this
    // check first.
    if (self.cursor.y == self.rows - 1) {
        self.scrollUp(alloc);
        return;
    }

    // Increase cursor by 1
    self.cursor.y += 1;
}

/// Insert amount lines at the current cursor row. The contents of the line
/// at the current cursor row and below (to the bottom-most line in the
/// scrolling region) are shifted down by amount lines. The contents of the
/// amount bottom-most lines in the scroll region are lost.
///
/// This unsets the pending wrap state without wrapping. If the current cursor
/// position is outside of the current scroll region it does nothing.
///
/// If amount is greater than the remaining number of lines in the scrolling
/// region it is adjusted down (still allowing for scrolling out every remaining
/// line in the scrolling region)
///
/// In left and right margin mode the margins are respected; lines are only
/// scrolled in the scroll region.
///
/// All cleared space is colored according to the current SGR state.
///
/// Moves the cursor to the left margin.
pub fn insertLines(self: *Terminal, alloc: Allocator, count: usize) !void {
    // Move the cursor to the left margin
    self.cursor.x = 0;

    // Remaining rows from our cursor
    const rem = self.scrolling_region.bottom - self.cursor.y + 1;

    // If count is greater than the amount of rows, adjust down.
    const adjusted_count = @minimum(count, rem);

    // The the top `scroll_amount` lines need to move to the bottom
    // scroll area. We may have nothing to scroll if we're clearing.
    const scroll_amount = rem - adjusted_count;
    var y: usize = self.scrolling_region.bottom;
    const top = y - scroll_amount;

    // Ensure we have the lines populated to the end
    _ = try self.getOrPutCell(alloc, 0, y);
    while (y > top) : (y -= 1) {
        self.screen.items[y].deinit(alloc);
        self.screen.items[y] = self.screen.items[y - adjusted_count];
        self.screen.items[y - adjusted_count] = .{};
    }

    // Insert count blank lines
    y = self.cursor.y;
    while (y < self.cursor.y + adjusted_count) : (y += 1) {
        var x: usize = 0;
        while (x < self.cols) : (x += 1) {
            const cell = try self.getOrPutCell(alloc, x, y);
            cell.* = self.cursor.pen;
            cell.char = 0;
        }
    }
}

/// Removes amount lines from the current cursor row down. The remaining lines
/// to the bottom margin are shifted up and space from the bottom margin up is
/// filled with empty lines.
///
/// If the current cursor position is outside of the current scroll region it
/// does nothing. If amount is greater than the remaining number of lines in the
/// scrolling region it is adjusted down.
///
/// In left and right margin mode the margins are respected; lines are only
/// scrolled in the scroll region.
///
/// If the cell movement splits a multi cell character that character cleared,
/// by replacing it by spaces, keeping its current attributes. All other
/// cleared space is colored according to the current SGR state.
///
/// Moves the cursor to the left margin.
pub fn deleteLines(self: *Terminal, alloc: Allocator, count: usize) void {
    // TODO: scroll region bounds

    // Move the cursor to the left margin
    self.cursor.x = 0;

    // Remaining number of lines in the scrolling region
    const rem = self.scrolling_region.bottom - self.cursor.y;

    // If the count is more than our remaining lines, we adjust down.
    const count2 = @minimum(count, rem);

    // Scroll up the count amount.
    var i: usize = 0;
    while (i < count2) : (i += 1) {
        self.scrollUpRegion(
            alloc,
            self.cursor.y,
            self.scrolling_region.bottom,
        );
    }
}

/// Scroll the text up by one row.
pub fn scrollUp(self: *Terminal, alloc: Allocator) void {
    const tracy = trace(@src());
    defer tracy.end();

    // TODO: this is horribly expensive. we need to optimize the screen repr

    // If we have no items, scrolling does nothing.
    if (self.screen.items.len == 0) return;

    // Clear the first line
    self.screen.items[0].deinit(alloc);

    var i: usize = 0;
    while (i < self.screen.items.len - 1) : (i += 1) {
        self.screen.items[i] = self.screen.items[i + 1];
    }
    self.screen.items.len -= 1;
}

/// Scroll the given region up.
///
/// Top and bottom are 0-indexed.
fn scrollUpRegion(
    self: *Terminal,
    alloc: Allocator,
    top: usize,
    bottom: usize,
) void {
    const tracy = trace(@src());
    defer tracy.end();

    // If we have no items, scrolling does nothing.
    if (self.screen.items.len <= top) return;

    // Clear the first line
    self.screen.items[top].deinit(alloc);

    // Only go to the end of the region OR the end of our lines.
    const end = @minimum(bottom, self.screen.items.len - 1);

    var i: usize = top;
    while (i < end) : (i += 1) {
        self.screen.items[i] = self.screen.items[i + 1];
    }

    // Blank our last line if we have space.
    if (i < self.screen.items.len) {
        self.screen.items[i] = .{};
    }
}

/// Scroll the text down by one row.
/// TODO: test
pub fn scrollDown(self: *Terminal, alloc: Allocator) !void {
    const tracy = trace(@src());
    defer tracy.end();

    // TODO: this is horribly expensive. we need to optimize the screen repr

    // We need space for one more row if we aren't at the max.
    if (self.screen.capacity < self.rows) {
        try self.screen.ensureTotalCapacity(alloc, self.screen.items.len + 1);
    }

    // Add one more item if we aren't at the max
    if (self.screen.items.len < self.rows) {
        self.screen.items.len += 1;
    } else {
        // We have the max, we need to deinitialize the last row because
        // we're going to overwrite it.
        self.screen.items[self.screen.items.len - 1].deinit(alloc);
    }

    // Shift everything down
    var i: usize = self.screen.items.len - 1;
    while (i > 0) : (i -= 1) {
        self.screen.items[i] = self.screen.items[i - 1];
    }

    // Clear this row
    self.screen.items[0] = .{};
}

/// Set Top and Bottom Margins If bottom is not specified, 0 or bigger than
/// the number of the bottom-most row, it is adjusted to the number of the
/// bottom most row.
///
/// If top < bottom set the top and bottom row of the scroll region according
/// to top and bottom and move the cursor to the top-left cell of the display
/// (when in cursor origin mode is set to the top-left cell of the scroll region).
///
/// Otherwise: Set the top and bottom row of the scroll region to the top-most
/// and bottom-most line of the screen.
///
/// Top and bottom are 1-indexed.
pub fn setScrollingRegion(self: *Terminal, top: usize, bottom: usize) void {
    var t = if (top == 0) 1 else top;
    var b = @minimum(bottom, self.rows);
    if (t >= b) {
        t = 1;
        b = self.rows;
    }

    self.scrolling_region = .{
        .top = t - 1,
        .bottom = b - 1,
    };

    self.setCursorPos(1, 1);
}

fn getOrPutCell(self: *Terminal, alloc: Allocator, x: usize, y: usize) !*Cell {
    const tracy = trace(@src());
    defer tracy.end();

    // If we don't have enough lines to get to y, then add it.
    if (self.screen.items.len < y + 1) {
        try self.screen.ensureTotalCapacity(alloc, y + 1);
        self.screen.appendNTimesAssumeCapacity(.{}, y + 1 - self.screen.items.len);
    }

    const line = &self.screen.items[y];
    if (line.items.len < x + 1) {
        try line.ensureTotalCapacity(alloc, x + 1);
        line.appendNTimesAssumeCapacity(undefined, x + 1 - line.items.len);
    }

    return &line.items[x];
}

test "Terminal: input with no control characters" {
    var t = try init(testing.allocator, 80, 80);
    defer t.deinit(testing.allocator);

    // Basic grid writing
    for ("hello") |c| try t.print(testing.allocator, c);
    try testing.expectEqual(@as(usize, 0), t.cursor.y);
    try testing.expectEqual(@as(usize, 5), t.cursor.x);
    {
        var str = try t.plainString(testing.allocator);
        defer testing.allocator.free(str);
        try testing.expectEqualStrings("hello", str);
    }
}

test "Terminal: linefeed and carriage return" {
    var t = try init(testing.allocator, 80, 80);
    defer t.deinit(testing.allocator);

    // Basic grid writing
    for ("hello") |c| try t.print(testing.allocator, c);
    t.carriageReturn();
    t.linefeed(testing.allocator);
    for ("world") |c| try t.print(testing.allocator, c);
    try testing.expectEqual(@as(usize, 1), t.cursor.y);
    try testing.expectEqual(@as(usize, 5), t.cursor.x);
    {
        var str = try t.plainString(testing.allocator);
        defer testing.allocator.free(str);
        try testing.expectEqualStrings("hello\nworld", str);
    }
}

test "Terminal: backspace" {
    const alloc = testing.allocator;
    var t = try init(testing.allocator, 80, 80);
    defer t.deinit(testing.allocator);

    // BS
    for ("hello") |c| try t.print(alloc, c);
    t.backspace();
    try t.print(alloc, 'y');
    try testing.expectEqual(@as(usize, 0), t.cursor.y);
    try testing.expectEqual(@as(usize, 5), t.cursor.x);
    {
        var str = try t.plainString(testing.allocator);
        defer testing.allocator.free(str);
        try testing.expectEqualStrings("helly", str);
    }
}

test "Terminal: horizontal tabs" {
    const alloc = testing.allocator;
    var t = try init(alloc, 80, 5);
    defer t.deinit(alloc);

    // HT
    try t.print(alloc, '1');
    try t.horizontalTab(alloc);
    try testing.expectEqual(@as(usize, 8), t.cursor.x);

    // HT
    try t.horizontalTab(alloc);
    try testing.expectEqual(@as(usize, 16), t.cursor.x);
}

test "Terminal: setCursorPosition" {
    var t = try init(testing.allocator, 80, 80);
    defer t.deinit(testing.allocator);

    try testing.expectEqual(@as(usize, 0), t.cursor.x);
    try testing.expectEqual(@as(usize, 0), t.cursor.y);

    // Setting it to 0 should keep it zero (1 based)
    t.setCursorPos(0, 0);
    try testing.expectEqual(@as(usize, 0), t.cursor.x);
    try testing.expectEqual(@as(usize, 0), t.cursor.y);

    // Should clamp to size
    t.setCursorPos(81, 81);
    try testing.expectEqual(@as(usize, 79), t.cursor.x);
    try testing.expectEqual(@as(usize, 79), t.cursor.y);
}

test "Terminal: setScrollingRegion" {
    var t = try init(testing.allocator, 80, 80);
    defer t.deinit(testing.allocator);

    // Initial value
    try testing.expectEqual(@as(usize, 0), t.scrolling_region.top);
    try testing.expectEqual(@as(usize, t.rows - 1), t.scrolling_region.bottom);

    // Move our cusor so we can verify we move it back
    t.setCursorPos(5, 5);
    t.setScrollingRegion(3, 7);

    // Cursor should move back to top-left
    try testing.expectEqual(@as(usize, 0), t.cursor.x);
    try testing.expectEqual(@as(usize, 0), t.cursor.y);

    // Scroll region is set
    try testing.expectEqual(@as(usize, 2), t.scrolling_region.top);
    try testing.expectEqual(@as(usize, 6), t.scrolling_region.bottom);

    // Scroll region invalid
    t.setScrollingRegion(7, 3);
    try testing.expectEqual(@as(usize, 0), t.scrolling_region.top);
    try testing.expectEqual(@as(usize, t.rows - 1), t.scrolling_region.bottom);
}

test "Terminal: setScrollingRegion" {
    const alloc = testing.allocator;
    var t = try init(alloc, 80, 80);
    defer t.deinit(alloc);

    // Initial value
    try t.print(alloc, 'A');
    t.carriageReturn();
    t.linefeed(alloc);
    try t.print(alloc, 'B');
    t.carriageReturn();
    t.linefeed(alloc);
    try t.print(alloc, 'C');
    t.carriageReturn();
    t.linefeed(alloc);
    try t.print(alloc, 'D');

    t.cursorUp(2);
    t.deleteLines(alloc, 1);

    try t.print(alloc, 'E');
    t.carriageReturn();
    t.linefeed(alloc);

    {
        var str = try t.plainString(testing.allocator);
        defer testing.allocator.free(str);
        try testing.expectEqualStrings("A\nE\nD\n", str);
    }
}

test "Terminal: insertLines" {
    const alloc = testing.allocator;
    var t = try init(alloc, 2, 5);
    defer t.deinit(alloc);

    // Initial value
    try t.print(alloc, 'A');
    t.carriageReturn();
    t.linefeed(alloc);
    try t.print(alloc, 'B');
    t.carriageReturn();
    t.linefeed(alloc);
    try t.print(alloc, 'C');
    t.carriageReturn();
    t.linefeed(alloc);
    try t.print(alloc, 'D');
    t.carriageReturn();
    t.linefeed(alloc);
    try t.print(alloc, 'E');

    // Move to row 2
    t.setCursorPos(2, 1);

    // Insert two lines
    try t.insertLines(alloc, 2);

    {
        var str = try t.plainString(testing.allocator);
        defer testing.allocator.free(str);
        try testing.expectEqualStrings("A\n\n\nB\nC", str);
    }
}

test "Terminal: insertLines with scroll region" {
    const alloc = testing.allocator;
    var t = try init(alloc, 2, 6);
    defer t.deinit(alloc);

    // Initial value
    try t.print(alloc, 'A');
    t.carriageReturn();
    t.linefeed(alloc);
    try t.print(alloc, 'B');
    t.carriageReturn();
    t.linefeed(alloc);
    try t.print(alloc, 'C');
    t.carriageReturn();
    t.linefeed(alloc);
    try t.print(alloc, 'D');
    t.carriageReturn();
    t.linefeed(alloc);
    try t.print(alloc, 'E');

    t.setScrollingRegion(1, 2);
    t.setCursorPos(1, 1);
    try t.insertLines(alloc, 1);

    try t.print(alloc, 'X');

    {
        var str = try t.plainString(testing.allocator);
        defer testing.allocator.free(str);
        try testing.expectEqualStrings("X\nA\nC\nD\nE", str);
    }
}

test "Terminal: insertLines more than remaining" {
    const alloc = testing.allocator;
    var t = try init(alloc, 2, 5);
    defer t.deinit(alloc);

    // Initial value
    try t.print(alloc, 'A');
    t.carriageReturn();
    t.linefeed(alloc);
    try t.print(alloc, 'B');
    t.carriageReturn();
    t.linefeed(alloc);
    try t.print(alloc, 'C');
    t.carriageReturn();
    t.linefeed(alloc);
    try t.print(alloc, 'D');
    t.carriageReturn();
    t.linefeed(alloc);
    try t.print(alloc, 'E');

    // Move to row 2
    t.setCursorPos(2, 1);

    // Insert a bunch of  lines
    try t.insertLines(alloc, 20);

    {
        var str = try t.plainString(testing.allocator);
        defer testing.allocator.free(str);
        try testing.expectEqualStrings("A\n\n\n\n", str);
    }
}
