#version 330 core

in vec2 glyph_tex_coords;

// The color for this cell. If this is a background pass this is the
// background color. Otherwise, this is the foreground color.
flat in vec4 color;

// Font texture
uniform sampler2D text;

// Background or foreground pass.
uniform int background;

void main() {
    if (background == 1) {
        gl_FragColor = color;
    } else {
        float a = texture(text, glyph_tex_coords).r;
        gl_FragColor = vec4(color.rgb, color.a*a);
    }
}
