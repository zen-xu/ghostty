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

        // We need to add this directory to the include path for the final
        // app so that we can access "freetype-zig.h".
        other.addIncludeDir(std.fs.path.dirname(@src().file) orelse unreachable);
    }
};

/// Compile-time options for the library. These mostly correspond to
/// options exposed by the native build system used by the library.
pub const Options = struct {};

/// Create this library. This is the primary API users of build.zig should
/// use to link this library to their application. On the resulting Library,
/// call the link function and given your own application step.
pub fn create(
    b: *std.build.Builder,
    target: std.zig.CrossTarget,
    mode: std.builtin.Mode,
    opts: Options,
) !Library {
    _ = opts;

    const ret = b.addStaticLibrary("freetype", null);
    ret.setTarget(target);
    ret.setBuildMode(mode);

    var flags = std.ArrayList([]const u8).init(b.allocator);
    defer flags.deinit();

    try flags.appendSlice(&.{
        "-DFT2_BUILD_LIBRARY",

        "-DHAVE_UNISTD_H",
        "-DHAVE_FCNTL_H",
    });

    // C files
    ret.addCSourceFiles(srcs, flags.items);
    switch (target.getOsTag()) {
        .linux => ret.addCSourceFile(root() ++ "builds/unix/ftsystem.c", flags.items),
        .windows => ret.addCSourceFile(root() ++ "builds/windows/ftsystem.c", flags.items),
        else => ret.addCSourceFile(root() ++ "src/base/ftsystem.c", flags.items),
    }
    switch (target.getOsTag()) {
        .windows => {
            ret.addCSourceFile(root() ++ "builds/windows/ftdebug.c", flags.items);
            ret.addCSourceFile(root() ++ "src/base/ftver.c", flags.items);
        },
        else => ret.addCSourceFile(root() ++ "src/base/ftdebug.c", flags.items),
    }

    ret.addIncludeDir(include_dir);
    ret.linkLibC();

    return Library{ .step = ret };
}

fn root() []const u8 {
    return (std.fs.path.dirname(@src().file) orelse unreachable) ++ "/../../vendor/freetype/";
}

/// Directories with our includes.
const include_dir = root() ++ "include";

const srcs = &.{
    root() ++ "src/autofit/autofit.c",
    root() ++ "src/base/ftbase.c",
    root() ++ "src/base/ftbbox.c",
    root() ++ "src/base/ftbdf.c",
    root() ++ "src/base/ftbitmap.c",
    root() ++ "src/base/ftcid.c",
    root() ++ "src/base/ftfstype.c",
    root() ++ "src/base/ftgasp.c",
    root() ++ "src/base/ftglyph.c",
    root() ++ "src/base/ftgxval.c",
    root() ++ "src/base/ftinit.c",
    root() ++ "src/base/ftmm.c",
    root() ++ "src/base/ftotval.c",
    root() ++ "src/base/ftpatent.c",
    root() ++ "src/base/ftpfr.c",
    root() ++ "src/base/ftstroke.c",
    root() ++ "src/base/ftsynth.c",
    root() ++ "src/base/fttype1.c",
    root() ++ "src/base/ftwinfnt.c",
    root() ++ "src/bdf/bdf.c",
    root() ++ "src/bzip2/ftbzip2.c",
    root() ++ "src/cache/ftcache.c",
    root() ++ "src/cff/cff.c",
    root() ++ "src/cid/type1cid.c",
    root() ++ "src/gzip/ftgzip.c",
    root() ++ "src/lzw/ftlzw.c",
    root() ++ "src/pcf/pcf.c",
    root() ++ "src/pfr/pfr.c",
    root() ++ "src/psaux/psaux.c",
    root() ++ "src/pshinter/pshinter.c",
    root() ++ "src/psnames/psnames.c",
    root() ++ "src/raster/raster.c",
    root() ++ "src/sdf/sdf.c",
    root() ++ "src/sfnt/sfnt.c",
    root() ++ "src/smooth/smooth.c",
    root() ++ "src/svg/svg.c",
    root() ++ "src/truetype/truetype.c",
    root() ++ "src/type1/type1.c",
    root() ++ "src/type42/type42.c",
    root() ++ "src/winfonts/winfnt.c",
};
