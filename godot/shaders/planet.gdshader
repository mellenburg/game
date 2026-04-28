shader_type spatial;
render_mode unshaded, cull_back;

uniform sampler2D albedo_texture : source_color;
uniform sampler2D night_texture : source_color;
uniform sampler2D normal_texture : hint_normal;
uniform vec3 sun_direction = vec3(1.0, 0.0, 0.0);

void fragment() {
	vec4 day = texture(albedo_texture, UV);
	vec4 night = texture(night_texture, UV);

	// NORMAL is in view space. Transform the world-space sun direction
	// into view space and dot — keeps everything in one frame.
	vec3 sun_view = normalize((VIEW_MATRIX * vec4(normalize(sun_direction), 0.0)).xyz);
	float lambert = clamp(dot(NORMAL, sun_view), -1.0, 1.0);

	float day_mix = smoothstep(-0.1, 0.1, lambert);
	vec3 lit_day = day.rgb * max(lambert, 0.05);
	vec3 lit_night = night.rgb * 0.9;

	ALBEDO = mix(lit_night, lit_day, day_mix);
}
