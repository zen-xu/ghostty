//! App is the primary GUI application for ghostty. This builds the window,
//! sets up the renderer, etc. The primary run loop is started by calling
//! the "run" function.
const App = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;
const glfw = @import("glfw");
const Window = @import("Window.zig");
const libuv = @import("libuv/main.zig");

const log = std.log.scoped(.app);

/// General purpose allocator
alloc: Allocator,

/// The primary window for the application. We currently support only
/// single window operations.
window: *Window,

// The main event loop for the application.
loop: libuv.Loop,

/// Initialize the main app instance. This creates the main window, sets
/// up the renderer state, compiles the shaders, etc. This is the primary
/// "startup" logic.
pub fn init(alloc: Allocator) !App {
    // Create the window
    var window = try Window.create(alloc);
    errdefer window.destroy();

    // Create the event loop
    var loop = try libuv.Loop.init(alloc);
    errdefer loop.deinit(alloc);

    return App{
        .alloc = alloc,
        .window = window,
        .loop = loop,
    };
}

pub fn deinit(self: *App) void {
    self.window.destroy();
    self.loop.deinit(self.alloc);
    self.* = undefined;
}

pub fn run(self: App) !void {
    // We are embedding two event loops: glfw and libuv. To do this, we
    // create a separate thread that watches for libuv events and notifies
    // glfw to wake up so we can run the libuv tick.
    var embed = try libuv.Embed.init(self.alloc, self.loop, (struct {
        fn callback() void {
            glfw.postEmptyEvent() catch unreachable;
        }
    }).callback);
    defer embed.deinit(self.alloc);
    try embed.start();
    errdefer embed.stop();

    // We need at least one handle in the event loop at all times so
    // that the loop doesn't spin 100% CPU.
    var timer = try libuv.Timer.init(self.alloc, self.loop);
    defer timer.deinit(self.alloc);
    try timer.start((struct {
        fn callback(_: libuv.Timer) void {}
    }).callback, 5000, 5000);

    while (!self.window.shouldClose()) {
        try self.window.run();

        // Block for any glfw events. This may also be an "empty" event
        // posted by the libuv watcher so that we trigger a libuv loop tick.
        try glfw.waitEvents();

        // Run the libuv loop
        try embed.loopRun();
    }

    // CLose our timer so that we can cleanly close the loop.
    timer.close(null);
    _ = try self.loop.run(.default);

    // Notify the embedder to stop. We purposely do NOT wait for `join`
    // here because handles with long timeouts may cause this to take a long
    // time. We're exiting the app anyways if we're here so we let the OS
    // clean up the threads.
    embed.stop();
}
