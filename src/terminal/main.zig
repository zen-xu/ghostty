const stream = @import("stream.zig");
const csi = @import("csi.zig");

pub const Terminal = @import("Terminal.zig");
pub const Parser = @import("Parser.zig");
pub const Stream = stream.Stream;
pub const EraseDisplay = csi.EraseDisplay;
pub const EraseLine = csi.EraseLine;

// Not exported because they're just used for tests.

test {
    _ = csi;
    _ = stream;
    _ = Parser;
    _ = Terminal;

    _ = @import("osc.zig");
    _ = @import("parse_table.zig");
    _ = @import("Tabstops.zig");
}
