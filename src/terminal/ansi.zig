/// C0 (7-bit) control characters from ANSI.
///
/// This is not complete, control characters are only added to this
/// as the terminal emulator handles them.
pub const C0 = enum(u7) {
    /// Line feed
    LF = 0x0A,
    /// Carriage return
    CR = 0x0D,
};
