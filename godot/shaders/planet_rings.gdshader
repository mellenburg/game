shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_opaque;

// Equirectangular-mapped ring strip. UV.x walks the radial axis from the
// inner mesh edge (D ring inner) at u=0 to the outer mesh edge (F ring
// outer) at u=1; UV.y is meaningless (the strip is 1D in radius) and
// the mesh emits y=0 everywhere. Texture's alpha is the ring's optical
// thickness; the planet's shadow knocks alpha down further on fragments
// that sit behind the body relative to the sun.
uniform sampler2D ring_texture : source_color;
// World-space sun direction. Must match planet.gdshader's value so the
// terminator on Saturn and the shadow on the rings line up.
uniform vec3 sun_direction = vec3(1.0, 0.0, 0.0);
// Body radius in scene units (1 unit = 1000 km). Saturn's bounding
// sphere is the occluder for the ring shadow check.
uniform float body_radius_scene : hint_range(1.0, 500.0) = 60.268;
// Penumbra width measured in scene units along the perpendicular from
// the sun-body axis. The shadow softens linearly between
// (body_radius_scene) and (body_radius_scene + penumbra_scene); set to
// match the apparent angular size of the sun at the body's distance —
// for Saturn at 9.5 AU the umbra/penumbra blur is very narrow, so we
// keep this small relative to the body radius.
uniform float penumbra_scene : hint_range(0.0, 50.0) = 1.5;
// Brightness lift on the sun-facing hemisphere of the disc — the rings
// scatter Mie-like, so the side of the disc lit by the sun reads
// brighter than the dark side. Lambertian fades to ambient as the disc
// normal turns away from the sun.
uniform float lit_face_strength : hint_range(0.0, 2.0) = 1.0;
uniform float ambient : hint_range(0.0, 1.0) = 0.18;

varying vec3 world_pos;
varying vec3 world_normal;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec4 sample = texture(ring_texture, UV);
	if (sample.a < 0.001) {
		discard;
	}

	vec3 d = normalize(sun_direction);

	// Hemisphere lighting. The disc is two-sided; we want the face
	// pointing toward the sun to read brighter than the face pointing
	// away. NORMAL on the back face flips, so a single dot(N, d) per
	// fragment captures the asymmetry correctly without explicit cull.
	float facing = clamp(dot(world_normal, d), -1.0, 1.0);
	float lit = ambient + max(facing, 0.0) * lit_face_strength;

	// Saturn's shadow on the disc. Project the fragment's world-space
	// position onto the sun direction; t < 0 puts the fragment on the
	// anti-sun side. The perpendicular distance from the fragment to
	// the sun-body axis (the body sits at world origin) tells us
	// whether Saturn is between the fragment and the sun. Inside the
	// umbra the light contribution drops to zero; the penumbra band
	// linearly blends back to fully lit so the shadow edge isn't a
	// crisp aliased line.
	float t = dot(world_pos, d);
	float shadow = 1.0;
	if (t < 0.0) {
		vec3 perp = world_pos - t * d;
		float dist = length(perp);
		float inner = body_radius_scene;
		float outer = body_radius_scene + penumbra_scene;
		shadow = clamp((dist - inner) / max(outer - inner, 0.001), 0.0, 1.0);
	}

	// The shadow only attenuates the *sun-driven* lit term; the ambient
	// floor stays so the dark side of the disc isn't pitch black.
	float lit_with_shadow = ambient + max(facing, 0.0) * lit_face_strength * shadow;
	vec3 color = sample.rgb * lit_with_shadow;

	ALBEDO = color;
	ALPHA = sample.a;
}
