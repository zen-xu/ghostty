const VertexArray = @This();

const c = @import("c.zig");

id: c.GLuint,

/// Create a single vertex array object.
pub inline fn create() !VertexArray {
    var vao: c.GLuint = undefined;
    c.glGenVertexArrays(1, &vao);
    return VertexArray{ .id = vao };
}

// Unbind any active vertex array.
pub inline fn unbind() !void {
    c.glBindVertexArray(0);
}

/// glBindVertexArray
pub inline fn bind(v: VertexArray) !void {
    c.glBindVertexArray(v.id);
}

pub inline fn destroy(v: VertexArray) void {
    c.glDeleteVertexArrays(1, &v.id);
}
