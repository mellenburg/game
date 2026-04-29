shader_type sky;
// Procedural starfield. Hashed per cell on an octahedral projection of
// the view direction so stars are stable in world space and roughly
// uniformly distributed (no pole pinching like spherical UV). Cell
// scales are kept moderate and each star is clamped to at least one
// pixel wide via fwidth(), so rotating the camera doesn't make stars
// twinkle in and out of subpixel coverage.

uniform vec3 background_color : source_color = vec3(0.004, 0.004, 0.012);
uniform float density : hint_range(0.0, 0.2) = 0.040;
uniform float layer1_scale : hint_range(20.0, 800.0) = 220.0;
uniform float layer2_scale : hint_range(20.0, 800.0) = 420.0;
uniform vec3 star_tint : source_color = vec3(1.0, 0.97, 0.92);

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

vec2 octahedral(vec3 d) {
	d /= max(dot(abs(d), vec3(1.0)), 1e-6);
	vec3 a = abs(d);
	if (d.z < 0.0) {
		d.xy = (1.0 - vec2(a.y, a.x)) * sign(d.xy);
	}
	return d.xy * 0.5 + 0.5;
}

float star_layer(vec2 uv, float scale, float thresh) {
	vec2 g = uv * scale;
	// Compute pixel footprint up front (must be in uniform control
	// flow). Also clamps below to ~screen pixels in cell-units.
	float pixel = max(fwidth(g.x), fwidth(g.y));
	vec2 cell = floor(g);
	vec2 frac = fract(g) - 0.5;
	float h = hash21(cell);
	if (h <= thresh) {
		return 0.0;
	}
	float bright = (h - thresh) / max(1.0 - thresh, 1e-6);
	vec2 jitter = vec2(
		hash21(cell + vec2(17.3, 0.0)),
		hash21(cell + vec2(0.0, 91.7))
	) - 0.5;
	float d = length(frac - jitter * 0.7);
	// Star radius in cell-units; floor at ~1 pixel so the disc never
	// shrinks below one fragment as the camera rotates.
	float size = mix(0.05, 0.13, bright);
	size = max(size, pixel * 0.9);
	float aa = max(pixel * 0.5, 0.005);
	return smoothstep(size, max(size - aa, 0.0), d) * mix(0.35, 1.5, bright);
}

void sky() {
	vec3 dir = normalize(EYEDIR);
	vec2 uv = octahedral(dir);
	float thresh = 1.0 - density;
	float s = star_layer(uv, layer1_scale, thresh);
	s += star_layer(uv + vec2(0.37, 0.19), layer2_scale, thresh + 0.005) * 0.65;
	COLOR = background_color + star_tint * s;
}
