const std = @import("std");

/// Compile-time options for the library. These mostly correspond to
/// options exposed by the native build system used by the library.
pub const BuildOptions = struct {};

// Build and link this library.
pub fn build(
    b: *std.build.Builder,
    step: *std.build.LibExeObjStep,
    target: std.zig.CrossTarget,
    mode: std.builtin.Mode,
    opts: BuildOptions,
) !void {
    _ = opts;

    const ret = b.addStaticLibrary("cglm", null);
    ret.setTarget(target);
    ret.setBuildMode(mode);

    var flags = std.ArrayList([]const u8).init(b.allocator);
    defer flags.deinit();

    try flags.appendSlice(&.{
        "-DCGLM_STATIC",
    });

    // C files
    ret.addCSourceFiles(srcs, flags.items);
    ret.addIncludeDir(include_dir);
    ret.linkLibC();

    step.addIncludeDir(include_dir);
    step.linkLibrary(ret);
}

fn root() []const u8 {
    return (std.fs.path.dirname(@src().file) orelse unreachable) ++ "/../vendor/cglm/";
}

/// Directories with our includes.
const include_dir = root() ++ "include";

const srcs = &.{
    root() ++ "src/euler.c",
    root() ++ "src/affine.c",
    root() ++ "src/io.c",
    root() ++ "src/quat.c",
    root() ++ "src/cam.c",
    root() ++ "src/vec2.c",
    root() ++ "src/vec3.c",
    root() ++ "src/vec4.c",
    root() ++ "src/mat2.c",
    root() ++ "src/mat3.c",
    root() ++ "src/mat4.c",
    root() ++ "src/plane.c",
    root() ++ "src/frustum.c",
    root() ++ "src/box.c",
    root() ++ "src/project.c",
    root() ++ "src/sphere.c",
    root() ++ "src/ease.c",
    root() ++ "src/curve.c",
    root() ++ "src/bezier.c",
    root() ++ "src/ray.c",
    root() ++ "src/affine2d.c",
    root() ++ "src/clipspace/persp_lh_zo.c",
    root() ++ "src/clipspace/persp_rh_zo.c",
    root() ++ "src/clipspace/persp_lh_no.c",
    root() ++ "src/clipspace/persp_rh_no.c",
    root() ++ "src/clipspace/ortho_lh_zo.c",
    root() ++ "src/clipspace/ortho_rh_zo.c",
    root() ++ "src/clipspace/ortho_lh_no.c",
    root() ++ "src/clipspace/ortho_rh_no.c",
    root() ++ "src/clipspace/view_lh_zo.c",
    root() ++ "src/clipspace/view_rh_zo.c",
    root() ++ "src/clipspace/view_lh_no.c",
    root() ++ "src/clipspace/view_rh_no.c",
};
