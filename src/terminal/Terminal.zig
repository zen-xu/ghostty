//! The primary terminal emulation structure. This represents a single
//!
//! "terminal" containing a grid of characters and exposes various operations
//! on that grid. This also maintains the scrollback buffer.
const Terminal = @This();

const std = @import("std");
const builtin = @import("builtin");
const testing = std.testing;
const Allocator = std.mem.Allocator;
const ansi = @import("ansi.zig");
const csi = @import("csi.zig");
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

/// Screen represents a presentable terminal screen made up of lines and cells.
const Screen = std.ArrayListUnmanaged(Line);
const Line = std.ArrayListUnmanaged(Cell);

/// Cell is a single cell within the terminal.
const Cell = struct {
    /// Each cell contains exactly one character. The character is UTF-8 encoded.
    char: u32,

    // TODO(mitchellh): this is where we'll track fg/bg and other attrs.

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

    // Bold specifies that text written should be bold
    // TODO: connect to render
    bold: bool = false,
};

/// Initialize a new terminal.
pub fn init(alloc: Allocator, cols: usize, rows: usize) !Terminal {
    return Terminal{
        .cols = cols,
        .rows = rows,
        .screen = .{},
        .cursor = .{ .x = 0, .y = 0 },
        .tabstops = try Tabstops.init(alloc, cols, 8),
    };
}

pub fn deinit(self: *Terminal, alloc: Allocator) void {
    self.tabstops.deinit(alloc);
    for (self.screen.items) |*line| line.deinit(alloc);
    self.screen.deinit(alloc);
    self.* = undefined;
}

/// Resize the underlying terminal.
pub fn resize(self: *Terminal, cols: usize, rows: usize) void {
    // TODO: actually doing anything for this
    self.cols = cols;
    self.rows = rows;
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
            i += try std.unicode.utf8Encode(@intCast(u21, cell.char), buffer[i..]);
        }
    }

    return buffer[0..i];
}

pub fn print(self: *Terminal, alloc: Allocator, c: u8) !void {
    const tracy = trace(@src());
    defer tracy.end();

    // Build our cell
    const cell = try self.getOrPutCell(alloc, self.cursor.x, self.cursor.y);
    cell.* = .{
        .char = @intCast(u32, c),
    };

    // Move the cursor
    self.cursor.x += 1;

    // TODO: wrap
    if (self.cursor.x == self.cols) {
        self.cursor.x -= 1;
    }
}

pub fn selectGraphicRendition(self: *Terminal, aspect: ansi.RenditionAspect) !void {
    switch (aspect) {
        .default => self.cursor.bold = false,
        .bold => self.cursor.bold = true,
        .default_fg => {}, // TODO
        .default_bg => {}, // TODO
        else => {
            //log.warn("invalid or unimplemented rendition aspect: {}", .{aspect});
        },
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
pub fn setCursorPos(self: *Terminal, row: usize, col: usize) !void {
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
            for (self.screen.items) |*line| line.deinit(alloc);
            self.screen.clearRetainingCapacity();
        },

        .below => {
            // If our cursor is outside our screen, we can't erase anything.
            if (self.cursor.y >= self.screen.items.len) return;
            var line = &self.screen.items[self.cursor.y];

            // Clear this line right (including the cursor)
            if (self.cursor.x < line.items.len) {
                for (line.items[self.cursor.x..line.items.len]) |*cell|
                    cell.char = 0;
            }

            // Remaining lines are deallocated
            if (self.cursor.y + 1 < self.screen.items.len) {
                for (self.screen.items[self.cursor.y + 1 .. self.screen.items.len]) |*below|
                    below.deinit(alloc);
            }

            // Shrink
            self.screen.shrinkRetainingCapacity(self.cursor.y + 1);
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
    mode: csi.EraseLine,
) !void {
    switch (mode) {
        .right => {
            // If our cursor is outside our screen, we can't erase anything.
            if (self.cursor.y >= self.screen.items.len) return;
            var line = &self.screen.items[self.cursor.y];

            // If our cursor is outside our screen, we can't erase anything.
            if (self.cursor.x >= line.items.len) return;

            for (line.items[self.cursor.x..line.items.len]) |*cell|
                cell.char = 0;
        },

        .left => {
            // If our cursor is outside our screen, we can't erase anything.
            if (self.cursor.y >= self.screen.items.len) return;
            var line = &self.screen.items[self.cursor.y];

            // Clear up to our cursor
            const end = @minimum(line.items.len, self.cursor.x);
            for (line.items[0..end]) |*cell|
                cell.char = 0;
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
pub fn eraseChars(self: *Terminal, count: usize) !void {
    var line = &self.screen.items[self.cursor.y];

    // Our last index is at most the end of the number of chars we have
    // in the current line.
    const end = @minimum(line.items.len, self.cursor.x + count);

    // Do nothing if we have no values.
    if (self.cursor.x >= line.items.len) return;

    // Shift
    var i: usize = self.cursor.x;
    while (i < end) : (i += 1) {
        line.items[i].char = 0;
        // TODO: retain graphical attributes
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
    try t.setCursorPos(0, 0);
    try testing.expectEqual(@as(usize, 0), t.cursor.x);
    try testing.expectEqual(@as(usize, 0), t.cursor.y);

    // Should clamp to size
    try t.setCursorPos(81, 81);
    try testing.expectEqual(@as(usize, 79), t.cursor.x);
    try testing.expectEqual(@as(usize, 79), t.cursor.y);
}
