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

// The main event loop for the application. The user data of this loop
// is always the allocator used to create the loop. This is a convenience
// so that users of the loop always have an allocator.
loop: libuv.Loop,

/// Initialize the main app instance. This creates the main window, sets
/// up the renderer state, compiles the shaders, etc. This is the primary
/// "startup" logic.
pub fn init(alloc: Allocator) !App {
    // Create the event loop
    var loop = try libuv.Loop.init(alloc);
    errdefer loop.deinit(alloc);

    // We always store allocator pointer on the loop data so that
    // handles can use our global allocator.
    const allocPtr = try alloc.create(Allocator);
    errdefer alloc.destroy(allocPtr);
    allocPtr.* = alloc;
    loop.setData(allocPtr);

    // Create the window
    var window = try Window.create(alloc, loop);
    errdefer window.destroy();

    return App{
        .alloc = alloc,
        .window = window,
        .loop = loop,
    };
}

pub fn deinit(self: *App) void {
    self.window.destroy();

    // Run the loop one more time, because destroying our other things
    // like windows usually cancel all our event loop stuff and we need
    // one more run through to finalize all the closes.
    _ = self.loop.run(.default) catch unreachable;

    // Dealloc our allocator copy
    self.alloc.destroy(self.loop.getData(Allocator).?);

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

    // Notify the embedder to stop. We purposely do NOT wait for `join`
    // here because handles with long timeouts may cause this to take a long
    // time. We're exiting the app anyways if we're here so we let the OS
    // clean up the threads.
    defer embed.stop();

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
}
