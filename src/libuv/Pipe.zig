//! Pipe handles provide an abstraction over streaming files on Unix
//! (including local domain sockets, pipes, and FIFOs) and named pipes on
//! Windows.
const Pipe = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;
const testing = std.testing;
const c = @import("c.zig");
const errors = @import("error.zig");
const Loop = @import("Loop.zig");
const Handle = @import("handle.zig").Handle;
const Stream = @import("stream.zig").Stream;

handle: *c.uv_pipe_t,

pub usingnamespace Handle(Pipe);
pub usingnamespace Stream(Pipe);

/// Valid flags for pipe.
pub const Flags = packed struct {
    _ignore: u6 = 0,
    nonblock: bool = false, // UV_NONBLOCK_PIPE = 0x40
    _ignore_high: u1 = 0,

    pub inline fn toInt(self: Flags, comptime IntType: type) IntType {
        return @intCast(IntType, @bitCast(u8, self));
    }

    test "Flags: expected value" {
        const f: Flags = .{ .nonblock = true };
        try testing.expectEqual(c.UV_NONBLOCK_PIPE, f.toInt(c_int));
    }
};

/// Create a pair of connected pipe handles. Data may be written to fds[1] and
/// read from fds[0]. The resulting handles can be passed to uv_pipe_open,
/// used with uv_spawn, or for any other purpose.
pub fn pipe(read_flags: Flags, write_flags: Flags) ![2]c.uv_file {
    var res: [2]c.uv_file = undefined;
    try errors.convertError(c.uv_pipe(
        &res,
        read_flags.toInt(c_int),
        write_flags.toInt(c_int),
    ));
    return res;
}

pub fn init(alloc: Allocator, loop: Loop, ipc: bool) !Pipe {
    var handle = try alloc.create(c.uv_pipe_t);
    errdefer alloc.destroy(handle);
    try errors.convertError(c.uv_pipe_init(loop.loop, handle, @boolToInt(ipc)));
    return Pipe{ .handle = handle };
}

pub fn deinit(self: *Pipe, alloc: Allocator) void {
    alloc.destroy(self.handle);
    self.* = undefined;
}

/// Open an existing file descriptor or HANDLE as a pipe.
pub fn open(self: Pipe, file: c.uv_file) !void {
    try errors.convertError(c.uv_pipe_open(self.handle, file));
}

test {
    _ = Flags;
}

test "Pipe" {
    const pipes = try pipe(.{ .nonblock = true }, .{ .nonblock = true });
    defer std.os.close(pipes[1]);

    var loop = try Loop.init(testing.allocator);
    defer loop.deinit(testing.allocator);
    var h = try init(testing.allocator, loop, false);
    defer h.deinit(testing.allocator);

    try h.open(pipes[0]);
    try testing.expect(try h.isReadable());
    try testing.expect(!try h.isWritable());

    h.close(null);
    _ = try loop.run(.default);
}
