#version 330 core
in vec3 FragPos;
in vec3 Normal;
in vec2 TexCoords;

out vec4 color;

uniform vec3 viewPos;
uniform float opacity;
uniform sampler2D texture_diffuse1;
uniform sampler2D texture_diffuse2; // No clouds
uniform sampler2D texture_ambient1;
uniform sampler2D texture_emissive1;
uniform sampler2D texture_height1;

void main()
{
    float w = 1.0f;
    vec3 lightDir = vec3(-1.0f, 0.0f, 0.0f);
    vec4 lightAmbient = .1*vec4(1.0f, 1.0f, 1.0f, w);
    vec4 lightDiffuse = vec4(1.0f, 1.0f, 1.0f, w);
    vec4 lightSpecular = -0.07f*vec4(1.0f, 1.0f, 1.0f, w);
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

    // Bump map hack
    norm = texture(texture_height1, TexCoords).rgb;
    norm = normalize(2*norm - 1.0);
    vec3 reflectDir = reflect(vec3(lightDir), norm);
    float bump_f = pow(dot(lightDir, reflectDir), 100.0f);
    vec4 bump = lightSpecular * bump_f * vec4(1.0f, 1.0f, 1.0f, 1.0f);

    color = vec4(vec3(ambient + diffuse + bump + emissive), opacity);
}
