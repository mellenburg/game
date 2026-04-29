shader_type canvas_item;
render_mode blend_add;

uniform vec2 sun_uv = vec2(0.5);
uniform float intensity : hint_range(0.0, 1.0) = 0.0;
// Viewport aspect (width / height) — used to keep ghost discs round.
uniform float aspect = 1.0;
uniform vec3 tint : source_color = vec3(1.0, 0.85, 0.55);
uniform vec3 cold_tint : source_color = vec3(0.45, 0.7, 1.0);

// Anisotropic gaussian blob in aspect-corrected screen space.
float blob(vec2 p, vec2 c, float r) {
	vec2 d = p - c;
	float k = dot(d, d) / (r * r);
	return exp(-k);
}

void fragment() {
	if (intensity <= 0.0) {
		COLOR = vec4(0.0, 0.0, 0.0, 0.0);
	} else {
		// Center the working space and correct for aspect so circles
		// stay circular regardless of window shape.
		vec2 p = (UV - vec2(0.5)) * vec2(aspect, 1.0);
		vec2 sun = (sun_uv - vec2(0.5)) * vec2(aspect, 1.0);
		// Direction from sun toward screen center.
		vec2 axis = -sun;

		vec3 col = vec3(0.0);

		// A handful of ghosts spaced along the sun-to-center axis. The
		// alternating warm/cold tint mimics the chromatic separation
		// you see through real coated lenses.
		col += tint      * blob(p, sun + axis * 0.30, 0.030) * 0.55;
		col += cold_tint * blob(p, sun + axis * 0.55, 0.022) * 0.40;
		col += tint      * blob(p, sun + axis * 0.78, 0.055) * 0.60;
		col += cold_tint * blob(p, sun + axis * 1.10, 0.028) * 0.35;
		col += tint      * blob(p, sun + axis * 1.35, 0.045) * 0.45;
		col += tint      * blob(p, sun + axis * 1.65, 0.018) * 0.30;

		// Soft halo ring around screen center.
		float d_center = length(p);
		float halo = exp(-pow(d_center - 0.22, 2.0) / 0.004);
		col += tint * halo * 0.18;

		// Anamorphic horizontal streak through the sun position.
		vec2 from_sun = p - sun;
		float streak = exp(-(from_sun.y * from_sun.y) / 0.0010)
		             * exp(-(from_sun.x * from_sun.x) / 0.50);
		col += tint * streak * 0.35;

		// Bright bloom glow on the sun itself, pillowed out beyond the
		// 3D billboard so the disc reads as actually bright.
		col += tint * blob(p, sun, 0.06) * 0.9;

		COLOR = vec4(col * intensity, 1.0);
	}
}
