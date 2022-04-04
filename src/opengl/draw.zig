const c = @import("c.zig");
const errors = @import("errors.zig");

pub fn clearColor(r: f32, g: f32, b: f32, a: f32) void {
    c.glClearColor(r, g, b, a);
}

pub fn clear(mask: c.GLbitfield) void {
    c.glClear(mask);
}

pub fn drawArrays(mode: c.GLenum, first: c.GLint, count: c.GLsizei) !void {
    c.glDrawArrays(mode, first, count);
    try errors.getError();
}

pub fn viewport(x: c.GLint, y: c.GLint, width: c.GLsizei, height: c.GLsizei) !void {
    c.glViewport(x, y, width, height);
}

pub fn pixelStore(mode: c.GLenum, value: anytype) !void {
    switch (@typeInfo(@TypeOf(value))) {
        .ComptimeInt, .Int => c.glPixelStorei(mode, value),
        else => unreachable,
    }
    try errors.getError();
}
