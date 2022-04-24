//! Window represents a single OS window.
//!
//! NOTE(multi-window): This may be premature, but this abstraction is here
//! to pave the way One Day(tm) for multi-window support. At the time of
//! writing, we support exactly one window.
const Window = @This();

const std = @import("std");
const builtin = @import("builtin");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;
const Grid = @import("Grid.zig");
const glfw = @import("glfw");
const gl = @import("opengl.zig");
const libuv = @import("libuv/main.zig");
const Pty = @import("Pty.zig");
const Terminal = @import("terminal/Terminal.zig");

const log = std.log.scoped(.window);

/// Allocator
alloc: Allocator,

/// The glfw window handle.
window: glfw.Window,

/// The terminal grid attached to this window.
grid: Grid,

/// The underlying pty for this window.
pty: Pty,

/// The terminal emulator internal state. This is the abstract "terminal"
/// that manages input, grid updating, etc. and is renderer-agnostic. It
/// just stores internal state about a grid. This is connected back to
/// a renderer.
terminal: Terminal,

/// Timer that blinks the cursor.
cursor_timer: libuv.Timer,

/// Set this to true whenver an event occurs that we may want to wake up
/// the event loop. Only set this from the main thread.
wakeup: bool = false,

/// Create a new window. This allocates and returns a pointer because we
/// need a stable pointer for user data callbacks. Therefore, a stack-only
/// initialization is not currently possible.
pub fn create(alloc: Allocator, loop: libuv.Loop) !*Window {
    var self = try alloc.create(Window);
    errdefer alloc.destroy(self);

    // Create our window
    const window = try glfw.Window.create(640, 480, "ghostty", null, null, .{
        .context_version_major = 3,
        .context_version_minor = 3,
        .opengl_profile = .opengl_core_profile,
        .opengl_forward_compat = true,
        .cocoa_graphics_switching = builtin.os.tag == .macos,
    });
    errdefer window.destroy();

    // NOTE(multi-window): We'll need to extract all the below into a
    // dedicated renderer and consider the multi-threading (or at the very
    // least: multi-OpenGL-context) implications. Since we don't support
    // multiple windows right now, we just do it all here.

    // Setup OpenGL
    try glfw.makeContextCurrent(window);
    try glfw.swapInterval(1);

    // Load OpenGL bindings
    const version = try gl.glad.load(glfw.getProcAddress);
    log.info("loaded OpenGL {}.{}", .{
        gl.glad.versionMajor(version),
        gl.glad.versionMinor(version),
    });

    // Culling, probably not necessary. We have to change the winding
    // order since our 0,0 is top-left.
    gl.c.glEnable(gl.c.GL_CULL_FACE);
    gl.c.glFrontFace(gl.c.GL_CW);

    // Blending for text
    gl.c.glEnable(gl.c.GL_BLEND);
    gl.c.glBlendFunc(gl.c.GL_SRC_ALPHA, gl.c.GL_ONE_MINUS_SRC_ALPHA);

    // Create our terminal grid with the initial window size
    const window_size = try window.getSize();
    var grid = try Grid.init(alloc);
    try grid.setScreenSize(.{ .width = window_size.width, .height = window_size.height });

    // Create our pty
    var pty = try Pty.open(.{
        .ws_row = @intCast(u16, grid.size.rows),
        .ws_col = @intCast(u16, grid.size.columns),
        .ws_xpixel = @intCast(u16, window_size.width),
        .ws_ypixel = @intCast(u16, window_size.height),
    });
    errdefer pty.deinit();

    // Create our terminal
    var term = Terminal.init(grid.size.columns, grid.size.rows);
    errdefer term.deinit(alloc);
    try term.append(alloc, "> ");

    // Setup a timer for blinking the cursor
    var timer = try libuv.Timer.init(alloc, loop);
    errdefer timer.deinit(alloc);
    errdefer timer.close(null);
    timer.setData(self);
    try timer.start(cursorTimerCallback, 600, 600);

    self.* = .{
        .alloc = alloc,
        .window = window,
        .grid = grid,
        .pty = pty,
        .terminal = term,
        .cursor_timer = timer,
    };

    // Setup our callbacks and user data
    window.setUserPointer(self);
    window.setSizeCallback(sizeCallback);
    window.setCharCallback(charCallback);
    window.setKeyCallback(keyCallback);
    window.setFocusCallback(focusCallback);

    return self;
}

