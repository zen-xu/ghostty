const std = @import("std");
const testing = std.testing;
const Parser = @import("Parser.zig");
const ansi = @import("ansi.zig");
const csi = @import("csi.zig");
const trace = @import("../tracy/tracy.zig").trace;

const log = std.log.scoped(.stream);

/// Returns a type that can process a stream of tty control characters.
/// This will call various callback functions on type T. Type T only has to
/// implement the callbacks it cares about; any unimplemented callbacks will
/// logged at runtime.
///
/// To figure out what callbacks exist, search the source for "hasDecl". This
/// isn't ideal but for now that's the best approach.
///
/// This is implemented this way because we purposely do NOT want dynamic
/// dispatch for performance reasons. The way this is implemented forces
/// comptime resolution for all function calls.
pub fn Stream(comptime Handler: type) type {
    return struct {
        const Self = @This();

        // We use T with @hasDecl so it needs to be a struct. Unwrap the
        // pointer if we were given one.
        const T = switch (@typeInfo(Handler)) {
            .Pointer => |p| p.child,
            else => Handler,
        };

        handler: Handler,
        parser: Parser = .{},

        /// Process a string of characters.
        pub fn nextSlice(self: *Self, c: []const u8) !void {
            const tracy = trace(@src());
            defer tracy.end();
            for (c) |single| try self.next(single);
        }

        /// Process the next character and call any callbacks if necessary.
        pub fn next(self: *Self, c: u8) !void {
            const tracy = trace(@src());
            defer tracy.end();

            //log.debug("char: {}", .{c});
            const actions = self.parser.next(c);
            for (actions) |action_opt| {
                // if (action_opt) |action| log.info("action: {}", .{action});
                switch (action_opt orelse continue) {
                    .print => |p| if (@hasDecl(T, "print")) try self.handler.print(p),
                    .execute => |code| try self.execute(code),
                    .csi_dispatch => |csi| try self.csiDispatch(csi),
                    .esc_dispatch => |esc| try self.escDispatch(esc),
                    .osc_dispatch => |cmd| log.warn("unhandled OSC: {}", .{cmd}),
                    .dcs_hook => |dcs| log.warn("unhandled DCS hook: {}", .{dcs}),
                    .dcs_put => |code| log.warn("unhandled DCS put: {}", .{code}),
                    .dcs_unhook => log.warn("unhandled DCS unhook", .{}),
                }
            }
        }

        fn execute(self: *Self, c: u8) !void {
            switch (@intToEnum(ansi.C0, c)) {
                .NUL => {},

                .BEL => if (@hasDecl(T, "bell"))
                    try self.handler.bell()
                else
                    log.warn("unimplemented execute: {x}", .{c}),

                .BS => if (@hasDecl(T, "backspace"))
                    try self.handler.backspace()
                else
                    log.warn("unimplemented execute: {x}", .{c}),

                .HT => if (@hasDecl(T, "horizontalTab"))
                    try self.handler.horizontalTab()
                else
                    log.warn("unimplemented execute: {x}", .{c}),

                .LF => if (@hasDecl(T, "linefeed"))
                    try self.handler.linefeed()
                else
                    log.warn("unimplemented execute: {x}", .{c}),

                .CR => if (@hasDecl(T, "carriageReturn"))
                    try self.handler.carriageReturn()
                else
                    log.warn("unimplemented execute: {x}", .{c}),
            }
        }

        fn csiDispatch(self: *Self, action: Parser.Action.CSI) !void {
            switch (action.final) {
                // CUU - Cursor Up
                'A' => if (@hasDecl(T, "setCursorUp")) try self.handler.setCursorUp(
                    switch (action.params.len) {
                        0 => 1,
                        1 => action.params[0],
                        else => {
                            log.warn("invalid cursor up command: {}", .{action});
                            return;
                        },
                    },
                ) else log.warn("unimplemented CSI callback: {}", .{action}),

                // CUD - Cursor Down
                'B' => if (@hasDecl(T, "setCursorDown")) try self.handler.setCursorDown(
                    switch (action.params.len) {
                        0 => 1,
                        1 => action.params[0],
                        else => {
                            log.warn("invalid cursor down command: {}", .{action});
                            return;
                        },
                    },
                ) else log.warn("unimplemented CSI callback: {}", .{action}),

                // CUF - Cursor Right
                'C' => if (@hasDecl(T, "setCursorRight")) try self.handler.setCursorRight(
                    switch (action.params.len) {
                        0 => 1,
                        1 => action.params[0],
                        else => {
                            log.warn("invalid cursor right command: {}", .{action});
                            return;
                        },
                    },
                ) else log.warn("unimplemented CSI callback: {}", .{action}),

                // HPA - Cursor Horizontal Position Absolute
                // TODO: test
                'G', '`' => if (@hasDecl(T, "setCursorCol")) switch (action.params.len) {
                    0 => try self.handler.setCursorCol(1),
                    1 => try self.handler.setCursorCol(action.params[0]),
                    else => log.warn("invalid HPA command: {}", .{action}),
                } else log.warn("unimplemented CSI callback: {}", .{action}),

                // CUP - Set Cursor Position.
                // TODO: test
                'H' => if (@hasDecl(T, "setCursorPos")) switch (action.params.len) {
                    0 => try self.handler.setCursorPos(1, 1),
                    1 => try self.handler.setCursorPos(action.params[0], 1),
                    2 => try self.handler.setCursorPos(action.params[0], action.params[1]),
                    else => log.warn("invalid CUP command: {}", .{action}),
                } else log.warn("unimplemented CSI callback: {}", .{action}),

                // Erase Display
                // TODO: test
                'J' => if (@hasDecl(T, "eraseDisplay")) try self.handler.eraseDisplay(
                    switch (action.params.len) {
                        0 => .below,
                        1 => mode: {
                            // TODO: use meta to get enum max
                            if (action.params[0] > 3) {
                                log.warn("invalid erase display command: {}", .{action});
                                return;
                            }

                            break :mode @intToEnum(
                                csi.EraseDisplay,
                                action.params[0],
                            );
                        },
                        else => {
                            log.warn("invalid erase display command: {}", .{action});
                            return;
                        },
                    },
                ) else log.warn("unimplemented CSI callback: {}", .{action}),

                // Erase Line
                'K' => if (@hasDecl(T, "eraseLine")) try self.handler.eraseLine(
                    switch (action.params.len) {
                        0 => .right,
                        1 => mode: {
                            // TODO: use meta to get enum max
                            if (action.params[0] > 3) {
                                log.warn("invalid erase line command: {}", .{action});
                                return;
                            }

                            break :mode @intToEnum(
                                csi.EraseLine,
                                action.params[0],
                            );
                        },
                        else => {
                            log.warn("invalid erase line command: {}", .{action});
                            return;
                        },
                    },
                ) else log.warn("unimplemented CSI callback: {}", .{action}),

                // DL - Delete Lines
                // TODO: test
                'M' => if (@hasDecl(T, "deleteLines")) switch (action.params.len) {
                    0 => try self.handler.deleteLines(1),
                    1 => try self.handler.deleteLines(action.params[0]),
                    else => log.warn("invalid DL command: {}", .{action}),
                } else log.warn("unimplemented CSI callback: {}", .{action}),

                // Delete Character (DCH)
                'P' => if (@hasDecl(T, "deleteChars")) try self.handler.deleteChars(
                    switch (action.params.len) {
                        0 => 1,
                        1 => action.params[0],
                        else => {
                            log.warn("invalid delete characters command: {}", .{action});
                            return;
                        },
                    },
                ) else log.warn("unimplemented CSI callback: {}", .{action}),

                // Erase Characters (ECH)
                'X' => if (@hasDecl(T, "eraseChars")) try self.handler.eraseChars(
                    switch (action.params.len) {
                        0 => 1,
                        1 => action.params[0],
                        else => {
                            log.warn("invalid erase characters command: {}", .{action});
                            return;
                        },
                    },
                ) else log.warn("unimplemented CSI callback: {}", .{action}),

                // VPA - Cursor Vertical Position Absolute
                'd' => if (@hasDecl(T, "setCursorRow")) try self.handler.setCursorRow(
                    switch (action.params.len) {
                        0 => 1,
                        1 => action.params[0],
                        else => {
                            log.warn("invalid VPA command: {}", .{action});
                            return;
                        },
                    },
                ) else log.warn("unimplemented CSI callback: {}", .{action}),

                // SM - Set Mode
                'h' => if (@hasDecl(T, "setMode")) {
                    for (action.params) |mode|
                        try self.handler.setMode(@intToEnum(ansi.Mode, mode), true);
                } else log.warn("unimplemented CSI callback: {}", .{action}),

                // RM - Reset Mode
                'l' => if (@hasDecl(T, "setMode")) {
                    for (action.params) |mode|
                        try self.handler.setMode(@intToEnum(ansi.Mode, mode), false);
                } else log.warn("unimplemented CSI callback: {}", .{action}),

                // SGR - Select Graphic Rendition
                'm' => if (@hasDecl(T, "selectGraphicRendition")) {
                    if (action.params.len == 0) {
                        // No values defaults to code 0
                        try self.handler.selectGraphicRendition(.default);
                    } else {
                        // Each parameter sets a separate aspect
                        for (action.params) |param| {
                            try self.handler.selectGraphicRendition(@intToEnum(
                                ansi.RenditionAspect,
                                param,
                            ));
                        }
                    }
                } else log.warn("unimplemented CSI callback: {}", .{action}),

                // DECSTBM - Set Top and Bottom Margins
                // TODO: test
                'r' => if (@hasDecl(T, "setTopAndBottomMargin")) switch (action.params.len) {
                    0 => try self.handler.setTopAndBottomMargin(1, 0),
                    1 => try self.handler.setTopAndBottomMargin(action.params[0], 0),
                    2 => try self.handler.setTopAndBottomMargin(action.params[0], action.params[1]),
                    else => log.warn("invalid DECSTBM command: {}", .{action}),
                } else log.warn("unimplemented CSI callback: {}", .{action}),

                else => if (@hasDecl(T, "csiUnimplemented"))
                    try self.handler.csiUnimplemented(action)
                else
                    log.warn("unimplemented CSI action: {}", .{action}),
            }
        }

        fn escDispatch(
            self: *Self,
            action: Parser.Action.ESC,
        ) !void {
            switch (action.final) {
                // RI - Reverse Index
                'M' => if (@hasDecl(T, "reverseIndex")) switch (action.intermediates.len) {
                    0 => try self.handler.reverseIndex(),
                    else => {
                        log.warn("invalid reverse index command: {}", .{action});
                        return;
                    },
                } else log.warn("unimplemented ESC callback: {}", .{action}),

                else => if (@hasDecl(T, "escUnimplemented"))
                    try self.handler.escUnimplemented(action)
                else
                    log.warn("unimplemented ESC action: {}", .{action}),
            }
        }
    };
}

