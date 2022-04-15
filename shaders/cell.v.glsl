#version 330 core

// The grid coordinates (x, y) where x < columns and y < rows
layout (location = 0) in vec2 grid_coord;

// The background color for this cell in RGBA (0 to 1.0)
layout (location = 1) in vec4 bg_color_in;

// The background color for this cell in RGBA (0 to 1.0)
flat out vec4 bg_color;

uniform vec2 cell_dims;
uniform mat4 projection;

vec3 hsv2rgb(vec3 c)
{
    vec4 K = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
    vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
    return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}

void main() {
    // Top-left cell coordinates converted to world space
    vec2 cell_pos = cell_dims * grid_coord;

    // Turn the cell position into a vertex point depending on the
    // gl_VertexID. Since we use instanced drawing, we have 4 vertices
    // for each corner of the cell. We can use gl_VertexID to determine
    // which one we're looking at. Using this, we can use 1 or 0 to keep
    // or discard the value for the vertex.
    vec2 position;
    position.x = (gl_VertexID == 0 || gl_VertexID == 1) ? 1. : 0.;
    position.y = (gl_VertexID == 0 || gl_VertexID == 3) ? 0. : 1.;
    cell_pos = cell_pos + cell_dims * position;

    gl_Position = projection * vec4(cell_pos, 1.0, 1.0);
    bg_color = vec4(hsv2rgb(bg_color_in.rgb), 1.0);
}
