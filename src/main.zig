const options = @import("build_options");
const std = @import("std");
const glfw = @import("glfw");

const App = @import("App.zig");
const cli_args = @import("cli_args.zig");
const tracy = @import("tracy/tracy.zig");
const Config = @import("config.zig").Config;

pub fn main() !void {
    var general_purpose_allocator = std.heap.GeneralPurposeAllocator(.{}){};
    const gpa = general_purpose_allocator.allocator();
    defer _ = general_purpose_allocator.deinit();

    // If we're tracing, then wrap memory so we can trace allocations
    const alloc = if (!tracy.enabled) gpa else tracy.allocator(gpa, null).allocator();

    // Parse the config from the CLI args
    const config = config: {
        var result: Config = .{};
        var iter = try std.process.argsWithAllocator(alloc);
        defer iter.deinit();
        try cli_args.parse(Config, &result, &iter);
        break :config result;
    };

    // Initialize glfw
    try glfw.init(.{});
    defer glfw.terminate();

    // Run our app
    var app = try App.init(alloc, &config);
    defer app.deinit();
    try app.run();
}

// Required by tracy/tracy.zig to enable/disable tracy support.
pub fn tracy_enabled() bool {
    return options.tracy_enabled;
}

test {
    _ = @import("Atlas.zig");
    _ = @import("FontAtlas.zig");
    _ = @import("Grid.zig");
    _ = @import("Pty.zig");
    _ = @import("Command.zig");
    _ = @import("TempDir.zig");
    _ = @import("terminal/Terminal.zig");

    // Libraries
    _ = @import("segmented_pool.zig");
    _ = @import("libuv/main.zig");
    _ = @import("terminal/main.zig");

    // TODO
    _ = @import("config.zig");
    _ = @import("cli_args.zig");
}
