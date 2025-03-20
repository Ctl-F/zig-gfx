#version 330 core
layout(location = 0) in vec3 v_Position;
layout(location = 1) in vec2 v_Uv;
layout(location = 2) in vec3 v_Color;

out vec2 f_Uv;
out vec3 f_Color;

uniform mat4 u_Projection;

void main(){
    gl_Position = u_Projection * vec4(v_Position, 1.0);
    f_Uv = v_Uv;
    f_Color = v_Color;
}