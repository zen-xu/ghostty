/// C0 (7-bit) control characters from ANSI.
///
/// This is not complete, control characters are only added to this
/// as the terminal emulator handles them.
pub const C0 = enum(u7) {
    /// Null
    NUL = 0x00,
    /// Bell
    BEL = 0x07,
    /// Backspace
    BS = 0x08,
    // Horizontal tab
    HT = 0x09,
    /// Line feed
    LF = 0x0A,
    /// Carriage return
    CR = 0x0D,
};

/// The SGR rendition aspects that can be set, sometimes known as attributes.
/// The value corresponds to the parameter value for the SGR command (ESC [ m).
pub const RenditionAspect = enum(u16) {
    default = 0,
    bold = 1,
    default_fg = 39,
    default_bg = 49,

    // Non-exhaustive so that @intToEnum never fails since the inputs are
    // user-generated.
    _,
};

/// Modes that can be set with with Set Mode (SM) (ESC [ h). The enum
/// values correspond to the `?`-prefixed modes, since those are the ones
/// of primary interest. The enum value is the mode value.
pub const Mode = enum(u16) {
    /// If set, the origin of the coordinate system is relative to the
    /// current scroll region. If set the cursor is moved to the top left of
    /// the current scroll region.
    origin = 6,

    // Non-exhaustive so that @intToEnum never fails for unsupported modes.
    _,
};
