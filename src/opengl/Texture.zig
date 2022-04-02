const Texture = @This();

const std = @import("std");
const c = @import("c.zig");
const errors = @import("errors.zig");

id: c.GLuint,

pub const Binding = struct {
    target: c.GLenum,

    pub inline fn unbind(b: *Binding) void {
        c.glBindTexture(b.target, 0);
        b.* = undefined;
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
