#version 330 core
in vec3 FragPos;
in vec3 Normal;
in vec2 TexCoords;

out vec4 color;

uniform vec3 viewPos;
uniform float opacity;
uniform sampler2D texture_diffuse1;
uniform sampler2D texture_diffuse2;
uniform sampler2D texture_specular1;
uniform sampler2D texture_ambient1;
uniform sampler2D texture_emissive1;
uniform sampler2D texture_height1;

void main()
{
    float shininess = 40.0f;
    float w = 1.0f;
    vec3 lightDir = vec3(-1.0f, 0.0f, 0.0f);
    vec4 lightAmbient = .1*vec4(1.0f, 1.0f, 1.0f, w);
    vec4 lightDiffuse = .9*vec4(1.0f, 1.0f, 1.0f, w);
    vec4 lightSpecular = -.15*vec4(1.0f, 1.0f, 1.0f, w);
    vec4 lightEmissive = vec4(1.0f, 1.0f, .80f, w);
    // Ambient
    vec4 ambient = lightAmbient * texture(texture_ambient1, TexCoords);

    // Diffuse
    //vec3 norm = normalize(Normal+(myspec*mapNorm));
    vec3 norm = normalize(Normal);
    float diff = max(dot(norm, -lightDir), 0.0);
    vec4 diffuse = lightDiffuse * diff * texture(texture_diffuse1, TexCoords);

    // Emissive
    // -.5*norm factor keeps the lights on into the day and before sunset
    float emm = -1*min(dot(norm, -lightDir-.5*norm), 0.0);
    vec4 emissive = lightEmissive * emm * texture(texture_emissive1, TexCoords);

    // Specular
    //Dont want bump to mess with diffusion. only use in spec
    norm = texture(texture_height1, TexCoords).rgb;
    norm = normalize(2*norm - 1.0);
    vec3 viewDir = normalize(viewPos - FragPos);
    vec3 reflectDir = reflect(vec3(lightDir), norm);
    float spec = pow(max(dot(viewDir, reflectDir), 0.0), shininess);
    //vec4 specular = lightSpecular * spec * texture(texture_specular1, TexCoords);
    vec4 specular = lightSpecular * spec * vec4(1.0f, 1.0f, 1.0f, 1.0f);

    color = vec4(vec3(ambient + diffuse + specular + emissive), opacity);
}
