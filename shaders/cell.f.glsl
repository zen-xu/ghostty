#version 330 core

/// The background color for this cell.
flat in vec4 bg_color;

void main() {
    gl_FragColor = bg_color;
}
