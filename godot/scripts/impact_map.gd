class_name ImpactMap
extends Control
## Mercator-projected world map overlay with markers at every recorded
## meteorite impact. The map background is the same 4096_earth.jpg the
## globe uses, reprojected to Web Mercator on the GPU by a small
## canvas-item shader; that avoids a CPU resample on startup and keeps
## the rendering side compatible with the project's GL Compatibility
## constraint.
##
## The map node is a TextureRect child sized at MAP_SIZE. Markers are
## drawn by an inner _MarkerLayer Control added AFTER the map, so
## Godot's back-to-front child draw order paints them on top of the
## basemap rather than under it.

const ImpactTracker = preload("res://scripts/impact_tracker.gd")
const Satellite = preload("res://scripts/satellite.gd")

# Inner Control that draws the impact markers and grid. Lives as a
# child of ImpactMap, added AFTER the map TextureRect so Godot's
# back-to-front draw order paints these on top of the basemap. The
# parent passes its position/size + tracker reference through the
# `configure()` call below.
class _MarkerLayer extends Control:
	# Re-declared inside the inner class because GDScript inner classes
	# don't inherit the outer file's preload constants. Same script,
	# same instance — the parent passes its tracker straight through.
	const _Tracker = preload("res://scripts/impact_tracker.gd")
	var tracker: _Tracker = null
	# Bound to EarthSystem.real_satellites; the layer filters for
	# is_surface each draw call so newly-placed or destroyed surface
	# installations show up without any signal plumbing. Plain Array
	# typing because the inner class can't reach the outer file's typed-
	# array element binding cleanly — same idiom RadarMap uses for its
	# wave list.
	var satellites: Array = []
	var origin: Vector2 = Vector2.ZERO
	var map_size: Vector2 = Vector2.ZERO
	var lat_clamp_deg: float = 85.0
	var grid_color: Color = Color(0.6, 0.7, 0.85, 0.18)
	var marker_outer: Color = Color(1.0, 0.25, 0.05, 0.95)
	var marker_inner: Color = Color(1.0, 0.85, 0.4, 0.95)
	var marker_radius: float = 4.0
	# HP-driven marker scaling envelope. Same log-decade idiom the
	# 3D ImpactExplosion uses, applied to the 2D dot radius so a
	# heavy impactor draws a visibly fatter splat than a battered
	# straggler. Floor + ceiling tuned against marker_radius so the
	# smallest dots stay readable and the largest don't swamp
	# adjacent impacts on the Mercator overlay.
	var marker_hp_ref_min: float = 10.0
	var marker_hp_log_decades: float = 3.0
	var marker_min_scale: float = 0.6
	var marker_max_scale: float = 2.0
	# Surface-installation marker palette: green to match the in-world
	# COLOR_SURFACE tint, distinct from the red/orange impact dots so
	# the two readouts coexist on the same map without ambiguity.
	# Squares (drawn by _draw_rect) instead of circles so the eye can
	# tell at a glance which markers are friendly emplacements vs.
	# meteorite impacts at the same lat/lon.
	var surface_outer: Color = Color(0.85, 1.0, 0.30, 0.95)
	var surface_inner: Color = Color(0.20, 0.70, 0.15, 0.95)
	var surface_marker_side: float = 8.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(_delta: float) -> void:
		queue_redraw()

	func _draw() -> void:
		_draw_grid()
		_draw_surface_units()
		if tracker == null:
			return
		for entry in tracker.impacts:
			var lat: float = entry["lat"]
			var lon: float = entry["lon"]
			var hp: float = float(entry.get("hp", 0.0))
			var p := _latlon_to_local(lat, lon)
			var r := marker_radius * _hp_marker_scale(hp)
			draw_circle(p, r + 1.5, marker_outer)
			draw_circle(p, maxf(r - 1.0, 0.5), marker_inner)

	func _hp_marker_scale(hp: float) -> float:
		var ratio := maxf(hp, marker_hp_ref_min) / marker_hp_ref_min
		var hp_norm := clampf(
			log(ratio) / log(pow(10.0, marker_hp_log_decades)), 0.0, 1.0
		)
		return lerpf(marker_min_scale, marker_max_scale, hp_norm)

	# Surface-unit markers are drawn UNDER the impact dots so a
	# meteorite that lands on top of an emplacement still shows the
	# impact splash on top — easier to read as "this position was hit"
	# than the inverse layering would be.
	func _draw_surface_units() -> void:
		var side := surface_marker_side
		var half := side * 0.5
		for sat in satellites:
			if sat == null or not sat.is_surface:
				continue
			if not sat.alive:
				continue
			var p := _latlon_to_local(sat.surface_lat_deg, sat.surface_lon_deg)
			# Outer rect (slightly larger) drawn first as a halo, inner
			# fill on top — same two-tone idiom as the impact circles.
			draw_rect(
				Rect2(p.x - half - 1.0, p.y - half - 1.0, side + 2.0, side + 2.0),
				surface_outer, true,
			)
			draw_rect(
				Rect2(p.x - half + 1.0, p.y - half + 1.0, side - 2.0, side - 2.0),
				surface_inner, true,
			)

	func _draw_grid() -> void:
		var mid_x := origin.x + map_size.x * 0.5
		draw_line(
			Vector2(mid_x, origin.y),
			Vector2(mid_x, origin.y + map_size.y),
			grid_color, 1.0
		)
		var lat_lines: Array[float] = [60.0, 30.0, 0.0, -30.0, -60.0]
		for lat in lat_lines:
			var y := _lat_to_local_y(lat)
			draw_line(
				Vector2(origin.x, y),
				Vector2(origin.x + map_size.x, y),
				grid_color, 1.0
			)

	func _latlon_to_local(lat: float, lon: float) -> Vector2:
		var x := origin.x + ((lon + 180.0) / 360.0) * map_size.x
		return Vector2(x, _lat_to_local_y(lat))

	func _lat_to_local_y(lat: float) -> float:
		var clamped := clampf(lat, -lat_clamp_deg, lat_clamp_deg)
		var lat_rad := deg_to_rad(clamped)
		var clamp_rad := deg_to_rad(lat_clamp_deg)
		var max_y := log(tan(PI * 0.25 + clamp_rad * 0.5))
		var merc_y := log(tan(PI * 0.25 + lat_rad * 0.5))
		var y_norm := 0.5 - 0.5 * (merc_y / max_y)
		return origin.y + y_norm * map_size.y


