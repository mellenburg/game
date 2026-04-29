shader_type spatial;
// Additive, unshaded, no depth write — but depth test is on so the
// Earth (which writes depth normally) occludes the disc when the sun
// is behind the planet. cull_disabled lets the quad face either way
// after the manual billboard transform.
render_mode unshaded, blend_add, depth_draw_never, cull_disabled;

uniform vec3 core_color : source_color = vec3(1.0, 0.99, 0.95);
uniform vec3 corona_color : source_color = vec3(1.0, 0.7, 0.35);
uniform float core_radius : hint_range(0.0, 0.5) = 0.11;
uniform float corona_radius : hint_range(0.0, 0.5) = 0.22;
uniform float core_intensity : hint_range(0.0, 8.0) = 4.0;
uniform float corona_intensity : hint_range(0.0, 4.0) = 0.6;

void vertex() {
	// Manual billboard: zero out the rotation in model-view so the quad's
	// local XY axes map to view-space XY (always parallel to the screen).
	// Translation is the world position transformed into view space.
	MODELVIEW_MATRIX = mat4(
		vec4(1.0, 0.0, 0.0, 0.0),
		vec4(0.0, 1.0, 0.0, 0.0),
		vec4(0.0, 0.0, 1.0, 0.0),
		VIEW_MATRIX * MODEL_MATRIX[3]
	);
}

void fragment() {
	float r = length(UV - vec2(0.5));
	// Bright, near-uniform disc that softens to its edge — additive
	// blending blows the centre out to white so it reads as hot.
	float core = (1.0 - smoothstep(core_radius * 0.7, core_radius, r)) * core_intensity;
	// Tight halo around the disc. pow(1-t, 5) makes it fall off fast so
	// it doesn't read as a lens-flare bloom across the screen.
	float t = clamp(r / corona_radius, 0.0, 1.0);
	float corona = pow(1.0 - t, 5.0) * corona_intensity;
	ALBEDO = core_color * core + corona_color * corona;
}
