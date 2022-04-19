//! App is the primary GUI application for ghostty. This builds the window,
//! sets up the renderer, etc. The primary run loop is started by calling
//! the "run" function.
const App = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;
const Window = @import("Window.zig");

/// General purpose allocator
alloc: Allocator,

/// The primary window for the application. We currently support only
/// single window operations.
window: *Window,

/// Initialize the main app instance. This creates the main window, sets
/// up the renderer state, compiles the shaders, etc. This is the primary
/// "startup" logic.
pub fn init(alloc: Allocator) !App {
    // Create the window
    const window = try Window.create(alloc);

    return App{
        .alloc = alloc,
        .window = window,
    };
}

pub fn deinit(self: *App) void {
    self.window.destroy();
    self.* = undefined;
}

pub fn run(self: App) !void {
    try self.window.run();
}
