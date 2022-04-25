//! Tty handles represent a stream for the console.
const Tty = @This();

const std = @import("std");
const fd_t = std.os.fd_t;
const Allocator = std.mem.Allocator;
const testing = std.testing;
const c = @import("c.zig");
const errors = @import("error.zig");
const Loop = @import("Loop.zig");
const Handle = @import("handle.zig").Handle;
const Stream = @import("stream.zig").Stream;
const Pty = @import("../Pty.zig");

handle: *c.uv_tty_t,

pub usingnamespace Handle(Tty);
pub usingnamespace Stream(Tty);

pub fn init(alloc: Allocator, loop: Loop, fd: fd_t) !Tty {
    var tty = try alloc.create(c.uv_tty_t);
    errdefer alloc.destroy(tty);
    try errors.convertError(c.uv_tty_init(loop.loop, tty, fd, 0));
    return Tty{ .handle = tty };
}

pub fn deinit(self: *Tty, alloc: Allocator) void {
    alloc.destroy(self.handle);
    self.* = undefined;
}

test "Tty" {
    var pty = try Pty.open(.{
        .ws_row = 20,
        .ws_col = 80,
        .ws_xpixel = 0,
        .ws_ypixel = 0,
    });
    defer pty.deinit();

    var loop = try Loop.init(testing.allocator);
    defer loop.deinit(testing.allocator);
    var tty = try init(testing.allocator, loop, pty.slave);
    defer tty.deinit(testing.allocator);

    try testing.expect(try tty.isReadable());
    try testing.expect(try tty.isWritable());

    tty.close(null);
    _ = try loop.run(.default);
}
