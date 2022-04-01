const std = @import("std");
const glfw = @import("glfw");
const c = @import("c.zig");
const gl = @import("opengl.zig");

pub fn main() !void {
    try glfw.init(.{});
    defer glfw.terminate();

    // Create our window
    const window = try glfw.Window.create(640, 480, "ghostty", null, null, .{
        .context_version_major = 3,
        .context_version_minor = 3,
        .opengl_profile = .opengl_core_profile,
        .opengl_forward_compat = true,
    });
    defer window.destroy();

    // Setup OpenGL
    try glfw.makeContextCurrent(window);
    try glfw.swapInterval(1);
    window.setSizeCallback((struct {
        fn callback(_: glfw.Window, width: i32, height: i32) void {
            std.log.info("set viewport {} {}", .{ width, height });
            c.glViewport(0, 0, width, height);
        }
    }).callback);

    // Create our vertex shader
    const vs = try gl.Shader.create(gl.c.GL_VERTEX_SHADER);
    try vs.setSourceAndCompile(vs_source);
    defer vs.destroy();

    const fs = try gl.Shader.create(gl.c.GL_FRAGMENT_SHADER);
    try fs.setSourceAndCompile(fs_source);
    defer fs.destroy();

    // Shader program
    const program = c.glCreateProgram();
    c.glAttachShader(program, vs.handle);
    c.glAttachShader(program, fs.handle);
    c.glLinkProgram(program);
    var success: c_int = undefined;
    c.glGetProgramiv(program, c.GL_LINK_STATUS, &success);
    if (success != c.GL_TRUE) {
        var msg: [512]u8 = undefined;
        c.glGetProgramInfoLog(program, 512, null, &msg);
        std.log.err("program fail: {s}\n", .{std.mem.sliceTo(&msg, 0)});
        return;
    }
    c.glDeleteShader(vs.handle);
    c.glDeleteShader(fs.handle);

    // Create our bufer or vertices
    const vertices = [_]f32{
        -0.5, -0.5, 0.0, // left
        0.5, -0.5, 0.0, // right
        0.0, 0.5, 0.0, // top
    };
    var vao: c_uint = undefined;
    var vbo: c_uint = undefined;
    c.glGenVertexArrays(1, &vao);
    c.glGenBuffers(1, &vbo);
    c.glBindVertexArray(vao);

    c.glBindBuffer(c.GL_ARRAY_BUFFER, vbo);
    c.glBufferData(
        c.GL_ARRAY_BUFFER,
        @as(isize, @sizeOf(@TypeOf(vertices))),
        &vertices,
        c.GL_STATIC_DRAW,
    );

    c.glVertexAttribPointer(
        0,
        3,
        c.GL_FLOAT,
        c.GL_FALSE,
        3 * @sizeOf(f32),
        null,
    );
    c.glEnableVertexAttribArray(0);

    c.glBindBuffer(c.GL_ARRAY_BUFFER, 0);
    c.glBindVertexArray(0);

    // Wait for the user to close the window.
    while (!window.shouldClose()) {
        // Setup basic OpenGL settings
        c.glClearColor(0.2, 0.3, 0.3, 1.0);
        c.glClear(c.GL_COLOR_BUFFER_BIT);

        c.glUseProgram(program);
        c.glBindVertexArray(vao);
        c.glDrawArrays(c.GL_TRIANGLES, 0, 3);

        // const pos = try window.getCursorPos();
        // std.log.info("CURSOR: {}", .{pos});

        try window.swapBuffers();
        try glfw.waitEvents();
    }
}

const vs_source =
    \\#version 330 core
    \\layout (location = 0) in vec3 aPos;
    \\
    \\void main()
    \\{
    \\    gl_Position = vec4(aPos.x, aPos.y, aPos.z, 1.0);
    \\}
;

const fs_source =
    \\#version 330 core
    \\out vec4 FragColor;
    \\
    \\void main()
    \\{
    \\    FragColor = vec4(1.0f, 0.5f, 0.2f, 1.0f);
    \\}
;
