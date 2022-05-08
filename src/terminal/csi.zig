// Modes for the ED CSI command.
pub const EraseDisplayMode = enum(u8) {
    below = 0,
    above = 1,
    complete = 2,
    scrollback = 3,
};