const MAP_SIZE := Vector2(420.0, 320.0)
const PANEL_BG := Color(0.04, 0.04, 0.08, 0.85)
const TITLE_COLOR := Color(0.85, 0.92, 1.0)
const GRID_COLOR := Color(0.6, 0.7, 0.85, 0.18)
const MARKER_OUTER := Color(1.0, 0.25, 0.05, 0.95)
const MARKER_INNER := Color(1.0, 0.85, 0.4, 0.95)
const MARKER_RADIUS: float = 4.0
const LAT_CLAMP_DEG: float = 85.0

# Padding around the map texture inside the panel. Top reserves space
# for the title strip; bottom reserves space for the latest-impact
# readout. Left/right are equal so the map sits centered horizontally.
const PAD_LEFT: float = 8.0
const PAD_RIGHT: float = 8.0
const PAD_TOP: float = 22.0
const PAD_BOTTOM: float = 36.0

var tracker: ImpactTracker:
	set(value):
		tracker = value
		if _marker_layer != null:
			_marker_layer.tracker = value
# Reference to the live game's satellite list. Bound from EarthSystem
# at _ready; the marker layer filters for is_surface each draw call.
var satellites: Array[Satellite] = []:
	set(value):
		satellites = value
		if _marker_layer != null:
			_marker_layer.satellites = value
