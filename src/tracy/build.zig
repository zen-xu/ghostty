const std = @import("std");
const Builder = std.build.Builder;
const LibExeObjStep = std.build.LibExeObjStep;

/// Build and link the Tracy client into the given executable.
pub fn link(
    b: *Builder,
    exe: *LibExeObjStep,
    target: std.zig.CrossTarget,
) !void {
    var flags = std.ArrayList([]const u8).init(b.allocator);
    defer flags.deinit();

    try flags.appendSlice(&.{
        "-DTRACY_ENABLE",
        "-fno-sanitize=undefined",
    });

    if (target.isWindows()) {
        try flags.appendSlice(&.{
            "-D_WIN32_WINNT=0x601",
        });
    }

    const path = root();
    exe.addIncludePath(path);
    exe.addCSourceFile(try std.fs.path.join(
        exe.builder.allocator,
        &.{ path, "TracyClient.cpp" },
    ), flags.items);

    exe.linkLibC();
    exe.linkSystemLibrary("c++");

    if (exe.target.isWindows()) {
        exe.linkSystemLibrary("Advapi32");
        exe.linkSystemLibrary("User32");
        exe.linkSystemLibrary("Ws2_32");
        exe.linkSystemLibrary("DbgHelp");
    }
}

fn root() []const u8 {
    return (std.fs.path.dirname(@src().file) orelse unreachable) ++ "/../../vendor/tracy/";
}
