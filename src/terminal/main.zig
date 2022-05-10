pub const Terminal = @import("Terminal.zig");
pub const Parser = @import("Parser.zig");

// Not exported because they're just used for tests.

test {
    _ = Parser;
    _ = Terminal;

    _ = @import("osc.zig");
    _ = @import("parse_table.zig");
    _ = @import("Tabstops.zig");
}
