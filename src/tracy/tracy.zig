//! Tracy API.
//!
//! Forked and modified from https://github.com/SpexGuy/Zig-Tracy
const std = @import("std");
const builtin = @import("builtin");
const root = @import("root");
const SourceLocation = std.builtin.SourceLocation;

// Tracy is enabled if the root function tracy_enabled returns true.
pub const enabled = @import("root").tracy_enabled();

// Bring in the correct implementation depending on if we're enabled or not.
// See Impl for all the real doc comments.
pub usingnamespace if (enabled) Impl else Noop;

const Impl = struct {
    const c = @cImport({
        @cDefine("TRACY_ENABLE", "");
        @cInclude("TracyC.h");
    });

    const has_callstack_support = @hasDecl(c, "TRACY_HAS_CALLSTACK") and @hasDecl(c, "TRACY_CALLSTACK");
    const callstack_enabled: c_int = if (has_callstack_support) c.TRACY_CALLSTACK else 0;

    pub const ZoneCtx = struct {
        zone: c.___tracy_c_zone_context,

        pub inline fn text(self: ZoneCtx, val: []const u8) void {
            c.___tracy_emit_zone_text(self.zone, val.ptr, val.len);
        }

        pub inline fn name(self: ZoneCtx, val: []const u8) void {
            c.___tracy_emit_zone_name(self.zone, val.ptr, val.len);
        }

        pub inline fn value(self: ZoneCtx, val: u64) void {
            c.___tracy_emit_zone_value(self.zone, val);
        }

        pub inline fn end(self: ZoneCtx) void {
            c.___tracy_emit_zone_end(self.zone);
        }
    };

    /// Start a trace. Defer calling end() to end the trace.
    pub inline fn trace(comptime src: SourceLocation) ZoneCtx {
        const callstack_depth = 10; // TODO configurable

        const static = struct {
            var loc: c.___tracy_source_location_data = undefined;
        };
        static.loc = .{
            .name = null,
            .function = src.fn_name.ptr,
            .file = src.file.ptr,
            .line = src.line,
            .color = 0,
        };

        const zone = if (has_callstack_support)
            c.___tracy_emit_zone_begin_callstack(&static.loc, callstack_depth, 1)
        else
            c.___tracy_emit_zone_begin(&static.loc, 1);

        return ZoneCtx{ .zone = zone };
    }
};

const Noop = struct {
    pub const ZoneCtx = struct {
        pub inline fn text(_: ZoneCtx, _: []const u8) void {}
        pub inline fn name(_: ZoneCtx, _: []const u8) void {}
        pub inline fn value(_: ZoneCtx, _: u64) void {}
        pub inline fn end(_: ZoneCtx) void {}
    };

    pub inline fn trace(comptime src: SourceLocation) ZoneCtx {
        _ = src;
        return .{};
    }
};
