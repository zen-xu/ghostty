const Buffer = @This();

const std = @import("std");
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
    data: anytype,
    usage: c.GLenum,
) !void {
    // Maybe one day in debug mode we can validate that this buffer
    // is currently bound.
    _ = v;

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

    c.glBufferData(target, info.size, info.ptr, usage);
    try errors.getError();
}

pub inline fn destroy(v: Buffer) void {
    c.glDeleteBuffers(1, &v.id);
}
