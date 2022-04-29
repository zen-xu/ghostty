pub const Terminal = @import("Terminal.zig");

// Not exported because they're just used for tests.

test {
    _ = Terminal;

    _ = @import("parse_table.zig");
    _ = @import("Parser.zig");
    _ = @import("Tabstops.zig");
}
