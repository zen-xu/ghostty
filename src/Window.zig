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
const Command = @import("Command.zig");
const Terminal = @import("terminal/Terminal.zig");
const SegmentedPool = @import("segmented_pool.zig").SegmentedPool;
const frame = @import("tracy/tracy.zig").frame;
const trace = @import("tracy/tracy.zig").trace;
const max_timer = @import("max_timer.zig");

const RenderTimer = max_timer.MaxTimer(renderTimerCallback);

const log = std.log.scoped(.window);

// The preallocation size for the write request pool. This should be big
// enough to satisfy most write requests. It must be a power of 2.
const WRITE_REQ_PREALLOC = std.math.pow(usize, 2, 5);

/// Allocator
alloc: Allocator,

/// The glfw window handle.
window: glfw.Window,

/// The terminal grid attached to this window.
grid: Grid,

/// The underlying pty for this window.
pty: Pty,

/// The command we're running for our tty.
command: Command,

/// The terminal emulator internal state. This is the abstract "terminal"
/// that manages input, grid updating, etc. and is renderer-agnostic. It
/// just stores internal state about a grid. This is connected back to
/// a renderer.
terminal: Terminal,

/// Timer that blinks the cursor.
cursor_timer: libuv.Timer,

/// Render at least 60fps.
render_timer: RenderTimer,

/// The reader/writer stream for the pty.
pty_stream: libuv.Tty,

/// This is the pool of available (unused) write requests. If you grab
/// one from the pool, you must put it back when you're done!
write_req_pool: SegmentedPool(libuv.WriteReq.T, WRITE_REQ_PREALLOC) = .{},

/// The pool of available buffers for writing to the pty.
/// TODO: [1]u8 is probably not right.
write_buf_pool: SegmentedPool([1]u8, WRITE_REQ_PREALLOC) = .{},

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

        // We need to disable this for now since this causes all sorts
        // of artifacts and issues to debug. This probably SHOULD be re-enable
        // at some point but only when we're ready to debug.
        .cocoa_retina_framebuffer = false,
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

    // Create our child process
    const path = (try Command.expandPath(alloc, "sh")) orelse
        return error.CommandNotFound;
    defer alloc.free(path);

    var env = try std.process.getEnvMap(alloc);
    defer env.deinit();
    try env.put("TERM", "dumb");

    var cmd: Command = .{
        .path = path,
        .args = &[_][]const u8{path},
        .env = &env,
        .pre_exec = (struct {
            fn callback(c: *Command) void {
                const p = c.getData(Pty) orelse unreachable;
                p.childPreExec() catch |err|
                    log.err("error initializing child: {}", .{err});
            }
        }).callback,
        .data = &pty,
    };
    // note: can't set these in the struct initializer because it
    // sets the handle to "0". Probably a stage1 zig bug.
    cmd.stdin = std.fs.File{ .handle = pty.slave };
    cmd.stdout = cmd.stdin;
    cmd.stderr = cmd.stdin;
    try cmd.start(alloc);
    log.debug("started subcommand path={s} pid={}", .{ path, cmd.pid });

    // Read data
    var stream = try libuv.Tty.init(alloc, loop, pty.master);
    errdefer stream.deinit(alloc);
    stream.setData(self);
    try stream.readStart(ttyReadAlloc, ttyRead);

    // Create our terminal
    var term = try Terminal.init(alloc, grid.size.columns, grid.size.rows);
    errdefer term.deinit(alloc);

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
        .command = cmd,
        .terminal = term,
        .cursor_timer = timer,
        .render_timer = try RenderTimer.init(loop, self, 16, 64),
        .pty_stream = stream,
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
    // Deinitialize the pty. This closes the pty handles. This should
    // cause a close in the our subprocess so just wait for that.
    self.pty.deinit();
    _ = self.command.wait() catch |err|
        log.err("error waiting for command to exit: {}", .{err});

    self.terminal.deinit(self.alloc);
    self.grid.deinit();
    self.window.destroy();

    self.cursor_timer.close((struct {
        fn callback(t: *libuv.Timer) void {
            const alloc = t.loop().getData(Allocator).?.*;
            t.deinit(alloc);
        }
    }).callback);

    self.render_timer.deinit();

    // We have to dealloc our window in the close callback because
    // we can't free some of the memory associated with the window
    // until the stream is closed.
    self.pty_stream.readStop();
    self.pty_stream.close((struct {
        fn callback(t: *libuv.Tty) void {
            const win = t.getData(Window).?;
            const alloc = win.alloc;
            t.deinit(alloc);
            win.write_req_pool.deinit(alloc);
            win.write_buf_pool.deinit(alloc);
            win.alloc.destroy(win);
        }
    }).callback);
}

pub fn shouldClose(self: Window) bool {
    return self.window.shouldClose();
}

fn sizeCallback(window: glfw.Window, width: i32, height: i32) void {
    const tracy = trace(@src());
    defer tracy.end();

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

    // Draw
    win.render_timer.schedule() catch unreachable;
}

fn charCallback(window: glfw.Window, codepoint: u21) void {
    const tracy = trace(@src());
    defer tracy.end();

    const win = window.getUserPointer(Window) orelse return;

    // Write the character to the pty
    const req = win.write_req_pool.get() catch unreachable;
    const buf = win.write_buf_pool.get() catch unreachable;
    buf[0] = @intCast(u8, codepoint);
    win.pty_stream.write(
        .{ .req = req },
        &[1][]u8{buf[0..1]},
        ttyWrite,
    ) catch unreachable;
}

