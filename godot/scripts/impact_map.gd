class_name ImpactMap
extends Control
## Mercator-projected world map overlay with markers at every recorded
## meteorite impact. The map background is the same equirectangular
## texture the globe uses, reprojected to Web Mercator on the GPU by
## a small canvas-item shader; that avoids a CPU resample on startup
## and keeps the rendering side compatible with the project's GL
## Compatibility constraint.
##
## The active body's texture is picked off CelestialBody at _ready —
## Earth missions get the day-side JPEG, Mars missions get the NASA
## PIA02066 cylindrical mosaic. The Mercator reprojection is
## body-agnostic; only the source texture and the panel title differ.
##
## The map node is a TextureRect child sized at MAP_SIZE. Markers are
## drawn by an inner _MarkerLayer Control added AFTER the map, so
## Godot's back-to-front child draw order paints them on top of the
## basemap rather than under it.

const ImpactTracker = preload("res://scripts/impact_tracker.gd")
const Satellite = preload("res://scripts/satellite.gd")
const CelestialBody = preload("res://scripts/celestial_body.gd")
const MeteorPhysics = preload("res://scripts/meteor_physics.gd")

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
	const _Physics = preload("res://scripts/meteor_physics.gd")
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
	# Three-tier damage palette. Each impact paints up to three
	# concentric circles whose radii come from MeteorPhysics:
	#   * yellow (light)    — overpressure, broken windows
	#   * orange (moderate) — severe blast / structural collapse
	#   * red    (heavy)    — near-instant lethality
	# Just-above-threshold impacts draw only the yellow ring at the
	# `min_visible_px` floor (a tiny dot); larger impacts paint
	# successive rings as the cube-root-of-mass radius grows past
	# each band's visibility threshold. Filled discs (with alpha)
	# rather than rings so they stack as nested colour fields.
	var damage_color_light: Color = Color(1.0, 0.85, 0.20, 0.32)
	var damage_color_moderate: Color = Color(1.0, 0.55, 0.10, 0.45)
	var damage_color_heavy: Color = Color(1.0, 0.20, 0.10, 0.65)
	# Pixels-per-km on the Mercator overlay. Geometric scale at the
	# equator is ~0.011 px/km — too small for a Tunguska-class blast
	# to register as anything but a sub-pixel speck — so we apply a
	# uniform 5x amplification. The user-visible result is that
	# damage circles read at "regional" magnitude rather than true-
	# scale invisibility, while preserving the cube-root-of-mass
	# proportionality between impacts.
	var damage_px_per_km: float = 0.05
	# Floor radius for the outermost (yellow) circle so any recorded
	# impact paints at least a visible speck. Inner rings have no
	# floor — they only appear when the impact's natural radius
	# pushes them past the `min_*_visible_px` thresholds, so a
	# threshold-sized impactor reads as a single yellow dot and
	# heavier ones progressively reveal the orange + red rings.
	var min_light_px: float = 2.0
	var min_moderate_visible_px: float = 1.5
	var min_heavy_visible_px: float = 1.0
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
			_draw_impact(entry)

	# Paint up to three concentric damage circles for one impact entry.
	# Older entries stored mass as 0 (legacy "dot" format); we fall
	# back to deriving a notional mass from `hp` so they still draw.
	# Heavy → moderate → light order so larger rings fall behind the
	# smaller, more saturated ones.
	func _draw_impact(entry: Dictionary) -> void:
		var lat: float = entry["lat"]
		var lon: float = entry["lon"]
		var mass: float = float(entry.get("mass_kg", 0.0))
		if mass <= 0.0:
			# Legacy entries without mass: estimate from HP using the
			# stony-density default so the marker has *some* size.
			var hp: float = float(entry.get("hp", 0.0))
			if hp > 0.0:
				mass = hp / (_Physics.HP_PER_KG_PER_DENSITY * 3.4)
		if _Physics.is_burn_up(mass):
			return
		var radii: Dictionary = _Physics.damage_radii_km(mass)
		var p := _latlon_to_local(lat, lon)
		var r_light_px: float = maxf(
			float(radii["light"]) * damage_px_per_km, min_light_px
		)
		var r_moderate_px: float = float(radii["moderate"]) * damage_px_per_km
		var r_heavy_px: float = float(radii["heavy"]) * damage_px_per_km
		draw_circle(p, r_light_px, damage_color_light)
		if r_moderate_px >= min_moderate_visible_px:
			draw_circle(p, r_moderate_px, damage_color_moderate)
		if r_heavy_px >= min_heavy_visible_px:
			draw_circle(p, r_heavy_px, damage_color_heavy)

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
var _body: CelestialBody


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

	_body = _resolve_body()
	_title = Label.new()
	_title.text = "%s surface impacts" % _body.display_name
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
	_install_map_material(_map_rect, _body)
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
	_marker_layer.tracker = tracker
	_marker_layer.satellites = satellites
	add_child(_marker_layer)


