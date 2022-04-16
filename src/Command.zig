//! Command launches sub-processes. This is an alternate implementation to the
//! Zig std.ChildProcess since at the time of authoring this, ChildProcess
//! didn't support the options necessary to spawn a shell attached to a pty.
//!
//! Consequently, I didn't implement a lot of features that std.ChildProcess
//! supports because we didn't need them. Cross-platform subprocessing is not
//! a trivial thing to implement (I've done it in three separate languages now)
//! so if we want to replatform onto std.ChildProcess I'd love to do that.
//! This was just the fastest way to get something built.
//!
//! TODO:
//!
//!   * Windows
//!   * Mac
//!
const Command = @This();

const std = @import("std");
const builtin = @import("builtin");
const os = std.os;
const debug = std.debug;
const testing = std.testing;
const Allocator = std.mem.Allocator;
const File = std.fs.File;

/// Path to the command to run. This must be an absolute path. This
/// library does not do PATH lookup.
path: []const u8,

/// Command-line arguments. It is the responsibility of the caller to set
/// args[0] to the command. If args is empty then args[0] will automatically
/// be set to equal path.
args: []const []const u8,

/// The file handle to set for stdin/out/err. If this isn't set, we do
/// nothing explicitly so it is up to the behavior of the operating system.
stdin: ?File = null,
stdout: ?File = null,
stderr: ?File = null,

/// If set, this will be executed /in the child process/ after fork but
/// before exec. This is useful to setup some state in the child before the
/// exec process takes over, such as signal handlers, setsid, setuid, etc.
pre_exec: ?fn () void = null,

/// Process ID is set after start is called.
pid: ?i32 = null,

/// The various methods a process may exit.
pub const Exit = union(enum) {
    /// Exited by normal exit call, value is exit status
    Exited: u8,

    /// Exited by a signal, value is the signal
    Signal: u32,

    /// Exited by a stop signal, value is signal
    Stopped: u32,

    /// Unknown exit reason, value is the status from waitpid
    Unknown: u32,

    pub fn init(status: u32) Exit {
        return if (os.W.IFEXITED(status))
            Exit{ .Exited = os.W.EXITSTATUS(status) }
        else if (os.W.IFSIGNALED(status))
            Exit{ .Signal = os.W.TERMSIG(status) }
        else if (os.W.IFSTOPPED(status))
            Exit{ .Stopped = os.W.STOPSIG(status) }
        else
            Exit{ .Unknown = status };
    }
};

/// Start the subprocess. This returns immediately once the child is started.
///
/// After this is successful, self.pid is available.
pub fn start(self: *Command, alloc: Allocator) !void {
    // Use an arena allocator for the temporary allocations we need in this func.
    // IMPORTANT: do all allocation prior to the fork(). I believe it is undefined
    // behavior if you malloc between fork and exec. The source of the Zig
    // stdlib seems to verify this as well as Go.
    var arena_allocator = std.heap.ArenaAllocator.init(alloc);
    defer arena_allocator.deinit();
    const arena = arena_allocator.allocator();

    // Null-terminate all our arguments
    const pathZ = try arena.dupeZ(u8, self.path);
    const argsZ = try arena.allocSentinel(?[*:0]u8, self.args.len, null);
    for (self.args) |arg, i| argsZ[i] = (try arena.dupeZ(u8, arg)).ptr;

    // Determine our env vars
    const envp = if (builtin.link_libc) std.c.environ else @compileError("missing env vars");

    // Fork
    const pid = try std.os.fork();
    if (pid != 0) {
        // Parent, return immediately.
        self.pid = @intCast(i32, pid);
        return;
    }

    // We are the child.

    // Setup our file descriptors for std streams.
    if (self.stdin) |f| try setupFd(f.handle, os.STDIN_FILENO);
    if (self.stdout) |f| try setupFd(f.handle, os.STDOUT_FILENO);
    if (self.stderr) |f| try setupFd(f.handle, os.STDERR_FILENO);

    // If the user requested a pre exec callback, call it now.
    if (self.pre_exec) |f| f();

    // Finally, replace our process.
    _ = std.os.execveZ(pathZ, argsZ, envp) catch null;
}

fn setupFd(src: File.Handle, target: i32) !void {
    // We use dup3 so that we can clear CLO_ON_EXEC. We do NOT want this
    // file descriptor to be closed on exec since we're exactly exec-ing after
    // this.
    if (os.linux.dup3(src, target, 0) < 0) return error.Dup3Failed;
}

/// Wait for the command to exit and return information about how it exited.
pub fn wait(self: Command) !Exit {
    const res = std.os.waitpid(self.pid.?, 0);
    return Exit.init(res.status);
}

test "Command: basic exec" {
    var cmd: Command = .{
        .path = "/usr/bin/env",
        .args = &.{ "/usr/bin/env", "--version" },
    };

    try cmd.start(testing.allocator);
    try testing.expect(cmd.pid != null);
    const exit = try cmd.wait();
    try testing.expect(exit == .Exited);
    try testing.expect(exit.Exited == 0);
}

test "Command: pre exec" {
    var cmd: Command = .{
        .path = "/usr/bin/env",
        .args = &.{ "/usr/bin/env", "--version" },
        .pre_exec = (struct {
            fn do() void {
                // This runs in the child, so we can exit and it won't
                // kill the test runner.
                os.exit(42);
            }
        }).do,
    };

    try cmd.start(testing.allocator);
    try testing.expect(cmd.pid != null);
    const exit = try cmd.wait();
    try testing.expect(exit == .Exited);
    try testing.expect(exit.Exited == 42);
}

test "Command: redirect stdout to file" {
    const cwd = std.fs.cwd();
    var stdout = try cwd.createFile("test1234.txt", .{
        .read = true,
        .truncate = true,
    });
    defer cwd.deleteFile("test1234.txt") catch unreachable;
    defer stdout.close();

    var cmd: Command = .{
        .path = "/usr/bin/env",
        .args = &.{ "/usr/bin/env", "--version" },
        .stdout = stdout,
    };

    try cmd.start(testing.allocator);
    try testing.expect(cmd.pid != null);
    const exit = try cmd.wait();
    try testing.expect(exit == .Exited);
    try testing.expect(exit.Exited == 0);

    // Read our stdout
    try stdout.seekTo(0);
    const contents = try stdout.readToEndAlloc(testing.allocator, 4096);
    defer testing.allocator.free(contents);
    try testing.expect(contents.len > 0);
}
