shader_type spatial;
// Billboarded ribbon: each base ring of the orbit becomes two
// vertices, offset perpendicular to the line direction in *screen
// space* so the rendered thickness is uniform pixels regardless of
// camera distance / zoom. blend_mix gives us a real alpha channel
// (HP-derived opacity); cull_disabled keeps the ribbon visible
// whichever side faces the camera.
render_mode unshaded, cull_disabled, blend_mix;

uniform vec4 line_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float line_width_px : hint_range(0.5, 16.0) = 1.0;

void vertex() {
	// NORMAL holds the model-space tangent direction (current ring →
	// next ring). UV.x is the side flag, -1 or +1, identifying which
	// edge of the ribbon this duplicated vertex sits on. Tangent
	// magnitude is irrelevant — we normalise in screen space below —
	// so oct-encoding losing the length is harmless.
	vec3 tangent_dir = NORMAL;
	float side = UV.x;

	vec4 view_pos = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	vec4 view_nxt = MODELVIEW_MATRIX * vec4(VERTEX + tangent_dir, 1.0);
	vec4 clip_pos = PROJECTION_MATRIX * view_pos;
	vec4 clip_nxt = PROJECTION_MATRIX * view_nxt;

	vec2 vp = VIEWPORT_SIZE;
	float wp = max(abs(clip_pos.w), 1e-6);
	float wn = max(abs(clip_nxt.w), 1e-6);
	vec2 ndc_pos = clip_pos.xy / wp;
	vec2 ndc_nxt = clip_nxt.xy / wn;
	// Screen direction in pixels — NDC is [-1,1] over each axis.
	vec2 screen_delta = (ndc_nxt - ndc_pos) * vp * 0.5;
	float dlen = length(screen_delta);
	if (dlen >= 1e-6) {
		vec2 dir = screen_delta / dlen;
		vec2 perp = vec2(-dir.y, dir.x);
		// Half-width in pixels, then back to NDC (1 px = 2 / vp NDC).
		vec2 offset_ndc = perp * side * line_width_px / vp;
		clip_pos.xy += offset_ndc * clip_pos.w;
	}
	POSITION = clip_pos;
}

void fragment() {
	ALBEDO = line_color.rgb;
	ALPHA = line_color.a;
}
