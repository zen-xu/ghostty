const std = @import("std");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;
const libuv = @import("libuv/main.zig");

/// A coalescing timer that forces a run after a certain maximum time
/// since the last run. This is used for example by the renderer to try
/// to render at a high FPS but gracefully fall back under high IO load so
/// that we can process more data and increase throughput.
pub fn MaxTimer(comptime cb: fn (*libuv.Timer) void) type {
    return struct {
        const Self = @This();

        /// The underlying libuv timer.
        timer: libuv.Timer,

        /// The maximum time between timer calls. This is best effort based on
        /// event loop load. If the event loop is busy, the timer will be run on
        /// the next available tick.
        max: u64,

        /// The fastest the timer will ever run.
        min: u64,

        /// The last time this timer ran.
        last: u64 = 0,

        pub fn init(
            loop: libuv.Loop,
            data: ?*anyopaque,
            min: u64,
            max: u64,
        ) !Self {
            const alloc = loop.getData(Allocator).?.*;
            var timer = try libuv.Timer.init(alloc, loop);
            timer.setData(data);

            // The maximum time can't be less than the interval otherwise this
            // will just constantly fire.
            if (max < min) return error.MaxShorterThanTimer;
            return Self{
                .timer = timer,
                .min = min,
                .max = max,
            };
        }

        pub fn deinit(self: *Self) void {
            self.timer.close((struct {
                fn callback(t: *libuv.Timer) void {
                    const alloc = t.loop().getData(Allocator).?.*;
                    t.deinit(alloc);
                }
            }).callback);
            self.* = undefined;
        }

        /// This should be called from the callback to update the last called time.
        pub fn tick(self: *Self) void {
            self.timer.loop().updateTime();
            self.last = self.timer.loop().now();
            self.timer.stop() catch unreachable;
        }

        /// Schedule the timer to run. If the timer is not started, it'll
        /// run on the next min tick. If the timer is started, this will
        /// delay the timer up to max time since the last run.
        pub fn schedule(self: *Self) !void {
            // If the timer hasn't been started, start it now and schedule
            // a tick as soon as possible.
            if (!try self.timer.isActive()) {
                try self.timer.start(cb, self.min, self.min);
                return;
            }

            // If we are past the max time, we run the timer now.
            try self.timer.stop();
            self.timer.loop().updateTime();
            if (self.timer.loop().now() - self.last > self.max) {
                @call(.{ .modifier = .always_inline }, cb, .{&self.timer});
                return;
            }

            // We still have time, restart the timer so that it is min time away.
            try self.timer.start(cb, self.min, 0);
        }
    };
}
