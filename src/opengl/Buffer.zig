const Buffer = @This();

const std = @import("std");
const c = @import("c.zig");
const errors = @import("errors.zig");

id: c.GLuint,

/// Binding is a bound buffer. By using this for functions that operate
/// on bound buffers, you can easily defer unbinding and in safety-enabled
/// modes verify that unbound buffers are never accessed.
pub const Binding = struct {
    target: c.GLenum,

    /// Sets the data of this bound buffer. The data can be any array-like
    /// type. The size of the data is automatically determined based on the type.
    pub inline fn setData(
        b: Binding,
        data: anytype,
        usage: c.GLenum,
    ) !void {
        // Determine the size and pointer to the given data.
        const info: struct {
            size: isize,
            ptr: *const anyopaque,
        } = switch (@typeInfo(@TypeOf(data))) {
            .Array => |ary| .{
                .size = @sizeOf(ary.child) * ary.len,
                .ptr = &data,
            },
            .Pointer => |ptr| switch (ptr.size) {
                .One => .{
                    .size = @sizeOf(ptr.child) * data.len,
                    .ptr = data,
                },
                .Slice => .{
                    .size = @sizeOf(ptr.child) * data.len,
                    .ptr = data.ptr,
                },
                else => {
                    std.log.err("invalid buffer data pointer size: {}", .{ptr.size});
                    unreachable;
                },
            },
            else => {
                std.log.err("invalid buffer data type: {s}", .{@tagName(@typeInfo(@TypeOf(data)))});
                unreachable;
            },
        };

        c.glBufferData(b.target, info.size, info.ptr, usage);
        try errors.getError();
    }

    pub inline fn enableVertexAttribArray(_: Binding, idx: c.GLuint) !void {
        c.glEnableVertexAttribArray(idx);
    }

    pub inline fn vertexAttribPointer(
        _: Binding,
        idx: c.GLuint,
        size: c.GLint,
        typ: c.GLenum,
        normalized: bool,
        stride: c.GLsizei,
        ptr: ?*const anyopaque,
    ) !void {
        const normalized_c: c.GLboolean = if (normalized) c.GL_TRUE else c.GL_FALSE;
        c.glVertexAttribPointer(idx, size, typ, normalized_c, stride, ptr);
        try errors.getError();
    }

    pub inline fn unbind(b: *Binding) void {
        c.glBindBuffer(b.target, 0);
        b.* = undefined;
    }
};

/// Create a single buffer.
pub inline fn create() !Buffer {
    var vbo: c.GLuint = undefined;
    c.glGenBuffers(1, &vbo);
    return Buffer{ .id = vbo };
}

/// glBindBuffer
pub inline fn bind(v: Buffer, target: c.GLenum) !Binding {
    c.glBindBuffer(target, v.id);
    return Binding{ .target = target };
}

pub inline fn destroy(v: Buffer) void {
    c.glDeleteBuffers(1, &v.id);
}
