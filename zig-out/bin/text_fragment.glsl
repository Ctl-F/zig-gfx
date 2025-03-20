#version 330 core
out vec4 FragColor;

in vec2 f_Uv;
in vec3 f_Color;

uniform sampler2D u_Atlas;

void main(){
    FragColor = vec4(f_Color, texture(u_Atlas, f_Uv).r);
}