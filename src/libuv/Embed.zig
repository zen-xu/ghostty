//! This has a helper for embedding libuv in another event loop.
//! This is an extension of libuv and not a helper built-in to libuv
//! itself, although it uses official APIs of libuv to enable the
//! functionality.

const Embed = @This();

const std = @import("std");
const builtin = @import("builtin");
const testing = std.testing;
const Allocator = std.mem.Allocator;
const Loop = @import("Loop.zig");
const Sem = @import("Sem.zig");
const Thread = @import("Thread.zig");

const TerminateAtomic = std.atomic.Atomic(bool);

loop: Loop,
sem: Sem,
terminate: TerminateAtomic,
callback: fn () void,
thread: ?Thread,

/// Initialize a new embedder. The callback is called when libuv should
/// tick. The callback should be as fast as possible.
pub fn init(alloc: Allocator, loop: Loop, callback: fn () void) !Embed {
    return Embed{
        .loop = loop,
        .sem = try Sem.init(alloc, 0),
        .terminate = TerminateAtomic.init(false),
        .callback = callback,
        .thread = null,
    };
}

/// Deinit the embed struct. This will not automatically terminate
/// the embed thread. You must call stop manually.
pub fn deinit(self: *Embed, alloc: Allocator) void {
    self.sem.deinit(alloc);
    self.* = undefined;
}

/// Start the thread that runs the embed logic and calls callback
/// when the libuv loop should tick. This must only be called once.
pub fn start(self: *Embed) !void {
    self.thread = try Thread.initData(self, Embed.threadMain);
}

/// Stop stops the embed thread and blocks until the thread joins.
pub fn stop(self: *Embed) void {
    if (self.thread == null) return;

    // Mark that we want to terminate
    self.terminate.store(true, .SeqCst);

    // Post to the semaphore to ensure that any waits are processed.
    self.sem.post();
}

/// Wait for the thread backing the embedding to end.
pub fn join(self: *Embed) !void {
    if (self.thread) |*thr| {
        try thr.join();
        self.thread = null;
    }
}

/// loopRun runs the next tick of the libuv event loop. This should be
/// called by the main loop thread as a result of callback making some
/// signal. This should NOT be called from callback.
pub fn loopRun(self: Embed) !void {
    _ = try self.loop.run(.nowait);
    self.sem.post();
}

fn threadMain(self: *Embed) void {
    while (self.terminate.load(.SeqCst) == false) {
        const fd = self.loop.backendFd() catch unreachable;
        const timeout = self.loop.backendTimeout();
        switch (builtin.os.tag) {
            // epoll
            .linux => {
                var ev: [1]std.os.linux.epoll_event = undefined;
                while (std.os.epoll_wait(fd, &ev, timeout) == -1) {}
            },

            else => @compileError("unsupported libuv Embed platform"),
        }

        // Call our trigger
        self.callback();

        // Wait for libuv to run a tick
        self.sem.wait();
    }
}

test "Embed" {
    var loop = try Loop.init(testing.allocator);
    defer loop.deinit(testing.allocator);

    var embed = try init(testing.allocator, loop, (struct {
        fn callback() void {}
    }).callback);
    defer embed.deinit(testing.allocator);

    // This just tests that the thread can start and then stop.
    // It doesn't do much else at the moment
    try embed.start();
    embed.stop();
    try embed.join();
}
