shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_lambert, specular_schlick_ggx;

uniform sampler2D albedo_texture : source_color;
uniform sampler2D night_texture : source_color;
uniform sampler2D normal_texture : hint_normal;
uniform float normal_scale : hint_range(-16, 16) = 1.0;
uniform vec3 sun_direction = vec3(1.0, 0.0, 0.0);

void fragment() {
	ALBEDO = texture(albedo_texture, UV).rgb;
	NORMAL_MAP = texture(normal_texture, UV).rgb;
	NORMAL_MAP_DEPTH = normal_scale;
	SPECULAR = 0.2;
	ROUGHNESS = 0.8;

	// Night lights on the dark side
	float sun_dot = dot(NORMAL, normalize(sun_direction));
	float night_blend = smoothstep(-0.1, -0.3, sun_dot);
	EMISSION = texture(night_texture, UV).rgb * night_blend * 1.5;
}
