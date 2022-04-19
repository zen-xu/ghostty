#version 330 core

in vec2 glyph_tex_coords;
flat in uint mode;

// The color for this cell. If this is a background pass this is the
// background color. Otherwise, this is the foreground color.
flat in vec4 color;

// Font texture
uniform sampler2D text;

// See fragment shader
const uint MODE_BG = 1u;
const uint MODE_FG = 2u;

void main() {
    switch (mode) {
    case MODE_BG:
        gl_FragColor = color;
        break;

    case MODE_FG:
        float a = texture(text, glyph_tex_coords).r;
        gl_FragColor = vec4(color.rgb, color.a*a);
        break;
    }
}
