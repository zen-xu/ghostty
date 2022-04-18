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

pub const Action = enum {
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

/// Current state of the state machine
state: State = .ground,

pub fn init() Parser {
    return .{};
}

pub fn next(self: *Parser, c: u8) void {
    const effect = effect: {
        // First look up the transition in the anywhere table.
        const anywhere = table[c][@enumToInt(State.anywhere)];
        if (anywhere.state != .anywhere) break :effect anywhere;

        // If we don't have any transition from anywhere, use our state.
        break :effect table[c][@enumToInt(self.state)];
    };

    const next_state = effect.state;
    const action = effect.action;

    // When going from one state to another, the actions take place in this order:
    //
    // 1. exit action from old state
    // 2. transition action
    // 3. entry action to new state

    // Perform exit actions. "The action associated with the exit event happens
    // when an incoming symbol causes a transition from this state to another
    // state (or even back to the same state)."
    switch (self.state) {
        .osc_string => {}, // TODO: osc_end
        .dcs_passthrough => {}, // TODO: unhook
        else => {},
    }

    // Perform the transition action
    self.doAction(action);

    // Perform the entry action
    // TODO: when _first_ entered only?
    switch (self.state) {
        .escape, .dcs_entry, .csi_entry => {}, // TODO: clear
        .osc_string => {}, // TODO: osc_start
        .dcs_passthrough => {}, // TODO: hook
        else => {},
    }

    self.state = next_state;
}

fn doAction(self: *Parser, action: Action) void {
    _ = self;
    _ = action;
}

test {
    var p = init();
    p.next(0x9E);
    try testing.expect(p.state == .sos_pm_apc_string);
}
