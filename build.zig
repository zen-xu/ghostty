const std = @import("std");
const Builder = std.build.Builder;
const LibExeObjStep = std.build.LibExeObjStep;

pub fn build(b: *std.build.Builder) void {
    const target = b.standardTargetOptions(.{});
    const mode = b.standardReleaseOptions();

    const exe = b.addExecutable("ghostty", "src/main.zig");
    exe.setTarget(target);
    exe.setBuildMode(mode);
    exe.install();
    exe.linkLibrary(addRaylib(exe.builder, exe.target));
    exe.addIncludeDir("vendor/raylib/src"); // for raylib.h

    const run_cmd = exe.run();
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}

pub fn addRaylib(b: *std.build.Builder, target: std.zig.CrossTarget) *std.build.LibExeObjStep {
    // Standard release options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
    const mode = b.standardReleaseOptions();

    const raylib_flags = &[_][]const u8{
        "-std=gnu99",
        "-DPLATFORM_DESKTOP",
        "-DGL_SILENCE_DEPRECATION=199309L",
        "-fno-sanitize=undefined", // https://github.com/raysan5/raylib/issues/1891
        "-DSUPPORT_EVENTS_WAITING", // for waiting, not polling on events
    };

    const srcdir = "vendor/raylib/src";

    const raylib = b.addStaticLibrary("raylib", srcdir ++ "/raylib.h");
    raylib.setTarget(target);
    raylib.setBuildMode(mode);
    raylib.linkLibC();

    raylib.addIncludeDir(srcdir ++ "/external/glfw/include");

    raylib.addCSourceFiles(&.{
        srcdir ++ "/raudio.c",
        srcdir ++ "/rcore.c",
        srcdir ++ "/rmodels.c",
        srcdir ++ "/rshapes.c",
        srcdir ++ "/rtext.c",
        srcdir ++ "/rtextures.c",
        srcdir ++ "/utils.c",
    }, raylib_flags);

    switch (raylib.target.toTarget().os.tag) {
        .windows => {
            raylib.addCSourceFiles(&.{srcdir ++ "/rglfw.c"}, raylib_flags);
            raylib.linkSystemLibrary("winmm");
            raylib.linkSystemLibrary("gdi32");
            raylib.linkSystemLibrary("opengl32");
            raylib.addIncludeDir("external/glfw/deps/mingw");
        },
        .linux => {
            raylib.addCSourceFiles(&.{srcdir ++ "/rglfw.c"}, raylib_flags);
            raylib.linkSystemLibrary("GL");
            raylib.linkSystemLibrary("rt");
            raylib.linkSystemLibrary("dl");
            raylib.linkSystemLibrary("m");
            raylib.linkSystemLibrary("X11");
        },
        .freebsd, .openbsd, .netbsd, .dragonfly => {
            raylib.addCSourceFiles(&.{srcdir ++ "/rglfw.c"}, raylib_flags);
            raylib.linkSystemLibrary("GL");
            raylib.linkSystemLibrary("rt");
            raylib.linkSystemLibrary("dl");
            raylib.linkSystemLibrary("m");
            raylib.linkSystemLibrary("X11");
            raylib.linkSystemLibrary("Xrandr");
            raylib.linkSystemLibrary("Xinerama");
            raylib.linkSystemLibrary("Xi");
            raylib.linkSystemLibrary("Xxf86vm");
            raylib.linkSystemLibrary("Xcursor");
        },
        .macos => {
            // On macos rglfw.c include Objective-C files.
            const raylib_flags_extra_macos = &[_][]const u8{
                "-ObjC",
            };
            raylib.addCSourceFiles(
                &.{srcdir ++ "/rglfw.c"},
                raylib_flags ++ raylib_flags_extra_macos,
            );
            raylib.linkFramework("Foundation");
        },
        else => {
            @panic("Unsupported OS");
        },
    }

    return raylib;
}
