const Texture = @This();

const std = @import("std");
const c = @import("c.zig");
const errors = @import("errors.zig");

id: c.GLuint,

pub inline fn active(target: c.GLenum) !void {
    c.glActiveTexture(target);
}

pub const Binding = struct {
    target: c.GLenum,

    pub inline fn unbind(b: *Binding) void {
        c.glBindTexture(b.target, 0);
        b.* = undefined;
    }

    pub fn generateMipmap(b: Binding) void {
        c.glGenerateMipmap(b.target);
    }

    pub fn parameter(b: Binding, name: c.GLenum, value: anytype) !void {
        switch (@TypeOf(value)) {
            c.GLint => c.glTexParameteri(b.target, name, value),
            else => unreachable,
        }
    }

    pub fn image2D(
        b: Binding,
        level: c.GLint,
        internal_format: c.GLint,
        width: c.GLsizei,
        height: c.GLsizei,
        border: c.GLint,
        format: c.GLenum,
        typ: c.GLenum,
        data: *const anyopaque,
    ) !void {
        c.glTexImage2D(
            b.target,
            level,
            internal_format,
            width,
            height,
            border,
            format,
            typ,
            data,
        );
    }
};

/// Create a single texture.
pub inline fn create() !Texture {
    var id: c.GLuint = undefined;
    c.glGenTextures(1, &id);
    return Texture{ .id = id };
}

/// glBindTexture
pub inline fn bind(v: Texture, target: c.GLenum) !Binding {
    c.glBindTexture(target, v.id);
    return Binding{ .target = target };
}

pub inline fn destroy(v: Texture) void {
    c.glDeleteTextures(1, &v.id);
}
