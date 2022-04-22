const c = @import("c.zig");

/// Returns a struct that has all the shared handle functions for the
/// given handle type T. The type T must have a field named "handle".
/// This is expected to be used with usingnamespace to add the shared
/// handler functions to other handle types.
pub fn Handle(comptime T: type) type {
    // 1. T should be a struct
    // 2. First field should be the handle pointer
    const tInfo = @typeInfo(T).Struct;
    const HandleType = tInfo.fields[0].field_type;

    return struct {
        // Request handle to be closed. close_cb will be called asynchronously
        // after this call. This MUST be called on each handle before memory
        // is released. Moreover, the memory can only be released in close_cb
        // or after it has returned.
        //
        // Handles that wrap file descriptors are closed immediately but
        // close_cb will still be deferred to the next iteration of the event
        // loop. It gives you a chance to free up any resources associated with
        // the handle.
        //
        // In-progress requests, like uv_connect_t or uv_write_t, are cancelled
        // and have their callbacks called asynchronously with status=UV_ECANCELED.
        pub fn close(self: T, comptime cb: ?fn (T) void) void {
            const cbParam = if (cb) |f|
                (struct {
                    pub fn callback(handle: [*c]c.uv_handle_t) callconv(.C) void {
                        // We get the raw handle, so we need to reconstruct
                        // the T. This is mutable because a lot of the libuv APIs
                        // are non-const but modifying it makes no sense.
                        const param: T = .{ .handle = @ptrCast(HandleType, handle) };
                        @call(.{ .modifier = .always_inline }, f, .{param});
                    }
                }).callback
            else
                null;

            c.uv_close(@ptrCast(*c.uv_handle_t, self.handle), cbParam);
        }

        /// Sets handle->data to data.
        pub fn setData(self: T, pointer: ?*anyopaque) void {
            c.uv_handle_set_data(
                @ptrCast(*c.uv_handle_t, self.handle),
                pointer,
            );
        }

        /// Returns handle->data.
        pub fn getData(self: T, comptime DT: type) ?*DT {
            return if (c.uv_handle_get_data(@ptrCast(*c.uv_handle_t, self.handle))) |ptr|
                @ptrCast(?*DT, @alignCast(@alignOf(DT), ptr))
            else
                null;
        }
    };
}
