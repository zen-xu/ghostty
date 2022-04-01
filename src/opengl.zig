const std = @import("std");
const assert = std.debug.assert;
const log = std.log.scoped(.opengl);

/// This can be used to access the OpenGL headers.
pub const c = @import("c.zig");

pub const Error = error{
    InvalidEnum,
    InvalidValue,
    InvalidOperation,
    InvalidFramebufferOperation,
    OutOfMemory,

    Unknown,
};

/// getError returns the error (if any) from the last OpenGL operation.
pub fn getError() Error!void {
    return switch (c.glGetError()) {
        c.GL_NO_ERROR => {},
        c.GL_INVALID_ENUM => Error.InvalidEnum,
        c.GL_INVALID_VALUE => Error.InvalidValue,
        c.GL_INVALID_OPERATION => Error.InvalidOperation,
        c.GL_INVALID_FRAMEBUFFER_OPERATION => Error.InvalidFramebufferOperation,
        c.GL_OUT_OF_MEMORY => Error.OutOfMemory,
        else => Error.Unknown,
    };
}

/// mustError just calls getError but always results in an error being returned.
/// If getError has no error, then Unknown is returned.
fn mustError() Error!void {
    try getError();
    return Error.Unknown;
}

pub const Shader = struct {
    id: c.GLuint,

    pub fn create(typ: c.GLenum) Error!Shader {
        const id = c.glCreateShader(typ);
        if (id == 0) {
            try mustError();
            unreachable;
        }

        log.debug("shader created id={}", .{id});
        return Shader{ .id = id };
    }

    /// Set the source and compile a shader.
    pub fn setSourceAndCompile(s: Shader, source: [:0]const u8) !void {
        c.glShaderSource(s.id, 1, &@ptrCast([*c]const u8, source), null);
        c.glCompileShader(s.id);

        // Check if compilation succeeded
        var success: c_int = undefined;
        c.glGetShaderiv(s.id, c.GL_COMPILE_STATUS, &success);
        if (success == c.GL_TRUE) return;
        log.err("shader compilation failure id={} message={s}", .{
            s.id,
            std.mem.sliceTo(&s.getInfoLog(), 0),
        });
        return error.CompileFailed;
    }

    /// getInfoLog returns the info log for this shader. This attempts to
    /// keep the log fully stack allocated and is therefore limited to a max
    /// amount of elements.
    //
    // NOTE(mitchellh): we can add a dynamic version that uses an allocator
    // if we ever need it.
    pub fn getInfoLog(s: Shader) [512]u8 {
        var msg: [512]u8 = undefined;
        c.glGetShaderInfoLog(s.id, msg.len, null, &msg);
        return msg;
    }

    pub fn destroy(s: Shader) void {
        assert(s.id != 0);
        c.glDeleteShader(s.id);
        log.debug("shader destroyed id={}", .{s.id});
    }
};

pub const Program = struct {
    id: c.GLuint,

    pub fn create() !Program {
        const id = c.glCreateProgram();
        if (id == 0) try mustError();

        log.debug("program created id={}", .{id});
        return Program{ .id = id };
    }

    pub fn attachShader(p: Program, s: Shader) !void {
        c.glAttachShader(p.id, s.id);
        try getError();
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
};
