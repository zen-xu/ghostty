const c = @import("c.zig");

const Loop = @import("Loop.zig");
const errors = @import("error.zig");

/// Returns a struct that has all the shared stream functions for the
/// given stream type T. The type T must have a field named "handle".
/// This is expected to be used with usingnamespace to add the shared
/// stream functions to other handle types.
pub fn Stream(comptime T: type) type {
    // 1. T should be a struct
    // 2. First field should be the handle pointer

    return struct {
        // note: this has to be here: https://github.com/ziglang/zig/issues/11367
        const tInfo = @typeInfo(T).Struct;
        const HandleType = tInfo.fields[0].field_type;

        /// Returns 1 if the stream is readable, 0 otherwise.
        pub fn isReadable(self: T) !bool {
            const res = c.uv_is_readable(@ptrCast(*c.uv_stream_t, self.handle));
            try errors.convertError(res);
            return res > 0;
        }

        /// Returns 1 if the stream is writable, 0 otherwise.
        pub fn isWritable(self: T) !bool {
            const res = c.uv_is_writable(@ptrCast(*c.uv_stream_t, self.handle));
            try errors.convertError(res);
            return res > 0;
        }
    };
}
