const std = @import("std");
const Builder = std.build.Builder;
const LibExeObjStep = std.build.LibExeObjStep;
const glfw = @import("vendor/mach/glfw/build.zig");
const ft = @import("src/freetype/build.zig");

pub fn build(b: *std.build.Builder) !void {
    const target = b.standardTargetOptions(.{});
    const mode = b.standardReleaseOptions();

    const exe = b.addExecutable("ghostty", "src/main.zig");
    exe.setTarget(target);
    exe.setBuildMode(mode);
    exe.install();
    exe.addIncludeDir("src/");
    exe.addCSourceFile("src/gb_math.c", &.{});
    exe.addPackagePath("glfw", "vendor/mach/glfw/src/main.zig");
    glfw.link(b, exe, .{});

    // GLAD
    exe.addIncludeDir("vendor/glad/include/");
    exe.addCSourceFile("vendor/glad/src/gl.c", &.{});

    const ftlib = try ft.create(b, target, mode, .{});
    ftlib.link(exe);
    // to link to system:
    // exe.linkSystemLibrary("freetype2");
    // exe.linkSystemLibrary("libpng");
    // exe.linkSystemLibrary("bzip2");
    // ftlib.addIncludeDirs(exe);

    // stb if we need it
    // exe.addIncludeDir("vendor/stb");
    // exe.addCSourceFile("src/stb/stb.c", &.{});

    const run_cmd = exe.run();
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    // Tests
    const test_step = b.step("test", "Run all tests");
    const lib_tests = b.addTest("src/main.zig");
    ftlib.link(lib_tests);
    lib_tests.addIncludeDir("vendor/glad/include/");
    lib_tests.addCSourceFile("vendor/glad/src/gl.c", &.{});
    test_step.dependOn(&lib_tests.step);
}