var _panel: Panel
var _map_rect: TextureRect
var _title: Label
var _readout: RichTextLabel
var _marker_layer: _MarkerLayer


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(
		MAP_SIZE.x + PAD_LEFT + PAD_RIGHT,
		MAP_SIZE.y + PAD_TOP + PAD_BOTTOM,
	)
	size = custom_minimum_size

	_panel = Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL_BG
	sb.set_corner_radius_all(6)
	_panel.add_theme_stylebox_override("panel", sb)
	_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_panel)

	_title = Label.new()
	_title.text = "Meteorite impacts"
	_title.add_theme_font_size_override("font_size", 12)
	_title.add_theme_color_override("font_color", TITLE_COLOR)
	_title.position = Vector2(PAD_LEFT, 4.0)
	_title.size = Vector2(MAP_SIZE.x, 16.0)
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_title)

	_map_rect = TextureRect.new()
	_map_rect.position = Vector2(PAD_LEFT, PAD_TOP)
	_map_rect.size = MAP_SIZE
	_map_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_map_rect.stretch_mode = TextureRect.STRETCH_SCALE
	_map_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_install_map_material(_map_rect)
	add_child(_map_rect)

	_readout = RichTextLabel.new()
	_readout.bbcode_enabled = true
	_readout.scroll_active = false
	_readout.fit_content = true
	_readout.position = Vector2(PAD_LEFT, PAD_TOP + MAP_SIZE.y + 2.0)
	_readout.size = Vector2(MAP_SIZE.x, PAD_BOTTOM - 4.0)
	_readout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_readout)

	# Marker layer added LAST so children draw on top of the map.
	_marker_layer = _MarkerLayer.new()
	_marker_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_marker_layer.origin = Vector2(PAD_LEFT, PAD_TOP)
	_marker_layer.map_size = MAP_SIZE
	_marker_layer.lat_clamp_deg = LAT_CLAMP_DEG
	_marker_layer.grid_color = GRID_COLOR
	_marker_layer.marker_outer = MARKER_OUTER
	_marker_layer.marker_inner = MARKER_INNER
	_marker_layer.marker_radius = MARKER_RADIUS
	_marker_layer.tracker = tracker
	_marker_layer.satellites = satellites
	add_child(_marker_layer)


# Wire the Mercator reprojection shader onto the map rect, with the
# equirectangular Earth texture as input. Falls back to a plain
# TextureRect (still equirectangular) if either resource is missing
# — the markers remain meaningful because their position math is
# driven by lat/lon, which we re-project below.
func _install_map_material(rect: TextureRect) -> void:
	var tex: Texture2D = null
	if ResourceLoader.exists("res://resources/3D/earth/4096_earth.jpg"):
		tex = load("res://resources/3D/earth/4096_earth.jpg") as Texture2D
	if tex != null:
		rect.texture = tex
	else:
		# Render-time fallback so the panel still has a backdrop. Plain
		# blue-gray placeholder; markers still draw correctly on top.
		var img := Image.create(2, 1, false, Image.FORMAT_RGB8)
		img.set_pixel(0, 0, Color(0.10, 0.18, 0.30))
		img.set_pixel(1, 0, Color(0.10, 0.18, 0.30))
		rect.texture = ImageTexture.create_from_image(img)
		return

	var shader: Shader = load("res://shaders/mercator_map.gdshader") as Shader
	if shader == null:
		return
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("source", tex)
	mat.set_shader_parameter("lat_clamp_deg", LAT_CLAMP_DEG)
	rect.material = mat


func _process(_delta: float) -> void:
	if not visible:
		return
	_update_readout()


func _update_readout() -> void:
	if _readout == null or tracker == null:
		return
	if tracker.impacts.is_empty():
		_readout.text = (
			"[font_size=11][color=#9aa9b8]"
			+ "No impacts recorded yet.[/color][/font_size]"
		)
		return
	var latest: Dictionary = tracker.impacts[tracker.impacts.size() - 1]
	var lat: float = latest["lat"]
	var lon: float = latest["lon"]
	var region: String = latest["region"]
	_readout.text = (
		"[font_size=11][color=#9aa9b8]Latest: [color=#ffd27a]"
		+ region
		+ "[/color]\n"
		+ "%s  %s  ([color=#7fcf7f]%d[/color] total)[/color][/font_size]"
	) % [_format_lat(lat), _format_lon(lon), tracker.impacts.size()]


static func _format_lat(lat: float) -> String:
	var hemi := "N" if lat >= 0.0 else "S"
	return "%.2f° %s" % [absf(lat), hemi]


static func _format_lon(lon: float) -> String:
	var hemi := "E" if lon >= 0.0 else "W"
	return "%.2f° %s" % [absf(lon), hemi]


