#version 330 core

in vec2 TexCoords;
in vec4 VertexColor;

uniform sampler2D text;

void main()
{
    float a = texture(text, TexCoords).r;
    gl_FragColor = vec4(VertexColor.rgb, VertexColor.a*a);
}
