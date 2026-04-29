shader_type spatial;
render_mode unshaded, cull_back;

uniform sampler2D albedo_texture : source_color;
uniform sampler2D night_texture : source_color;
uniform sampler2D normal_texture : hint_normal;
uniform sampler2D clouds_texture : source_color;
uniform vec3 sun_direction = vec3(1.0, 0.0, 0.0);
uniform float cloud_opacity : hint_range(0.0, 1.0) = 0.85;

void fragment() {
	vec4 day = texture(albedo_texture, UV);
	vec4 night = texture(night_texture, UV);
	vec4 clouds = texture(clouds_texture, UV);

	// NORMAL is in view space. Transform the world-space sun direction
	// into view space and dot — keeps everything in one frame.
	vec3 sun_view = normalize((VIEW_MATRIX * vec4(normalize(sun_direction), 0.0)).xyz);
	float lambert = clamp(dot(NORMAL, sun_view), -1.0, 1.0);

	float day_mix = smoothstep(-0.1, 0.1, lambert);
	vec3 lit_day = day.rgb * max(lambert, 0.05);
	vec3 lit_night = night.rgb * 0.9;
	vec3 surface = mix(lit_night, lit_day, day_mix);

	// Cloud texture is grayscale; brightness == coverage. Lit by the
	// same lambert as the surface so they fade out at the terminator
	// and disappear on the night side.
	float cloud_alpha = clouds.r * cloud_opacity * day_mix;
	vec3 lit_clouds = clouds.rgb * max(lambert, 0.05);

	ALBEDO = mix(surface, lit_clouds, cloud_alpha);
}
