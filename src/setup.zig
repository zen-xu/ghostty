const std = @import("std");
const dawn = @import("dawn");
const glfw = @import("glfw");
const gpu = @import("gpu");
const c = dawn.c;

const Setup = struct {
    native_instance: gpu.NativeInstance,
    backend_type: gpu.Adapter.BackendType,
    device: gpu.Device,
    window: glfw.Window,
};

pub fn setup(allocator: std.mem.Allocator) !Setup {
    const backend_type = try detectBackendType(allocator);
    std.log.info("detected backend type: {}", .{backend_type});

    // Initialize glfw
    try glfw.init(.{});
    errdefer glfw.terminate();

    // Create the window and discover adapters using it (esp. for OpenGL)
    var hints = glfwWindowHintsForBackend(backend_type);
    hints.cocoa_retina_framebuffer = true;
    const window = try glfw.Window.create(640, 480, "ghostty", null, null, hints);

    const backend_procs = dawn.c.machDawnNativeGetProcs();
    dawn.c.dawnProcSetProcs(backend_procs);

    const instance = dawn.c.machDawnNativeInstance_init();
    var native_instance = gpu.NativeInstance.wrap(dawn.c.machDawnNativeInstance_get(instance).?);
    const gpu_interface = native_instance.interface();

    // Discovers e.g. OpenGL adapters.
    try discoverAdapters(instance, window, backend_type);

    // Request an adapter.
    const backend_adapter = switch (gpu_interface.waitForAdapter(&.{
        .power_preference = .high_performance,
    })) {
        .adapter => |v| v,
        .err => |err| {
            std.debug.print("failed to get adapter: error={} {s}\n", .{ err.code, err.message });
            std.process.exit(1);
        },
    };

    // Print which adapter we are going to use.
    const props = backend_adapter.properties;
    std.debug.print("found {s} backend on {s} adapter: {s}, {s}\n", .{
        gpu.Adapter.backendTypeName(props.backend_type),
        gpu.Adapter.typeName(props.adapter_type),
        props.name,
        props.driver_description,
    });

    const device = switch (backend_adapter.waitForDevice(&.{})) {
        .device => |v| v,
        .err => |err| {
            std.debug.print("failed to get device: error={} {s}\n", .{ err.code, err.message });
            std.process.exit(1);
        },
    };

    return Setup{
        .native_instance = native_instance,
        .backend_type = backend_type,
        .device = device,
        .window = window,
    };
}

fn detectBackendType(allocator: std.mem.Allocator) !gpu.Adapter.BackendType {
    const GPU_BACKEND = std.process.getEnvVarOwned(allocator, "GPU_BACKEND") catch |err| switch (err) {
        error.EnvironmentVariableNotFound => @as(?[]u8, null),
        else => |e| return e,
    };
    if (GPU_BACKEND) |backend| {
        defer allocator.free(backend);
        if (std.ascii.eqlIgnoreCase(backend, "d3d11")) return .d3d11;
        if (std.ascii.eqlIgnoreCase(backend, "d3d12")) return .d3d12;
        if (std.ascii.eqlIgnoreCase(backend, "metal")) return .metal;
        if (std.ascii.eqlIgnoreCase(backend, "null")) return .nul;
        if (std.ascii.eqlIgnoreCase(backend, "opengl")) return .opengl;
        if (std.ascii.eqlIgnoreCase(backend, "opengles")) return .opengles;
        if (std.ascii.eqlIgnoreCase(backend, "vulkan")) return .vulkan;
        @panic("unknown GPU_BACKEND value");
    }

    const target = @import("builtin").target;
    if (target.isDarwin()) return .metal;
    if (target.os.tag == .windows) return .d3d12;
    return .vulkan;
}

fn glfwWindowHintsForBackend(backend: gpu.Adapter.BackendType) glfw.Window.Hints {
    return switch (backend) {
        .opengl => .{
            // Ask for OpenGL 4.4 which is what the GL backend requires for
            //  compute shaders and texture views.
            .context_version_major = 4,
            .context_version_minor = 4,
            .opengl_forward_compat = true,
            .opengl_profile = .opengl_core_profile,
        },
        .opengles => .{
            .context_version_major = 3,
            .context_version_minor = 1,
            .client_api = .opengl_es_api,
            .context_creation_api = .egl_context_api,
        },
        else => .{
            // Without this GLFW will initialize a GL context on the window,
            // which prevents using  the window with other APIs (by crashing in weird ways).
            .client_api = .no_api,
        },
    };
}

fn discoverAdapters(
    instance: c.MachDawnNativeInstance,
    window: glfw.Window,
    backend: gpu.Adapter.BackendType,
) !void {
    switch (backend) {
        .opengl => {
            try glfw.makeContextCurrent(window);
            const adapter_options = c.MachDawnNativeAdapterDiscoveryOptions_OpenGL{
                .getProc = @ptrCast(fn ([*c]const u8) callconv(.C) ?*anyopaque, glfw.getProcAddress),
            };
            _ = c.machDawnNativeInstance_discoverAdapters(instance, @enumToInt(backend), &adapter_options);
        },
        .opengles => {
            try glfw.makeContextCurrent(window);
            const adapter_options = c.MachDawnNativeAdapterDiscoveryOptions_OpenGLES{
                .getProc = @ptrCast(fn ([*c]const u8) callconv(.C) ?*anyopaque, glfw.getProcAddress),
            };
            _ = c.machDawnNativeInstance_discoverAdapters(instance, @enumToInt(backend), &adapter_options);
        },
        else => {
            c.machDawnNativeInstance_discoverDefaultAdapters(instance);
        },
    }
}
