shader_type spatial;
render_mode unshaded, cull_back;
// Procedural Mars surface. Drop-in replacement for planet.gdshader on
// the Mars stage — same vertex / interface contract (sun_direction
// uniform, lambert lighting, world-space sphere) but the day-side
// albedo, relief shading, and polar caps are computed in-fragment from
// hashed noise rather than sampled from on-disk JPEGs. The repo ships
// no Mars texture assets and the build environment is offline, so
// generating the surface in-shader is the way to deliver a "similar
// quality to the Earth map" feel without an external texture set.
//
// Quality notes
//   * Albedo is layered fBm sampled in *world* space (the sphere has
//     unit radius after dividing the model-space VERTEX); this keeps
//     the noise frame stationary as the planet rotates beneath it,
//     which is wrong physically but identical to the way Earth's
//     baked albedo doesn't shift as the mesh spins.
//   * Polar caps fade in via abs(sin(latitude)) so the cap edge has a
//     proper irregular fingering instead of a clean ring.
//   * Relief shading derives a fake normal from finite differences of
//     the elevation field. The differences live in tangent space
//     (longitude / latitude steps), so the lambert dot stays well-
//     conditioned at the poles where the longitude derivative
//     collapses.

uniform vec3 sun_direction = vec3(1.0, 0.0, 0.0);

const vec3 COLOR_LOWLAND = vec3(0.45, 0.18, 0.10);
const vec3 COLOR_MIDLAND = vec3(0.71, 0.36, 0.20);
const vec3 COLOR_HIGHLAND = vec3(0.84, 0.55, 0.34);
const vec3 COLOR_CRATER = vec3(0.30, 0.13, 0.08);
const vec3 COLOR_POLAR_CAP = vec3(0.94, 0.93, 0.90);

// Hash → noise primitives. Standard "fract sin dot" hash. Avoids
// hash-explosion artefacts for the |dot| < 100 input range we feed
// it; values outside that range never appear here.
float hash3(vec3 p) {
	return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453);
}

float value_noise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	vec3 u = f * f * (3.0 - 2.0 * f);  // smoothstep blend
	float n000 = hash3(i + vec3(0.0, 0.0, 0.0));
	float n100 = hash3(i + vec3(1.0, 0.0, 0.0));
	float n010 = hash3(i + vec3(0.0, 1.0, 0.0));
	float n110 = hash3(i + vec3(1.0, 1.0, 0.0));
	float n001 = hash3(i + vec3(0.0, 0.0, 1.0));
	float n101 = hash3(i + vec3(1.0, 0.0, 1.0));
	float n011 = hash3(i + vec3(0.0, 1.0, 1.0));
	float n111 = hash3(i + vec3(1.0, 1.0, 1.0));
	float nx00 = mix(n000, n100, u.x);
	float nx10 = mix(n010, n110, u.x);
	float nx01 = mix(n001, n101, u.x);
	float nx11 = mix(n011, n111, u.x);
	float nxy0 = mix(nx00, nx10, u.y);
	float nxy1 = mix(nx01, nx11, u.y);
	return mix(nxy0, nxy1, u.z);
}

// 5-octave fBm. Each octave doubles the frequency and halves the
// amplitude — the conventional 1/f spectrum that produces the natural-
// looking continental / regional / detail layering Mars needs.
float fbm(vec3 p) {
	float total = 0.0;
	float amp = 0.5;
	float freq = 1.0;
	for (int i = 0; i < 5; ++i) {
		total += value_noise(p * freq) * amp;
		freq *= 2.0;
		amp *= 0.5;
	}
	return total;
}

// Combined elevation field: continental fBm at low frequency + a
// stronger ridge-pass to give the highlands a faulted look.
float elevation(vec3 dir) {
	float continental = fbm(dir * 1.6);
	float ridge = 1.0 - abs(fbm(dir * 3.5) - 0.5) * 2.0;
	return clamp(continental * 0.7 + ridge * 0.3, 0.0, 1.0);
}

// Cratering pass — a sparse hash-driven mask so the eye reads "impact
// scarring" without a full per-crater stamp loop. Sampling at multiple
// scales gives a believable size distribution.
float crater_mask(vec3 dir) {
	float c1 = smoothstep(0.55, 0.62, value_noise(dir * 14.0));
	float c2 = smoothstep(0.62, 0.70, value_noise(dir * 28.0));
	return clamp(c1 * 0.7 + c2 * 0.5, 0.0, 1.0);
}

void fragment() {
	// Object-space surface direction. The sphere is centered at the
	// model origin, so VERTEX points outward from the centre and its
	// normalisation is the unit-sphere coordinate of this fragment.
	// Sampling noise here (rather than in world space) anchors the
	// surface features to the mesh, so they rotate with the planet's
	// daily spin instead of appearing fixed to the world frame.
	vec3 dir = normalize(VERTEX);

	float elev = elevation(dir);
	float crater = crater_mask(dir);

	vec3 base_color;
	if (elev < 0.45) {
		base_color = mix(COLOR_LOWLAND, COLOR_MIDLAND,
			smoothstep(0.0, 0.45, elev));
	} else {
		base_color = mix(COLOR_MIDLAND, COLOR_HIGHLAND,
			smoothstep(0.45, 1.0, elev));
	}
	base_color = mix(base_color, COLOR_CRATER, crater * 0.65);

	// Polar caps. dir.z (in pole-aligned object space, which is what
	// dir is here after the model rotation) approximates sin(latitude).
	// Fringe noise breaks the cap edge.
	float lat_abs = abs(dir.z);
	float cap_edge = value_noise(dir * 9.0);
	float cap_blend = smoothstep(0.78, 0.95, lat_abs + cap_edge * 0.08);
	base_color = mix(base_color, COLOR_POLAR_CAP, cap_blend);

	// Faux relief — finite-difference the elevation field along two
	// orthogonal tangents to derive a perturbed object-space normal.
	// `eps` tunes the bump amplitude; large enough to read on the
	// camera's standoff distance without producing per-fragment dot
	// artefacts.
	vec3 tangent_a = normalize(cross(dir, vec3(0.0, 0.0, 1.0)) + vec3(1e-5));
	vec3 tangent_b = cross(dir, tangent_a);
	float eps = 0.02;
	float ea = elevation(normalize(dir + tangent_a * eps));
	float eb = elevation(normalize(dir + tangent_b * eps));
	vec3 perturbed_obj = normalize(
		dir + tangent_a * (ea - elev) * 4.0 + tangent_b * (eb - elev) * 4.0
	);

	// Lambert in view space, matching the Earth shader's frame. The
	// perturbed normal is in object space → world via MODEL_MATRIX (the
	// sphere is uniformly scaled so a direct multiply preserves the
	// unit length up to renormalisation) → view via VIEW_MATRIX.
	vec3 perturbed_world = normalize((MODEL_MATRIX * vec4(perturbed_obj, 0.0)).xyz);
	vec3 perturbed_view = normalize((VIEW_MATRIX * vec4(perturbed_world, 0.0)).xyz);
	vec3 sun_view = normalize((VIEW_MATRIX * vec4(normalize(sun_direction), 0.0)).xyz);
	float lambert = clamp(dot(perturbed_view, sun_view), -1.0, 1.0);

	float day_mix = smoothstep(-0.1, 0.1, lambert);
	vec3 lit = base_color * max(lambert, 0.05);
	// Night side: dim ambient red so the dark limb still reads as Mars
	// rather than a black silhouette.
	vec3 dark = base_color * 0.06;
	ALBEDO = mix(dark, lit, day_mix);
}
