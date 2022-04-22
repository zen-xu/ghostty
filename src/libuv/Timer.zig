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

test "Timer" {
    var loop = try Loop.init(testing.allocator);
    defer loop.deinit(testing.allocator);
    var timer = try init(testing.allocator, loop);
    defer timer.deinit(testing.allocator);
    timer.close(null);
    _ = try loop.run(.default);
}

test "Timer: close callback" {
    var loop = try Loop.init(testing.allocator);
    defer loop.deinit(testing.allocator);
    var timer = try init(testing.allocator, loop);
    defer timer.deinit(testing.allocator);

    var data: u8 = 42;
    timer.setData(&data);
    timer.close((struct {
        fn callback(v: *Timer) void {
            var dataPtr = v.getData(u8).?;
            dataPtr.* = 24;
        }
    }).callback);
    _ = try loop.run(.default);

    try testing.expectEqual(@as(u8, 24), data);
}
