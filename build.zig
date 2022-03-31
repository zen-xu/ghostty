const std = @import("std");
const Builder = std.build.Builder;
const LibExeObjStep = std.build.LibExeObjStep;

const glfw = @import("vendor/mach/glfw/build.zig");
const gpu_dawn = @import("vendor/mach/gpu-dawn/build.zig");

pub fn build(b: *std.build.Builder) void {
    const target = b.standardTargetOptions(.{});
    const mode = b.standardReleaseOptions();

    const exe = b.addExecutable("ghostty", "src/main.zig");
    exe.setTarget(target);
    exe.setBuildMode(mode);
    exe.install();
    exe.addPackagePath("gpu", "vendor/mach/gpu/src/main.zig");
    exe.addPackagePath("dawn", "vendor/mach/gpu-dawn/src/dawn/c.zig");
    exe.addPackagePath("glfw", "vendor/mach/glfw/src/main.zig");
    glfw.link(b, exe, .{});
    gpu_dawn.link(b, exe, if (target.getCpuArch() == .aarch64) .{
        // We only need to do this until there is an aarch64 binary build.
        .separate_libs = true,
        .from_source = true,
    } else .{});

    const run_cmd = exe.run();
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