fn keyCallback(
    window: glfw.Window,
    key: glfw.Key,
    scancode: i32,
    action: glfw.Action,
    mods: glfw.Mods,
) void {
    const tracy = trace(@src());
    defer tracy.end();

    _ = scancode;
    _ = mods;

    //log.info("KEY {} {} {} {}", .{ key, scancode, mods, action });
    if (action == .press or action == .repeat) {
        const c: u8 = switch (key) {
            // Lots more of these:
            // https://www.physics.udel.edu/~watson/scen103/ascii.html
            .a => if (mods.control and !mods.shift) 0x01 else return,
            .b => if (mods.control and !mods.shift) 0x02 else return,
            .c => if (mods.control and !mods.shift) 0x03 else return,
            .d => if (mods.control and !mods.shift) 0x04 else return,
            .e => if (mods.control and !mods.shift) 0x05 else return,
            .f => if (mods.control and !mods.shift) 0x06 else return,
            .g => if (mods.control and !mods.shift) 0x07 else return,
            .h => if (mods.control and !mods.shift) 0x08 else return,
            .i => if (mods.control and !mods.shift) 0x09 else return,
            .j => if (mods.control and !mods.shift) 0x0A else return,
            .k => if (mods.control and !mods.shift) 0x0B else return,
            .l => if (mods.control and !mods.shift) 0x0C else return,
            .m => if (mods.control and !mods.shift) 0x0D else return,
            .n => if (mods.control and !mods.shift) 0x0E else return,
            .o => if (mods.control and !mods.shift) 0x0F else return,
            .p => if (mods.control and !mods.shift) 0x10 else return,
            .q => if (mods.control and !mods.shift) 0x11 else return,
            .r => if (mods.control and !mods.shift) 0x12 else return,
            .s => if (mods.control and !mods.shift) 0x13 else return,
            .t => if (mods.control and !mods.shift) 0x14 else return,
            .u => if (mods.control and !mods.shift) 0x15 else return,
            .v => if (mods.control and !mods.shift) 0x16 else return,
            .x => if (mods.control and !mods.shift) 0x17 else return,
            .y => if (mods.control and !mods.shift) 0x18 else return,
            .z => if (mods.control and !mods.shift) 0x19 else return,

            .backspace => 0x08,
            .enter => '\n',
            .tab => '\t',
            else => return,
        };

        const win = window.getUserPointer(Window) orelse return;
        const req = win.write_req_pool.get() catch unreachable;
        const buf = win.write_buf_pool.get() catch unreachable;
        buf[0] = c;
        win.pty_stream.write(
            .{ .req = req },
            &[1][]u8{buf[0..1]},
            ttyWrite,
        ) catch unreachable;
    }
}

fn focusCallback(window: glfw.Window, focused: bool) void {
    const tracy = trace(@src());
    defer tracy.end();

    const win = window.getUserPointer(Window) orelse return;

    // We have to schedule a render because no matter what we're changing
    // the cursor.
    win.render_timer.schedule() catch unreachable;

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
    const tracy = trace(@src());
    defer tracy.end();

    const win = t.getData(Window) orelse return;
    win.grid.cursor_visible = !win.grid.cursor_visible;
    win.grid.updateCells(win.terminal) catch unreachable;
    win.render_timer.schedule() catch unreachable;
}

fn ttyReadAlloc(t: *libuv.Tty, size: usize) ?[]u8 {
    const tracy = trace(@src());
    defer tracy.end();

    const alloc = t.loop().getData(Allocator).?.*;
    return alloc.alloc(u8, size) catch null;
}

fn ttyRead(t: *libuv.Tty, n: isize, buf: []const u8) void {
    const tracy = trace(@src());
    tracy.color(0xEAEA7F); // yellow-ish
    defer tracy.end();

    const win = t.getData(Window).?;
    defer win.alloc.free(buf);

    // log.info("DATA: {d}", .{n});
    // log.info("DATA: {any}", .{buf[0..@intCast(usize, n)]});

    // First check for errors in the case n is less than 0.
    libuv.convertError(@intCast(i32, n)) catch |err| {
        switch (err) {
            // ignore EOF because it should end the process.
            libuv.Error.EOF => {},
            else => log.err("read error: {}", .{err}),
        }

        return;
    };

    // Add this character to the terminal buffer.
    win.terminal.append(win.alloc, buf[0..@intCast(usize, n)]) catch |err|
        log.err("error writing terminal data: {}", .{err});

    // Whenever a character is typed, we ensure the cursor is visible
    // and we restart the cursor timer.
    win.grid.cursor_visible = true;
    if (win.cursor_timer.isActive() catch false) {
        _ = win.cursor_timer.again() catch null;
    }

    // Update the cells for drawing
    win.grid.updateCells(win.terminal) catch unreachable;

    // Schedule a render
    win.render_timer.schedule() catch unreachable;
}

fn ttyWrite(req: *libuv.WriteReq, status: i32) void {
    const tracy = trace(@src());
    defer tracy.end();

    const tty = req.handle(libuv.Tty).?;
    const win = tty.getData(Window).?;
    win.write_req_pool.put();
    win.write_buf_pool.put();

    libuv.convertError(status) catch |err|
        log.err("write error: {}", .{err});

    //log.info("WROTE: {d}", .{status});
}

fn renderTimerCallback(t: *libuv.Timer) void {
    const tracy = trace(@src());
    defer tracy.end();

    const win = t.getData(Window).?;

    // Set our background
    gl.clearColor(0.2, 0.3, 0.3, 1.0);
    gl.clear(gl.c.GL_COLOR_BUFFER_BIT);

    // Render the grid
    win.grid.render() catch |err| {
        log.err("error rendering grid: {}", .{err});
        return;
    };

    // Swap
    win.window.swapBuffers() catch |err| {
        log.err("error swapping buffers: {}", .{err});
        return;
    };

    // Record our run
    win.render_timer.tick();
}