test "stream: print" {
    const H = struct {
        c: ?u8 = 0,

        pub fn print(self: *@This(), c: u8) !void {
            self.c = c;
        }
    };

    var s: Stream(H) = .{ .handler = .{} };
    try s.next('x');
    try testing.expectEqual(@as(u8, 'x'), s.handler.c.?);
}

test "stream: cursor right (CUF)" {
    const H = struct {
        amount: u16 = 0,

        pub fn setCursorRight(self: *@This(), v: u16) !void {
            self.amount = v;
        }
    };

    var s: Stream(H) = .{ .handler = .{} };
    try s.nextSlice("\x1B[C");
    try testing.expectEqual(@as(u16, 1), s.handler.amount);

    try s.nextSlice("\x1B[5C");
    try testing.expectEqual(@as(u16, 5), s.handler.amount);

    s.handler.amount = 0;
    try s.nextSlice("\x1B[5;4C");
    try testing.expectEqual(@as(u16, 0), s.handler.amount);
}

test "stream: set mode (SM) and reset mode (RM)" {
    const H = struct {
        mode: ansi.Mode = @intToEnum(ansi.Mode, 0),

        pub fn setMode(self: *@This(), mode: ansi.Mode, v: bool) !void {
            self.mode = @intToEnum(ansi.Mode, 0);
            if (v) self.mode = mode;
        }
    };

    var s: Stream(H) = .{ .handler = .{} };
    try s.nextSlice("\x1B[?6h");
    try testing.expectEqual(@as(ansi.Mode, .origin), s.handler.mode);

    try s.nextSlice("\x1B[?6l");
    try testing.expectEqual(@intToEnum(ansi.Mode, 0), s.handler.mode);
}
