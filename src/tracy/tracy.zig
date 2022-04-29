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

    /// A zone represents the lifetime of a special on-stack profiler variable.
    /// Typically it would exist for the duration of a whole scope of the
    /// profiled function, but you also can measure time spent in scopes of a
    /// for-loop or an if-branch.
    pub const Zone = struct {
        zone: c.___tracy_c_zone_context,

        /// Text description of a zone.
        pub inline fn text(self: Zone, val: []const u8) void {
            c.___tracy_emit_zone_text(self.zone, val.ptr, val.len);
        }

        /// Name of the zone.
        pub inline fn name(self: Zone, val: []const u8) void {
            c.___tracy_emit_zone_name(self.zone, val.ptr, val.len);
        }

        /// Color of the zone in the UI. Specify the value as RGB
        /// using hex: 0xRRGGBB.
        pub inline fn color(self: Zone, val: u32) void {
            c.___tracy_emit_zone_color(self.zone, val);
        }

        /// A value associated with the zone.
        pub inline fn value(self: Zone, val: u64) void {
            c.___tracy_emit_zone_value(self.zone, val);
        }

        /// End the zone.
        pub inline fn end(self: Zone) void {
            c.___tracy_emit_zone_end(self.zone);
        }
    };

    /// Tracy profiles within the context of a frame. This represents
    /// a single frame.
    pub fn Frame(comptime name: [:0]const u8) type {
        return struct {
            pub fn end(_: @This()) void {
                c.___tracy_emit_frame_mark_end(name.ptr);
            }
        };
    }

    /// Start a trace. Defer calling end() to end the trace.
    pub inline fn trace(comptime src: SourceLocation) Zone {
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

        return Zone{ .zone = zone };
    }

    /// Mark the boundary of a frame. Good for continuous frames. For
    /// discontinous frames, use frame() and defer end().
    pub inline fn frameMark() void {
        c.___tracy_emit_frame_mark(null);
    }

    /// Start a discontinuous frame.
    pub inline fn frame(comptime name: [:0]const u8) Frame(name) {
        c.___tracy_emit_frame_mark_start(name.ptr);
        return .{};
    }
};

const Noop = struct {
    pub const Zone = struct {
        pub inline fn text(_: Zone, _: []const u8) void {}
        pub inline fn name(_: Zone, _: []const u8) void {}
        pub inline fn color(_: Zone, _: u32) void {}
        pub inline fn value(_: Zone, _: u64) void {}
        pub inline fn end(_: Zone) void {}
    };

    pub fn Frame(comptime _: [:0]const u8) type {
        return struct {
            pub fn end(_: @This()) void {}
        };
    }

    pub inline fn trace(comptime src: SourceLocation) Zone {
        _ = src;
        return .{};
    }

    pub inline fn frameMark() void {}

    pub inline fn frame(comptime name: [*:0]const u8) Frame(name) {
        return .{};
    }
};
