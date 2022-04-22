//! Timer handles are used to schedule callbacks to be called in the future.
const Timer = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;
const testing = std.testing;
const c = @import("c.zig");
const errors = @import("error.zig");
const Loop = @import("Loop.zig");
const Handle = @import("handle.zig").Handle;

handle: *c.uv_timer_t,

pub usingnamespace Handle(Timer);

pub fn init(alloc: Allocator, loop: Loop) !Timer {
    var timer = try alloc.create(c.uv_timer_t);
    errdefer alloc.destroy(timer);
    try errors.convertError(c.uv_timer_init(loop.loop, timer));
    return Timer{ .handle = timer };
}

pub fn deinit(self: *Timer, alloc: Allocator) void {
    alloc.destroy(self.handle);
    self.* = undefined;
}

/// Start the timer. timeout and repeat are in milliseconds.
///
/// If timeout is zero, the callback fires on the next event loop iteration.
/// If repeat is non-zero, the callback fires first after timeout milliseconds
/// and then repeatedly after repeat milliseconds.
pub fn start(
    self: Timer,
    comptime cb: fn (Timer) void,
    timeout: u64,
    repeat: u64,
) !void {
    const Wrapper = struct {
        pub fn callback(handle: [*c]c.uv_timer_t) callconv(.C) void {
            const newSelf: Timer = .{ .handle = handle };
            @call(.{ .modifier = .always_inline }, cb, .{newSelf});
        }
    };

    try errors.convertError(c.uv_timer_start(
        self.handle,
        Wrapper.callback,
        timeout,
        repeat,
    ));
}

/// Stop the timer, the callback will not be called anymore.
pub fn stop(self: Timer) !void {
    try errors.convertError(c.uv_timer_stop(self.handle));
}

test "Timer" {
    var loop = try Loop.init(testing.allocator);
    defer loop.deinit(testing.allocator);
    var timer = try init(testing.allocator, loop);
    defer timer.deinit(testing.allocator);

    var called: bool = false;
    timer.setData(&called);
    try timer.start((struct {
        fn callback(t: Timer) void {
            t.getData(bool).?.* = true;
            t.close(null);
        }
    }).callback, 10, 1000);

    _ = try loop.run(.default);

    try testing.expect(called);
}

test "Timer: close callback" {
    var loop = try Loop.init(testing.allocator);
    defer loop.deinit(testing.allocator);
    var timer = try init(testing.allocator, loop);
    defer timer.deinit(testing.allocator);

    var data: u8 = 42;
    timer.setData(&data);
    timer.close((struct {
        fn callback(v: Timer) void {
            var dataPtr = v.getData(u8).?;
            dataPtr.* = 24;
        }
    }).callback);
    _ = try loop.run(.default);

    try testing.expectEqual(@as(u8, 24), data);
}
