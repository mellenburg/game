shader_type spatial;
render_mode unshaded, cull_back;

uniform sampler2D albedo_texture : source_color;
uniform sampler2D night_texture : source_color;
uniform sampler2D normal_texture : hint_normal;
uniform sampler2D clouds_texture : source_color;
uniform vec3 sun_direction = vec3(1.0, 0.0, 0.0);
uniform float cloud_opacity : hint_range(0.0, 1.0) = 0.85;
// Background / starlight floor on the night hemisphere — enough that
// the dark limb reads as a planet rather than a black silhouette
// against the skybox. Applied as a small fraction of the day-side
// albedo, so the unlit terrain reads in the body's own colour
// (rust on Mars, slate-blue on Earth) instead of a flat grey wash.
// 4% matches the order of magnitude of moonlight + integrated
// starlight against full daylight.
uniform float ambient_strength : hint_range(0.0, 0.2) = 0.04;

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
	// Ambient floor sourced from the body's own albedo so the night
	// hemisphere keeps Mars red (or Earth slate-blue) instead of going
	// flat grey. Added to the lit_night contribution rather than max'd
	// against it so Earth's city lights still punch through cleanly.
	vec3 ambient = day.rgb * ambient_strength;
	vec3 surface = mix(lit_night + ambient, lit_day, day_mix);

	// Cloud texture is grayscale; brightness == coverage. Lit by the
	// same lambert as the surface so they fade out at the terminator
	// and disappear on the night side.
	float cloud_alpha = clouds.r * cloud_opacity * day_mix;
	vec3 lit_clouds = clouds.rgb * max(lambert, 0.05);

	ALBEDO = mix(surface, lit_clouds, cloud_alpha);
}
