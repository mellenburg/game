// Reproject an equirectangular Earth texture into Web Mercator on the
// fly. Runs as a CanvasItem fragment shader so the map overlay can use
// the existing 4096_earth.jpg without a CPU image-resample pass.
//
// UV maps: x in [0,1] → longitude in [-180, 180]; y in [0,1] →
// Mercator y, clamped to ±lat_clamp_deg latitude. We invert the
// Mercator y → latitude formula in-shader and resample the source
// equirectangular texture at the geographic UV.
shader_type canvas_item;

uniform sampler2D source : source_color;
uniform float lat_clamp_deg : hint_range(60.0, 89.0) = 85.0;

void fragment() {
	float u = UV.x;
	float y_norm = UV.y;
	float clamp_rad = radians(lat_clamp_deg);
	// Mercator y at the clamp latitude — used to scale UV.y so the
	// clamped pole sits exactly at the top/bottom edge of the rect.
	float max_y = log(tan(0.7853981633974483 + clamp_rad * 0.5));
	float merc_y = (1.0 - 2.0 * y_norm) * max_y;
	float lat_rad = 2.0 * atan(exp(merc_y)) - 1.5707963267948966;
	float v = 0.5 - lat_rad / 3.141592653589793;
	COLOR = texture(source, vec2(u, v));
}
