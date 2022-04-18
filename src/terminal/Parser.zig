//! VT-series parser for escape and control sequences.
//!
//! This is implemented directly as the state machine described on
//! vt100.net: https://vt100.net/emu/dec_ansi_parser
const Parser = @This();

const std = @import("std");
const testing = std.testing;
const table = @import("parse_table.zig").table;

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
    clear,
    collect,
    param,
    esc_dispatch,
    csi_dispatch,
    hook,
    put,
    unhook,
    osc_start,
    osc_put,
    osc_end,
};

/// Action is the action that a caller of the parser is expected to
/// take as a result of some input character.
pub const Action = union(enum) {
    /// Draw character to the screen.
    print: u8,

    /// Execute the C0 or C1 function.
    execute: u8,
};

/// Current state of the state machine
state: State = .ground,

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
        switch (self.state) {
            .osc_string => @panic("TODO"), // TODO: osc_end
            .dcs_passthrough => @panic("TODO"), // TODO: unhook
            else => null,
        },

        self.doAction(action, c),

        switch (self.state) {
            .escape, .dcs_entry, .csi_entry => @panic("TODO"), // TODO: clear
            .osc_string => @panic("TODO"), // TODO: osc_start
            .dcs_passthrough => @panic("TODO"), // TODO: hook
            else => null,
        },
    };
}

fn doAction(self: *Parser, action: TransitionAction, c: u8) ?Action {
    _ = self;
    return switch (action) {
        .none, .ignore => null,
        .print => return Action{ .print = c },
        .execute => return Action{ .execute = c },
        else => @panic("TODO"),
    };
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
