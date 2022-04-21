const std = @import("std");

/// This is the type returned by create.
pub const Library = struct {
    step: *std.build.LibExeObjStep,

    /// statically link this library into the given step
    pub fn link(self: Library, other: *std.build.LibExeObjStep) void {
        self.addIncludeDirs(other);
        other.linkLibrary(self.step);
    }

    /// only add the include dirs to the given step. This is useful if building
    /// a static library that you don't want to fully link in the code of this
    /// library.
    pub fn addIncludeDirs(self: Library, other: *std.build.LibExeObjStep) void {
        _ = self;
        other.addIncludeDir(include_dir);
    }
};

/// Create this library. This is the primary API users of build.zig should
/// use to link this library to their application. On the resulting Library,
/// call the link function and given your own application step.
pub fn create(
    b: *std.build.Builder,
    target: std.zig.CrossTarget,
    mode: std.builtin.Mode,
) !Library {
    const ret = b.addStaticLibrary("uv", null);
    ret.setTarget(target);
    ret.setBuildMode(mode);

    var flags = std.ArrayList([]const u8).init(b.allocator);
    defer flags.deinit();

    // try flags.appendSlice(&.{});

    if (!target.isWindows()) {
        try flags.appendSlice(&.{
            "-D_FILE_OFFSET_BITS=64",
            "-D_LARGEFILE_SOURCE",
        });
    }

    if (target.isLinux()) {
        try flags.appendSlice(&.{
            "-D_GNU_SOURCE",
            "-D_POSIX_C_SOURCE=200112",
        });
    }

    // C files common to all platforms
    ret.addCSourceFiles(&.{
        root() ++ "src/fs-poll.c",
        root() ++ "src/idna.c",
        root() ++ "src/inet.c",
        root() ++ "src/random.c",
        root() ++ "src/strscpy.c",
        root() ++ "src/strtok.c",
        root() ++ "src/threadpool.c",
        root() ++ "src/timer.c",
        root() ++ "src/uv-common.c",
        root() ++ "src/uv-data-getter-setters.c",
        root() ++ "src/version.c",
    }, flags.items);

    if (!target.isWindows()) {
        ret.addCSourceFiles(&.{
            root() ++ "src/unix/async.c",
            root() ++ "src/unix/core.c",
            root() ++ "src/unix/dl.c",
            root() ++ "src/unix/fs.c",
            root() ++ "src/unix/getaddrinfo.c",
            root() ++ "src/unix/getnameinfo.c",
            root() ++ "src/unix/loop-watcher.c",
            root() ++ "src/unix/loop.c",
            root() ++ "src/unix/pipe.c",
            root() ++ "src/unix/poll.c",
            root() ++ "src/unix/process.c",
            root() ++ "src/unix/random-devurandom.c",
            root() ++ "src/unix/signal.c",
            root() ++ "src/unix/stream.c",
            root() ++ "src/unix/tcp.c",
            root() ++ "src/unix/thread.c",
            root() ++ "src/unix/tty.c",
            root() ++ "src/unix/udp.c",
        }, flags.items);
    }

    if (target.isLinux() or target.isDarwin()) {
        ret.addCSourceFiles(&.{
            root() ++ "src/unix/proctitle.c",
        }, flags.items);
    }

    if (target.isLinux()) {
        ret.addCSourceFiles(&.{
            root() ++ "src/unix/linux-core.c",
            root() ++ "src/unix/linux-inotify.c",
            root() ++ "src/unix/linux-syscalls.c",
            root() ++ "src/unix/procfs-exepath.c",
            root() ++ "src/unix/random-getrandom.c",
            root() ++ "src/unix/random-sysctl-linux.c",
            root() ++ "src/unix/epoll.c",
        }, flags.items);
    }

    ret.addIncludeDir(include_dir);
    ret.addIncludeDir(root() ++ "src");
    if (target.isWindows()) {
        ret.linkSystemLibrary("psapi");
        ret.linkSystemLibrary("user32");
        ret.linkSystemLibrary("advapi32");
        ret.linkSystemLibrary("iphlpapi");
        ret.linkSystemLibrary("userenv");
        ret.linkSystemLibrary("ws2_32");
    }
    if (target.isLinux()) {
        ret.linkSystemLibrary("pthread");
    }
    ret.linkLibC();

    return Library{ .step = ret };
}

fn root() []const u8 {
    return (std.fs.path.dirname(@src().file) orelse unreachable) ++ "/../../vendor/libuv/";
}

/// Directories with our includes.
const include_dir = root() ++ "include";
