//! VT-series parser for escape and control sequences.
//!
//! This is implemented directly as the state machine described on
//! vt100.net: https://vt100.net/emu/dec_ansi_parser
const Parser = @This();

const std = @import("std");
const testing = std.testing;
const table = @import("parse_table.zig").table;
const osc = @import("osc.zig");

const log = std.log.scoped(.parser);

/// States for the state machine
pub const State = enum {
    anywhere,
    ground,
    escape,
    escape_intermediate,
    csi_entry,
    csi_intermediate,
    csi_param,
    csi_ignore,
    dcs_entry,
    dcs_param,
    dcs_intermediate,
    dcs_passthrough,
    dcs_ignore,
    osc_string,
    sos_pm_apc_string,
};

/// Transition action is an action that can be taken during a state
/// transition. This is more of an internal action, not one used by
/// end users, typically.
pub const TransitionAction = enum {
    none,
    ignore,
    print,
    execute,
    collect,
    param,
    esc_dispatch,
    csi_dispatch,
    put,
    osc_put,
};

/// Action is the action that a caller of the parser is expected to
/// take as a result of some input character.
pub const Action = union(enum) {
    /// Draw character to the screen.
    print: u8,

    /// Execute the C0 or C1 function.
    execute: u8,

    /// Execute the CSI command. Note that pointers within this
    /// structure are only valid until the next call to "next".
    csi_dispatch: CSI,

    /// Execute the ESC command.
    esc_dispatch: ESC,

    /// Execute the OSC command.
    osc_dispatch: osc.Command,

    /// DCS-related events.
    dcs_hook: DCS,
    dcs_put: u8,
    dcs_unhook: void,

    pub const CSI = struct {
        intermediates: []u8,
        params: []u16,
        final: u8,
    };

    pub const ESC = struct {
        intermediates: []u8,
        final: u8,
    };

    pub const DCS = struct {
        intermediates: []u8,
        params: []u16,
        final: u8,
    };
};

/// Keeps track of the parameter sep used for CSI params. We allow colons
/// to be used ONLY by the 'm' CSI action.
const ParamSepState = enum(u8) {
    none = 0,
    semicolon = ';',
    colon = ':',
    mixed = 1,
};

/// Maximum number of intermediate characters during parsing.
const MAX_INTERMEDIATE = 2;
const MAX_PARAMS = 16;

/// Current state of the state machine
state: State = .ground,

/// Intermediate tracking.
intermediates: [MAX_INTERMEDIATE]u8 = undefined,
intermediates_idx: u8 = 0,

/// Param tracking, building
params: [MAX_PARAMS]u16 = undefined,
params_idx: u8 = 0,
params_sep: ParamSepState = .none,
param_acc: u16 = 0,
param_acc_idx: u8 = 0,

/// Parser for OSC sequences
osc_parser: osc.Parser = .{},

pub fn init() Parser {
    return .{};
}

/// Next consums the next character c and returns the actions to execute.
/// Up to 3 actions may need to be exected -- in order -- representing
/// the state exit, transition, and entry actions.
pub fn next(self: *Parser, c: u8) [3]?Action {
    const effect = effect: {
        // First look up the transition in the anywhere table.
        const anywhere = table[c][@enumToInt(State.anywhere)];
        if (anywhere.state != .anywhere) break :effect anywhere;

        // If we don't have any transition from anywhere, use our state.
        break :effect table[c][@enumToInt(self.state)];
    };

    // log.info("next: {x}", .{c});

    const next_state = effect.state;
    const action = effect.action;

    // After generating the actions, we set our next state.
    defer self.state = next_state;

    // When going from one state to another, the actions take place in this order:
    //
    // 1. exit action from old state
    // 2. transition action
    // 3. entry action to new state
    return [3]?Action{
        // Exit depends on current state
        if (self.state == next_state) null else switch (self.state) {
            .osc_string => if (self.osc_parser.end()) |cmd|
                Action{ .osc_dispatch = cmd }
            else
                null,
            .dcs_passthrough => Action{ .dcs_unhook = {} },
            else => null,
        },

        self.doAction(action, c),

        // Entry depends on new state
        if (self.state == next_state) null else switch (next_state) {
            .escape, .dcs_entry, .csi_entry => clear: {
                self.clear();
                break :clear null;
            },
            .osc_string => osc_string: {
                self.osc_parser.reset();
                break :osc_string null;
            },
            .dcs_passthrough => Action{
                .dcs_hook = .{
                    .intermediates = self.intermediates[0..self.intermediates_idx],
                    .params = self.params[0..self.params_idx],
                    .final = c,
                },
            },
            else => null,
        },
    };
}

