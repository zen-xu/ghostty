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
    handle: c.GLuint,

    pub fn create(typ: c.GLenum) Error!Shader {
        const handle = c.glCreateShader(typ);
        if (handle == 0) {
            try mustError();
            unreachable;
        }

        log.debug("shader created id={}", .{handle});
        return Shader{ .handle = handle };
    }

    /// Set the source and compile a shader.
    pub fn setSourceAndCompile(s: Shader, source: [:0]const u8) !void {
        c.glShaderSource(s.handle, 1, &@ptrCast([*c]const u8, source), null);
        c.glCompileShader(s.handle);

        // Check if compilation succeeded
        var success: c_int = undefined;
        c.glGetShaderiv(s.handle, c.GL_COMPILE_STATUS, &success);
        if (success == c.GL_TRUE) return;
        log.err("shader compilation failure handle={} message={s}", .{
            s.handle,
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
        c.glGetShaderInfoLog(s.handle, msg.len, null, &msg);
        return msg;
    }

    pub fn destroy(s: Shader) void {
        assert(s.handle != 0);
        c.glDeleteShader(s.handle);
        log.debug("shader destroyed id={}", .{s.handle});
    }
};
