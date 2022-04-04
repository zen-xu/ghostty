const std = @import("std");
const ft = @import("../freetype/build.zig");

/// Compile-time options for the library. These mostly correspond to
/// options exposed by the native build system used by the library.
pub const Options = struct {};

/// Create this library. This is the primary API users of build.zig should
/// use to link this library to their application. On the resulting Library,
/// call the link function and given your own application step.
pub fn link(
    exe: *std.build.LibExeObjStep,
    b: *std.build.Builder,
    target: std.zig.CrossTarget,
    mode: std.builtin.Mode,
    opts: Options,
) !void {
    _ = opts;

    const ret = b.addStaticLibrary("freetype-gl", null);
    ret.setTarget(target);
    ret.setBuildMode(mode);

    var flags = std.ArrayList([]const u8).init(b.allocator);
    defer flags.deinit();
    try flags.appendSlice(&.{
        "-DGL_WITH_GLAD",
    });

    // C files
    ret.addCSourceFiles(srcs, flags.items);
    ret.addIncludeDir(root());
    ret.addIncludeDir(thisDir() ++ "../../glad/include");
    ret.linkLibC();

    // For config.h
    ret.addIncludeDir(thisDir());

    // Dependencies
    ret.linkSystemLibrary("gl");
    const ftstep = try ft.create(b, target, mode, .{});
    ftstep.addIncludeDirs(ret);

    exe.addIncludeDir(root());
    exe.linkLibrary(ret);
}

fn root() []const u8 {
    return (std.fs.path.dirname(@src().file) orelse unreachable) ++ "/../../vendor/freetype-gl/";
}

fn thisDir() []const u8 {
    return (std.fs.path.dirname(@src().file) orelse unreachable) ++ "/";
}

const srcs = &.{
    root() ++ "distance-field.c",
    root() ++ "edtaa3func.c",
    root() ++ "platform.c",
    root() ++ "text-buffer.c",
    root() ++ "texture-atlas.c",
    root() ++ "texture-font.c",
    root() ++ "utf8-utils.c",
    root() ++ "ftgl-utils.c",
    root() ++ "vector.c",
    root() ++ "vertex-attribute.c",

    // optional stuff we don't need
    // root() ++ "font-manager.c",
    // root() ++ "vertex-buffer.c",
};
