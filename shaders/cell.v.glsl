#version 330 core

// The grid coordinates (x, y) where x < columns and y < rows
layout (location = 0) in vec2 grid_coord;

// Position of the glyph in the texture.
layout (location = 1) in vec2 glyph_pos;

// Width/height of the glyph
layout (location = 2) in vec2 glyph_size;

// Offset of the top-left corner of the glyph when rendered in a rect.
layout (location = 3) in vec2 glyph_offset;

// The background color for this cell in RGBA (0 to 1.0)
layout (location = 4) in vec4 bg_color_in;

// The background color for this cell in RGBA (0 to 1.0)
flat out vec4 bg_color;

// The x/y coordinate for the glyph representing the font.
out vec2 glyph_tex_coords;

uniform sampler2D text;
uniform vec2 cell_size;
uniform mat4 projection;

void main() {
    // Top-left cell coordinates converted to world space
    // Example: (1,0) with a 30 wide cell is converted to (30,0)
    vec2 cell_pos = cell_size * grid_coord;

    // Turn the cell position into a vertex point depending on the
    // gl_VertexID. Since we use instanced drawing, we have 4 vertices
    // for each corner of the cell. We can use gl_VertexID to determine
    // which one we're looking at. Using this, we can use 1 or 0 to keep
    // or discard the value for the vertex.
    //
    // 0 = top-right
    // 1 = bot-right
    // 2 = bot-left
    // 3 = top-left
    vec2 position;
    position.x = (gl_VertexID == 0 || gl_VertexID == 1) ? 1. : 0.;
    position.y = (gl_VertexID == 0 || gl_VertexID == 3) ? 0. : 1.;

    int background = 0;
    if (background == 1) {
        // Calculate the final position of our cell in world space.
        // We have to add our cell size since our vertices are offset
        // one cell up and to the left. (Do the math to verify yourself)
        cell_pos = cell_pos + cell_size * position;

        gl_Position = projection * vec4(cell_pos, 0.0, 1.0);
        bg_color = vec4(bg_color_in.rgb / 255.0, 1.0);
    } else {
        // TODO: why?
        vec2 glyph_offset_calc = glyph_offset;
        glyph_offset_calc.y = cell_size.y - glyph_offset.y;

        // Calculate the final position of the cell.
        cell_pos = cell_pos + glyph_size * position + glyph_offset_calc;
        gl_Position = projection * vec4(cell_pos, 0.0, 1.0);

        // Calculate our texture coordinate
        ivec2 text_size = textureSize(text, 0);
        vec2 glyph_tex_size = glyph_size / text_size.xy;
        glyph_tex_coords = glyph_pos + glyph_tex_size * position;

        // This is used to color the font for now.
        bg_color = vec4(bg_color_in.rgb / 255.0, 1.0);
    }
}
