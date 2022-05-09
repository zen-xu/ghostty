// Modes for the ED CSI command.
pub const EraseDisplay = enum(u8) {
    below = 0,
    above = 1,
    complete = 2,
    scrollback = 3,
};

// Modes for the EL CSI command.
pub const EraseLine = enum(u8) {
    right = 0,
    left = 1,
    complete = 3,
    right_unless_pending_wrap = 4,
};
