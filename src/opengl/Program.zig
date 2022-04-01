const Program = @This();

const std = @import("std");
const assert = std.debug.assert;
const log = std.log.scoped(.opengl);

const c = @import("c.zig");
const Shader = @import("Shader.zig");
const errors = @import("errors.zig");

id: c.GLuint,

pub fn create() !Program {
    const id = c.glCreateProgram();
    if (id == 0) try errors.mustError();

    log.debug("program created id={}", .{id});
    return Program{ .id = id };
}

pub fn attachShader(p: Program, s: Shader) !void {
    c.glAttachShader(p.id, s.id);
    try errors.getError();
}

pub fn link(p: Program) !void {
    c.glLinkProgram(p.id);

    // Check if linking succeeded
    var success: c_int = undefined;
    c.glGetProgramiv(p.id, c.GL_LINK_STATUS, &success);
    if (success == c.GL_TRUE) {
        log.debug("program linked id={}", .{p.id});
        return;
    }

    log.err("program link failure id={} message={s}", .{
        p.id,
        std.mem.sliceTo(&p.getInfoLog(), 0),
    });
    return error.CompileFailed;
}

/// getInfoLog returns the info log for this program. This attempts to
/// keep the log fully stack allocated and is therefore limited to a max
/// amount of elements.
//
// NOTE(mitchellh): we can add a dynamic version that uses an allocator
// if we ever need it.
pub fn getInfoLog(s: Program) [512]u8 {
    var msg: [512]u8 = undefined;
    c.glGetProgramInfoLog(s.id, msg.len, null, &msg);
    return msg;
}

pub fn destroy(p: Program) void {
    assert(p.id != 0);
    c.glDeleteProgram(p.id);
    log.debug("program destroyed id={}", .{p.id});
}
