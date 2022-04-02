const Buffer = @This();

const c = @import("c.zig");
const errors = @import("errors.zig");

id: c.GLuint,

/// Create a single buffer.
pub inline fn create() !Buffer {
    var vbo: c.GLuint = undefined;
    c.glGenBuffers(1, &vbo);
    return Buffer{ .id = vbo };
}

// Unbind any active vertex array.
pub inline fn unbind(target: c.GLenum) !void {
    c.glBindBuffer(target, 0);
}

/// glBindBuffer
pub inline fn bind(v: Buffer, target: c.GLenum) !void {
    c.glBindBuffer(target, v.id);
}

pub inline fn setData(
    v: Buffer,
    target: c.GLenum,
    data: []const f32,
    usage: c.GLenum,
) !void {
    // Maybe one day in debug mode we can validate that this buffer
    // is currently bound.
    _ = v;

    // Determine the per-element size. This is all comptime-computed.
    const dataInfo = @typeInfo(@TypeOf(data));
    const size: usize = switch (dataInfo) {
        .Pointer => |ptr| switch (ptr.size) {
            .Slice => @sizeOf(ptr.child),
            else => unreachable,
        },
        else => unreachable,
    };

    c.glBufferData(
        target,
        @intCast(isize, size * data.len),
        data.ptr,
        usage,
    );
    try errors.getError();
}

pub inline fn destroy(v: Buffer) void {
    c.glDeleteBuffers(1, &v.id);
}