fn doAction(self: *Parser, action: TransitionAction, c: u8) ?Action {
    return switch (action) {
        .none, .ignore => null,
        .print => Action{ .print = c },
        .execute => Action{ .execute = c },
        .collect => collect: {
            if (self.intermediates_idx >= MAX_INTERMEDIATE) {
                log.warn("invalid intermediates count", .{});
                break :collect null;
            }

            self.intermediates[self.intermediates_idx] = c;
            self.intermediates_idx += 1;

            // The client is expected to perform no action.
            break :collect null;
        },
        .param => param: {
            // Semicolon separates parameters. If we encounter a semicolon
            // we need to store and move on to the next parameter.
            if (c == ';' or c == ':') {
                // Ignore too many parameters
                if (self.params_idx >= MAX_PARAMS) break :param null;

                // If this is our first time seeing a parameter, we track
                // the separator used so that we can't mix separators later.
                if (self.params_idx == 0) self.params_sep = @intToEnum(ParamSepState, c);
                if (@intToEnum(ParamSepState, c) != self.params_sep) self.params_sep = .mixed;

                // Set param final value
                self.params[self.params_idx] = self.param_acc;
                self.params_idx += 1;

                // Reset current param value to 0
                self.param_acc = 0;
                self.param_acc_idx = 0;
                break :param null;
            }

            // A numeric value. Add it to our accumulator.
            if (self.param_acc_idx > 0) {
                self.param_acc *|= 10;
            }
            self.param_acc +|= c - '0';
            self.param_acc_idx += 1;

            // The client is expected to perform no action.
            break :param null;
        },
        .osc_put => osc_put: {
            self.osc_parser.next(c);
            break :osc_put null;
        },
        .csi_dispatch => csi_dispatch: {
            // Finalize parameters if we have one
            if (self.param_acc_idx > 0) {
                self.params[self.params_idx] = self.param_acc;
                self.params_idx += 1;
            }

            // We only allow the colon separator for the 'm' command.
            switch (self.params_sep) {
                .none => {},
                .semicolon => {},
                .colon => if (c != 'm') break :csi_dispatch null,
                .mixed => break :csi_dispatch null,
            }

            break :csi_dispatch Action{
                .csi_dispatch = .{
                    .intermediates = self.intermediates[0..self.intermediates_idx],
                    .params = self.params[0..self.params_idx],
                    .final = c,
                },
            };
        },
        .esc_dispatch => Action{
            .esc_dispatch = .{
                .intermediates = self.intermediates[0..self.intermediates_idx],
                .final = c,
            },
        },
        .put => Action{
            .dcs_put = c,
        },
    };
}

fn clear(self: *Parser) void {
    self.intermediates_idx = 0;
    self.params_idx = 0;
    self.param_acc = 0;
    self.param_acc_idx = 0;
}

test {
    var p = init();
    _ = p.next(0x9E);
    try testing.expect(p.state == .sos_pm_apc_string);
    _ = p.next(0x9C);
    try testing.expect(p.state == .ground);

    {
        const a = p.next('a');
        try testing.expect(p.state == .ground);
        try testing.expect(a[0] == null);
        try testing.expect(a[1].? == .print);
        try testing.expect(a[2] == null);
    }

    {
        const a = p.next(0x19);
        try testing.expect(p.state == .ground);
        try testing.expect(a[0] == null);
        try testing.expect(a[1].? == .execute);
        try testing.expect(a[2] == null);
    }
}

