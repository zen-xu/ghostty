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
