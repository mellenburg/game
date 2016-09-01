#version 330 core
in vec3 ourColor;

uniform vec3 setColor;

out vec4 color;

void main()
{
    color = vec4(setColor, 1.0f);
    //color = vec4(1.0f, 1.0f, 1.0f, 1.0f);
}
