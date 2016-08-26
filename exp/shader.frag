#version 330 core
struct Light {
    vec3 direction;

    vec3 ambient;
    vec3 diffuse;
    vec3 specular;
};

in vec3 FragPos;
in vec3 Normal;
in vec2 TexCoords;

out vec4 color;

uniform vec3 viewPos;
uniform Light light;
uniform float shininess;
uniform sampler2D texture_diffuse1;
uniform sampler2D texture_specular1;
uniform sampler2D texture_ambient1;
uniform sampler2D texture_opacity1;

void main()
{
    // Ambient
    vec4 ambient = vec4(light.ambient, 1.0f) * texture(texture_ambient1, TexCoords);
    //vec3 ambient = light.ambient * vec3(texture(texture_ambient1, TexCoords));

    // Diffuse
    //vec4 norm = vec4(normalize(Normal), 1.0f);
    vec4 norm = normalize(vec4(Normal, 1.0f));
    //vec3 norm = normalize(Normal);
    //vec4 lightDir = vec4(normalize(-light.direction), 1.0f);
    vec4 lightDir = normalize(vec4(-light.direction, 1.0f));
    //vec3 lightDir = normalize(-light.direction);
    float diff = max(dot(norm, lightDir), 0.0);
    vec4 diffuse = vec4(light.diffuse, 1.0f) * diff * texture(texture_diffuse1, TexCoords);
    //vec3 diffuse = light.diffuse * diff * vec3(texture(texture_diffuse1, TexCoords));

    // Specular
    vec3 viewDir = normalize(viewPos - FragPos);
    vec4 reflectDir = reflect(-lightDir, norm);
    //vec3 reflectDir = reflect(-lightDir, norm);
    float spec = pow(max(dot(viewDir, vec3(reflectDir)), 0.0), shininess);
    vec4 specular = vec4(light.specular, 1.0f) * spec * texture(texture_specular1, TexCoords);
    //vec3 specular = light.specular * spec * vec3(texture(texture_specular1, TexCoords));

    //vec4 texColor = vec4(ambient + diffuse + specular, .50f);
    //vec4 texColor = (ambient + diffuse + specular) * texture(texture_opacity1, TexCoords);
    vec4 texColor = (ambient + diffuse + specular);
    if(texColor.a < 0.1)
        discard;
    color = texColor;
}
