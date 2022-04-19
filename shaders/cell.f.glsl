#version 330 core

in vec2 glyph_tex_coords;

/// The background color for this cell.
flat in vec4 bg_color;

/// Font texture
uniform sampler2D text;

void main() {
    int background = 0;
    if (background == 1) {
        gl_FragColor = bg_color;
    } else {
        float a = texture(text, glyph_tex_coords).r;
        gl_FragColor = vec4(bg_color.rgb, bg_color.a*a);
    }
}