pub fn destroy(self: *Window) void {
    self.cursor_timer.close((struct {
        fn callback(t: *libuv.Timer) void {
            const alloc = t.loop().getData(Allocator).?.*;
            t.deinit(alloc);
        }
    }).callback);
    self.terminal.deinit(self.alloc);
    self.pty.deinit();
    self.grid.deinit();
    self.window.destroy();
    self.alloc.destroy(self);
}

pub fn shouldClose(self: Window) bool {
    return self.window.shouldClose();
}

pub fn run(self: Window) !void {
    // Set our background
    gl.clearColor(0.2, 0.3, 0.3, 1.0);
    gl.clear(gl.c.GL_COLOR_BUFFER_BIT);

    // Render the grid
    try self.grid.render();

    // Swap
    try self.window.swapBuffers();
}

fn sizeCallback(window: glfw.Window, width: i32, height: i32) void {
    // glfw gives us signed integers, but negative width/height is n
    // non-sensical so we use unsigned throughout, so assert.
    assert(width >= 0);
    assert(height >= 0);

    // Update our grid so that the projections on render are correct.
    const win = window.getUserPointer(Window) orelse return;
    win.grid.setScreenSize(.{
        .width = @intCast(u32, width),
        .height = @intCast(u32, height),
    }) catch |err| log.err("error updating grid screen size err={}", .{err});

    // Update the size of our terminal state
    win.terminal.resize(win.grid.size.columns, win.grid.size.rows);

    // TODO: this is not the right place for this
    win.grid.updateCells(win.terminal) catch unreachable;

    // Update the size of our pty
    win.pty.setSize(.{
        .ws_row = @intCast(u16, win.grid.size.rows),
        .ws_col = @intCast(u16, win.grid.size.columns),
        .ws_xpixel = @intCast(u16, width),
        .ws_ypixel = @intCast(u16, height),
    }) catch |err| log.err("error updating pty screen size err={}", .{err});

    // Update our viewport for this context to be the entire window
    gl.viewport(0, 0, width, height) catch |err|
        log.err("error updating OpenGL viewport err={}", .{err});
}

fn charCallback(window: glfw.Window, codepoint: u21) void {
    const win = window.getUserPointer(Window) orelse return;

    // Append this character to the terminal
    win.terminal.appendChar(win.alloc, @intCast(u8, codepoint)) catch unreachable;

    // Whenever a character is typed, we ensure the cursor is visible
    // and we restart the cursor timer.
    win.grid.cursor_visible = true;
    if (win.cursor_timer.isActive() catch false) {
        _ = win.cursor_timer.again() catch null;
    }

    // Update the cells for drawing
    win.grid.updateCells(win.terminal) catch unreachable;
}

fn keyCallback(
    window: glfw.Window,
    key: glfw.Key,
    scancode: i32,
    action: glfw.Action,
    mods: glfw.Mods,
) void {
    _ = scancode;
    _ = mods;

    //log.info("KEY {} {}", .{ key, action });
    if (key == .enter and (action == .press or action == .repeat)) {
        const win = window.getUserPointer(Window) orelse return;
        win.terminal.append(win.alloc, "\r\n> ") catch unreachable;
        win.grid.updateCells(win.terminal) catch unreachable;
    }
}

fn focusCallback(window: glfw.Window, focused: bool) void {
    const win = window.getUserPointer(Window) orelse return;
    if (focused) {
        win.wakeup = true;
        win.cursor_timer.start(cursorTimerCallback, 0, win.cursor_timer.getRepeat()) catch unreachable;
        win.grid.cursor_style = .box;
        win.grid.cursor_visible = false;
    } else {
        win.grid.cursor_visible = true;
        win.grid.cursor_style = .box_hollow;
        win.grid.updateCells(win.terminal) catch unreachable;
        win.cursor_timer.stop() catch unreachable;
    }
}

fn cursorTimerCallback(t: *libuv.Timer) void {
    const win = t.getData(Window) orelse return;
    win.grid.cursor_visible = !win.grid.cursor_visible;
    win.grid.updateCells(win.terminal) catch unreachable;
}
