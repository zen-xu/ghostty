//! The primary terminal emulation structure. This represents a single
//! "terminal" containing a grid of characters and exposes various operations
//! on that grid. This also maintains the scrollback buffer.
const Terminal = @This();

const std = @import("std");
const builtin = @import("builtin");
const testing = std.testing;
const Allocator = std.mem.Allocator;
const ansi = @import("ansi.zig");
const csi = @import("csi.zig");
const Parser = @import("Parser.zig");
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

/// VT stream parser
parser: Parser,

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
    x: usize,
    y: usize,
};

/// Initialize a new terminal.
pub fn init(alloc: Allocator, cols: usize, rows: usize) !Terminal {
    return Terminal{
        .cols = cols,
        .rows = rows,
        .screen = .{},
        .cursor = .{ .x = 0, .y = 0 },
        .tabstops = try Tabstops.init(alloc, cols, 8),
        .parser = Parser.init(),
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

/// Append a string of characters. See appendChar.
pub fn append(self: *Terminal, alloc: Allocator, str: []const u8) !void {
    const tracy = trace(@src());
    defer tracy.end();

    for (str) |c| {
        try self.appendChar(alloc, c);
    }
}

/// Append a single character to the terminal.
///
/// This may allocate if necessary to store the character in the grid.
pub fn appendChar(self: *Terminal, alloc: Allocator, c: u8) !void {
    const tracy = trace(@src());
    defer tracy.end();

    //log.debug("char: {}", .{c});
    const actions = self.parser.next(c);
    for (actions) |action_opt| {
        switch (action_opt orelse continue) {
            .print => |p| try self.print(alloc, p),
            .execute => |code| try self.execute(alloc, code),
            .csi_dispatch => |csi| try self.csiDispatch(alloc, csi),
        }
    }
}

fn csiDispatch(
    self: *Terminal,
    alloc: Allocator,
    action: Parser.Action.CSI,
) !void {
    switch (action.final) {
        // CUP - Set Cursor Position.
        'H' => {
            switch (action.params.len) {
                0 => try self.setCursorPosition(1, 1),
                1 => try self.setCursorPosition(action.params[0], 1),
                2 => try self.setCursorPosition(action.params[0], action.params[1]),
                else => log.warn("unimplemented CSI: {}", .{action}),
            }
        },

        // Erase Display
        'J' => try self.eraseDisplay(alloc, switch (action.params.len) {
            0 => .below,
            1 => mode: {
                // TODO: use meta to get enum max
                if (action.params[0] > 3) {
                    log.warn("invalid erase display command: {}", .{action});
                    return;
                }

                break :mode @intToEnum(
                    csi.EraseDisplayMode,
                    action.params[0],
                );
            },
            else => {
                log.warn("invalid erase display command: {}", .{action});
                return;
            },
        }),

        else => log.warn("unimplemented CSI: {}", .{action}),
    }
}

fn print(self: *Terminal, alloc: Allocator, c: u8) !void {
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

fn execute(self: *Terminal, alloc: Allocator, c: u8) !void {
    const tracy = trace(@src());
    defer tracy.end();

    switch (@intToEnum(ansi.C0, c)) {
        .NUL => {},
        .BEL => self.bell(),
        .BS => self.backspace(),
        .HT => try self.horizontal_tab(alloc),
        .LF => self.linefeed(alloc),
        .CR => self.carriage_return(),
    }
}

pub fn bell(self: *Terminal) void {
    // TODO: bell
    _ = self;
    log.info("bell", .{});
}

// Set Cursor Position. Move cursor to the position indicated
// by row and column (1-indexed). If column is 0, it is adjusted to 1.
// If column is greater than the right-most column it is adjusted to
// the right-most column. If row is 0, it is adjusted to 1. If row is
// greater than the bottom-most row it is adjusted to the bottom-most
// row.
pub fn setCursorPosition(self: *Terminal, row: usize, col: usize) !void {
    const tracy = trace(@src());
    defer tracy.end();

    self.cursor.x = @minimum(self.cols, col) -| 1;
    self.cursor.y = @minimum(self.rows, row) -| 1;
}

/// Erase the display.
/// TODO: test
pub fn eraseDisplay(
    self: *Terminal,
    alloc: Allocator,
    mode: csi.EraseDisplayMode,
) !void {
    switch (mode) {
        .complete => {
            for (self.screen.items) |*line| line.deinit(alloc);
            self.screen.clearRetainingCapacity();
        },
        else => @panic("unimplemented"),
    }
}

/// Backspace moves the cursor back a column (but not less than 0).
pub fn backspace(self: *Terminal) void {
    const tracy = trace(@src());
    defer tracy.end();

    self.cursor.x -|= 1;
}

/// Horizontal tab moves the cursor to the next tabstop, clearing
/// the screen to the left the tabstop.
pub fn horizontal_tab(self: *Terminal, alloc: Allocator) !void {
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
pub fn carriage_return(self: *Terminal) void {
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
        self.scroll_up(alloc);
        return;
    }

    // Increase cursor by 1
    self.cursor.y += 1;
}

/// Scroll the text up by one row.
pub fn scroll_up(self: *Terminal, alloc: Allocator) void {
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

test {
    _ = Parser;
    _ = Tabstops;
}

test "Terminal: input with no control characters" {
    var t = try init(testing.allocator, 80, 80);
    defer t.deinit(testing.allocator);

    // Basic grid writing
    try t.append(testing.allocator, "hello");
    try testing.expectEqual(@as(usize, 0), t.cursor.y);
    try testing.expectEqual(@as(usize, 5), t.cursor.x);
    {
        var str = try t.plainString(testing.allocator);
        defer testing.allocator.free(str);
        try testing.expectEqualStrings("hello", str);
    }
}

test "Terminal: C0 control LF and CR" {
    var t = try init(testing.allocator, 80, 80);
    defer t.deinit(testing.allocator);

    // Basic grid writing
    try t.append(testing.allocator, "hello\r\nworld");
    try testing.expectEqual(@as(usize, 1), t.cursor.y);
    try testing.expectEqual(@as(usize, 5), t.cursor.x);
    {
        var str = try t.plainString(testing.allocator);
        defer testing.allocator.free(str);
        try testing.expectEqualStrings("hello\nworld", str);
    }
}

test "Terminal: C0 control BS" {
    var t = try init(testing.allocator, 80, 80);
    defer t.deinit(testing.allocator);

    // BS
    try t.append(testing.allocator, "hello");
    try t.appendChar(testing.allocator, @enumToInt(ansi.C0.BS));
    try t.append(testing.allocator, "y");
    try testing.expectEqual(@as(usize, 0), t.cursor.y);
    try testing.expectEqual(@as(usize, 5), t.cursor.x);
    {
        var str = try t.plainString(testing.allocator);
        defer testing.allocator.free(str);
        try testing.expectEqualStrings("helly", str);
    }
}

test "Terminal: horizontal tabs" {
    var t = try init(testing.allocator, 80, 5);
    defer t.deinit(testing.allocator);

    // HT
    try t.append(testing.allocator, "1\t");
    try testing.expectEqual(@as(usize, 8), t.cursor.x);

    // HT
    try t.append(testing.allocator, "\t");
    try testing.expectEqual(@as(usize, 16), t.cursor.x);
}

test "Terminal: CUP (ESC [ H)" {
    var t = try init(testing.allocator, 80, 80);
    defer t.deinit(testing.allocator);

    // X, Y both specified
    try t.append(testing.allocator, "\x1B[5;10H");
    try testing.expectEqual(@as(usize, 4), t.cursor.y);
    try testing.expectEqual(@as(usize, 9), t.cursor.x);

    // Y only
    try t.append(testing.allocator, "\x1B[5H");
    try testing.expectEqual(@as(usize, 4), t.cursor.y);
    try testing.expectEqual(@as(usize, 0), t.cursor.x);

    // 0, 0 default
    try t.append(testing.allocator, "\x1B[H");
    try testing.expectEqual(@as(usize, 0), t.cursor.y);
    try testing.expectEqual(@as(usize, 0), t.cursor.x);

    // invalid
    try t.append(testing.allocator, "\x1B[1;2;3H");
    try testing.expectEqual(@as(usize, 0), t.cursor.y);
    try testing.expectEqual(@as(usize, 0), t.cursor.x);
}

test "Terminal: setCursorPosition" {
    var t = try init(testing.allocator, 80, 80);
    defer t.deinit(testing.allocator);

    try testing.expectEqual(@as(usize, 0), t.cursor.x);
    try testing.expectEqual(@as(usize, 0), t.cursor.y);

    // Setting it to 0 should keep it zero (1 based)
    try t.setCursorPosition(0, 0);
    try testing.expectEqual(@as(usize, 0), t.cursor.x);
    try testing.expectEqual(@as(usize, 0), t.cursor.y);

    // Should clamp to size
    try t.setCursorPosition(81, 81);
    try testing.expectEqual(@as(usize, 79), t.cursor.x);
    try testing.expectEqual(@as(usize, 79), t.cursor.y);
}
