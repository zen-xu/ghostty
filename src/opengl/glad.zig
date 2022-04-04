const c = @import("c.zig");

/// Initialize Glad. This is guaranteed to succeed if no errors are returned.
/// The getProcAddress param is an anytype so that we can accept multiple
/// forms of the function depending on what we're interfacing with.
pub fn load(getProcAddress: anytype) !c_int {
    const res = switch (@TypeOf(getProcAddress)) {
        // glfw
        fn ([*:0]const u8) callconv(.C) ?fn () callconv(.C) void => c.gladLoadGL(@ptrCast(
            fn ([*c]const u8) callconv(.C) ?fn () callconv(.C) void,
            getProcAddress,
        )),

        // try as-is. If this introduces a compiler error, then add a new case.
        else => c.gladLoadGL(getProcAddress),
    };
    if (res == 0) return error.GLInitFailed;
    return res;
}

pub fn versionMajor(res: c_int) c_uint {
    // The intcast here is due to translate-c weirdness
    return c.GLAD_VERSION_MAJOR(@intCast(c_uint, res));
}

pub fn versionMinor(res: c_int) c_uint {
    // The intcast here is due to translate-c weirdness
    return c.GLAD_VERSION_MINOR(@intCast(c_uint, res));
}