test "esc: ESC ( B" {
    var p = init();
    _ = p.next(0x1B);
    _ = p.next('(');

    {
        const a = p.next('B');
        try testing.expect(p.state == .ground);
        try testing.expect(a[0] == null);
        try testing.expect(a[1].? == .esc_dispatch);
        try testing.expect(a[2] == null);

        const d = a[1].?.esc_dispatch;
        try testing.expect(d.final == 'B');
        try testing.expect(d.intermediates.len == 1);
        try testing.expect(d.intermediates[0] == '(');
    }
}

test "csi: ESC [ H" {
    var p = init();
    _ = p.next(0x1B);
    _ = p.next(0x5B);

    {
        const a = p.next(0x48);
        try testing.expect(p.state == .ground);
        try testing.expect(a[0] == null);
        try testing.expect(a[1].? == .csi_dispatch);
        try testing.expect(a[2] == null);

        const d = a[1].?.csi_dispatch;
        try testing.expect(d.final == 0x48);
        try testing.expect(d.params.len == 0);
    }
}

test "csi: ESC [ 1 ; 4 H" {
    var p = init();
    _ = p.next(0x1B);
    _ = p.next(0x5B);
    _ = p.next(0x31); // 1
    _ = p.next(0x3B); // ;
    _ = p.next(0x34); // 4

    {
        const a = p.next(0x48); // H
        try testing.expect(p.state == .ground);
        try testing.expect(a[0] == null);
        try testing.expect(a[1].? == .csi_dispatch);
        try testing.expect(a[2] == null);

        const d = a[1].?.csi_dispatch;
        try testing.expect(d.final == 'H');
        try testing.expect(d.params.len == 2);
        try testing.expectEqual(@as(u16, 1), d.params[0]);
        try testing.expectEqual(@as(u16, 4), d.params[1]);
    }
}

test "csi: SGR ESC [ 38 : 2 m" {
    var p = init();
    _ = p.next(0x1B);
    _ = p.next('[');
    _ = p.next('3');
    _ = p.next('8');
    _ = p.next(':');
    _ = p.next('2');

    {
        const a = p.next('m');
        try testing.expect(p.state == .ground);
        try testing.expect(a[0] == null);
        try testing.expect(a[1].? == .csi_dispatch);
        try testing.expect(a[2] == null);

        const d = a[1].?.csi_dispatch;
        try testing.expect(d.final == 'm');
        try testing.expect(d.params.len == 2);
        try testing.expectEqual(@as(u16, 38), d.params[0]);
        try testing.expectEqual(@as(u16, 2), d.params[1]);
    }
}

test "csi: mixing semicolon/colon" {
    var p = init();
    _ = p.next(0x1B);
    for ("[38:2;4m") |c| {
        const a = p.next(c);
        try testing.expect(a[0] == null);
        try testing.expect(a[1] == null);
        try testing.expect(a[2] == null);
    }

    try testing.expect(p.state == .ground);
}

test "csi: colon for non-m final" {
    var p = init();
    _ = p.next(0x1B);
    for ("[38:2h") |c| {
        const a = p.next(c);
        try testing.expect(a[0] == null);
        try testing.expect(a[1] == null);
        try testing.expect(a[2] == null);
    }

    try testing.expect(p.state == .ground);
}

test "osc: change window title" {
    var p = init();
    _ = p.next(0x1B);
    _ = p.next(']');
    _ = p.next('0');
    _ = p.next(';');
    _ = p.next('a');
    _ = p.next('b');
    _ = p.next('c');

    {
        const a = p.next(0x07); // BEL
        try testing.expect(p.state == .ground);
        try testing.expect(a[0].? == .osc_dispatch);
        try testing.expect(a[1] == null);
        try testing.expect(a[2] == null);

        const cmd = a[0].?.osc_dispatch;
        try testing.expect(cmd == .change_window_title);
    }
}
