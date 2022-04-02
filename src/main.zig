const std = @import("std");
const glfw = @import("glfw");
const gl = @import("opengl.zig");
const c = gl.c;

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
    const program = try gl.Program.create();
    defer program.destroy();
    try program.attachShader(vs);
    try program.attachShader(fs);
    try program.link();
    vs.destroy();
    fs.destroy();

    // Create our bufer or vertices
    const vertices = [_]f32{
        -0.5, -0.5, 0.0, // left
        0.5, -0.5, 0.0, // right
        0.0, 0.5, 0.0, // top
    };
    const vao = try gl.VertexArray.create();
    defer vao.destroy();
    const vbo = try gl.Buffer.create();
    defer vbo.destroy();
    try vao.bind();
    var binding = try vbo.bind(c.GL_ARRAY_BUFFER);
    try binding.setData(&vertices, c.GL_STATIC_DRAW);
    try binding.vertexAttribPointer(0, 3, c.GL_FLOAT, false, 3 * @sizeOf(f32), null);
    try binding.enableVertexAttribArray(0);

    binding.unbind();
    try gl.VertexArray.unbind();

    // Wait for the user to close the window.
    while (!window.shouldClose()) {
        // Setup basic OpenGL settings
        c.glClearColor(0.2, 0.3, 0.3, 1.0);
        c.glClear(c.GL_COLOR_BUFFER_BIT);

        try program.use();
        try vao.bind();
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
