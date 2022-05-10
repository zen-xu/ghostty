//! OSC (Operating System Command) related functions and types. OSC is
//! another set of control sequences for terminal programs that start with
//! "ESC ]". Unlike CSI or standard ESC sequences, they may contain strings
//! and other irregular formatting so a dedicated parser is created to handle it.
const osc = @This();

const std = @import("std");

const log = std.log.scoped(.osc);

pub const Command = union(enum) {
    /// Set the window title of the terminal
    ///
    /// If title mode 0  is set text is expect to be hex encoded (i.e. utf-8
    /// with each code unit further encoded with two hex digets).
    ///
    /// If title mode 2 is set or the terminal is setup for unconditional
    /// utf-8 titles text is interpreted as utf-8. Else text is interpreted
    /// as latin1.
    change_window_title: []const u8,
};

pub const Parser = struct {
    state: State = .empty,
    command: Command = undefined,
    param_str: ?*[]const u8 = null,
    buf: [MAX_BUF]u8 = undefined,
    buf_start: usize = 0,
    buf_idx: usize = 0,
    complete: bool = false,

    // Maximum length of a single OSC command. This is the full OSC command
    // sequence length (excluding ESC ]). This is arbitrary, I couldn't find
    // any definitive resource on how long this should be.
    const MAX_BUF = 2048;

    pub const State = enum {
        empty,
        invalid,
        @"0",
        string,
    };

    /// Reset the parser start.
    pub fn reset(self: *Parser) void {
        self.state = .empty;
        self.param_str = null;
        self.buf_start = 0;
        self.buf_idx = 0;
        self.complete = false;
    }

    /// Consume the next character c and advance the parser state.
    pub fn next(self: *Parser, c: u8) void {
        // We store everything in the buffer so we can do a better job
        // logging if we get to an invalid command.
        self.buf[self.buf_idx] = c;
        self.buf_idx += 1;

        log.info("state = {} c = {x}", .{ self.state, c });

        switch (self.state) {
            // Ignore, we're in some invalid state and we can't possibly
            // do anything reasonable.
            .invalid => {},

            .empty => switch (c) {
                '0' => self.state = .@"0",
                else => self.state = .invalid,
            },

            .@"0" => switch (c) {
                ';' => {
                    self.command = .{ .change_window_title = undefined };

                    self.state = .string;
                    self.param_str = &self.command.change_window_title;
                    self.buf_start = self.buf_idx;
                },
                else => self.state = .invalid,
            },

            .string => {
                // Complete once we receive one character since we have
                // at least SOME value for the expected string value.
                self.complete = true;
            },
        }
    }

    /// End the sequence and return the command, if any. If the return value
    /// is null, then no valid command was found.
    pub fn end(self: Parser) ?Command {
        if (!self.complete) {
            log.warn("invalid OSC command: {s}", .{self.buf[0..self.buf_idx]});
            return null;
        }

        // If we have an expected string parameter, fill it in.
        if (self.param_str) |param_str| {
            param_str.* = self.buf[self.buf_start..self.buf_idx];
        }

        return self.command;
    }
};

test "OSC: change_window_title" {
    const testing = std.testing;

    var p: Parser = .{};
    p.next('0');
    p.next(';');
    p.next('a');
    p.next('b');
    const cmd = p.end().?;
    try testing.expect(cmd == .change_window_title);
    try testing.expectEqualStrings("ab", cmd.change_window_title);
}