# Wire the Mercator reprojection shader onto the map rect, with the
# active body's equirectangular albedo as input. Falls back to a solid-
# colour TextureRect tinted by `body.fallback_color` if the asset is
# missing — the markers remain meaningful because their position math
# is driven by lat/lon, which we re-project below.
func _install_map_material(rect: TextureRect, body: CelestialBody) -> void:
	var tex := body.load_albedo_texture()
	if tex != null:
		rect.texture = tex
	else:
		var img := Image.create(2, 1, false, Image.FORMAT_RGB8)
		img.set_pixel(0, 0, body.fallback_color)
		img.set_pixel(1, 0, body.fallback_color)
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


func _resolve_body() -> CelestialBody:
	return CelestialBody.active(get_tree())


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
	# ImpactTracker.classify_region keys off Earth's bounding-box table,
	# so Mars impacts come back tagged with Earth region names. Skip
	# the region row on non-Earth bodies and use the body's own name as
	# a generic location label rather than mislead the operator.
	var region: String = (
		String(latest["region"]) if _body.id == CelestialBody.ID_EARTH
		else "%s surface" % _body.display_name
	)
	var mass: float = float(latest.get("mass_kg", 0.0))
	var comp: int = int(latest.get("composition", -1))
	var density: float = float(latest.get("density_g_cm3", 0.0))
	var detail := _format_impact_detail(mass, comp, density)
	_readout.text = (
		"[font_size=11][color=#9aa9b8]Latest: [color=#ffd27a]"
		+ region
		+ "[/color]\n"
		+ "%s  %s%s  ([color=#7fcf7f]%d[/color] total)[/color][/font_size]"
	) % [_format_lat(lat), _format_lon(lon), detail, tracker.impacts.size()]


# Build the "  ·  S-type, 1.20 Tg, 3.4 g/cm³" suffix for the latest-
# impact readout. Falls back to an empty string for legacy entries
# without mass/composition so older saves don't render "N/A" noise.
static func _format_impact_detail(
	mass_kg: float, composition: int, density_g_cm3: float
) -> String:
	if mass_kg <= 0.0:
		return ""
	var parts: Array[String] = []
	if composition >= 0:
		parts.append(MeteorPhysics.composition_name(composition))
	parts.append(_format_mass(mass_kg))
	if density_g_cm3 > 0.0:
		parts.append("%.1f g/cm³" % density_g_cm3)
	return "  ·  " + ", ".join(parts)


# SI-prefix mass formatter: tons (Mg) for small impacts, escalating
# through Gg / Tg / Pg / Eg as orders of magnitude rise. Two
# significant figures so a 12 000 kg impactor reads "12 Mg" rather
# than "12000 kg".
static func _format_mass(mass_kg: float) -> String:
	if mass_kg < 1.0e6:
		return "%.0f Mg" % (mass_kg / 1.0e3)
	if mass_kg < 1.0e9:
		return "%.1f Gg" % (mass_kg / 1.0e6)
	if mass_kg < 1.0e12:
		return "%.1f Tg" % (mass_kg / 1.0e9)
	if mass_kg < 1.0e15:
		return "%.1f Pg" % (mass_kg / 1.0e12)
	return "%.1f Eg" % (mass_kg / 1.0e15)


static func _format_lat(lat: float) -> String:
	var hemi := "N" if lat >= 0.0 else "S"
	return "%.2f° %s" % [absf(lat), hemi]


static func _format_lon(lon: float) -> String:
	var hemi := "E" if lon >= 0.0 else "W"
	return "%.2f° %s" % [absf(lon), hemi]


