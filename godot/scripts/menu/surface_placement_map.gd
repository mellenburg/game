extends Control
## Equirectangular world map widget for the menu's Surface Ops tab.
## Shows the same basemap the in-game ImpactMap uses for the active
## body (Earth's day-side JPEG on Earth missions, the NASA PIA02066
## cylindrical mosaic on Mars), and emits `placed(lat_deg, lon_deg)`
## whenever the operator clicks anywhere inside the map area. Existing
## surface installations from PlayerLoadout are drawn as green markers
## on top of the map.
##
## Equirectangular (rather than the in-game ImpactMap's Mercator) so
## clicking near the poles still resolves to a sensible lat/lon — the
## Mercator projection compresses placement resolution near 0° lat and
## blows up near the poles, which would feel wrong on a click target.

const PlayerLoadoutType = preload("res://scripts/player_loadout.gd")
const CelestialBody = preload("res://scripts/celestial_body.gd")

signal placed(lat_deg: float, lon_deg: float)


# Inner Control that draws the existing-unit markers on top of the
# basemap. Same back-to-front idiom as ImpactMap's _MarkerLayer — the
# basemap TextureRect is added first, the marker layer last.
class _MarkerLayer extends Control:
	var unit_color_outer: Color = Color(0.85, 1.0, 0.30, 0.95)
	var unit_color_inner: Color = Color(0.20, 0.70, 0.15, 0.95)
	var marker_side: float = 10.0
	var origin: Vector2 = Vector2.ZERO
	var map_size: Vector2 = Vector2.ZERO
	var label_color: Color = Color(0.95, 0.97, 1.0, 0.95)
	# Plain Array (not typed Array[SurfaceUnitConfig]) because the inner
	# class can't reach the outer file's preload binding cleanly — we
	# duck-type the entries on lat_deg / lon_deg / name.
	var configs: Array = []

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(_delta: float) -> void:
		queue_redraw()

	func _draw() -> void:
		# Latitude grid lines (every 30°) and the prime meridian, so
		# the map reads as a globe rather than an arbitrary photo.
		var grid := Color(1.0, 1.0, 1.0, 0.18)
		var mid_x := origin.x + map_size.x * 0.5
		draw_line(
			Vector2(mid_x, origin.y),
			Vector2(mid_x, origin.y + map_size.y),
			grid, 1.0,
		)
		var lat_lines: Array[float] = [60.0, 30.0, 0.0, -30.0, -60.0]
		for lat in lat_lines:
			var y: float = origin.y + (1.0 - (lat + 90.0) / 180.0) * map_size.y
			draw_line(
				Vector2(origin.x, y),
				Vector2(origin.x + map_size.x, y),
				grid, 1.0,
			)

		var half := marker_side * 0.5
		for cfg in configs:
			if cfg == null:
				continue
			var p := _latlon_to_local(cfg.lat_deg, cfg.lon_deg)
			draw_rect(
				Rect2(p.x - half - 1.0, p.y - half - 1.0, marker_side + 2.0, marker_side + 2.0),
				unit_color_outer, true,
			)
			draw_rect(
				Rect2(p.x - half + 1.0, p.y - half + 1.0, marker_side - 2.0, marker_side - 2.0),
				unit_color_inner, true,
			)

	func _latlon_to_local(lat_deg: float, lon_deg: float) -> Vector2:
		var x := origin.x + ((lon_deg + 180.0) / 360.0) * map_size.x
		var y := origin.y + (1.0 - (lat_deg + 90.0) / 180.0) * map_size.y
		return Vector2(x, y)


const PAD_LEFT: float = 6.0
const PAD_RIGHT: float = 6.0
const PAD_TOP: float = 6.0
const PAD_BOTTOM: float = 6.0

const PANEL_BG := Color(0.04, 0.04, 0.08, 1.0)

var _panel: Panel
var _map_rect: TextureRect
var _marker_layer: _MarkerLayer
# Stage id whose basemap is currently bound. refresh() compares this
# against the live PlayerLoadout selection and reloads the texture
# when they diverge — that's the seam the menu uses to swap Earth →
# Mars after the operator picks a different mission.
var _bound_stage_id: String = ""


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP

	_panel = Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL_BG
	sb.set_corner_radius_all(4)
	_panel.add_theme_stylebox_override("panel", sb)
	_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_panel)

	_map_rect = TextureRect.new()
	_map_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_map_rect.offset_left = PAD_LEFT
	_map_rect.offset_top = PAD_TOP
	_map_rect.offset_right = -PAD_RIGHT
	_map_rect.offset_bottom = -PAD_BOTTOM
	_map_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_map_rect.stretch_mode = TextureRect.STRETCH_SCALE
	_map_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_map_rect)
	_apply_basemap_for_selected_stage()

	_marker_layer = _MarkerLayer.new()
	_marker_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_marker_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_marker_layer)

	resized.connect(_update_marker_extents)
	_update_marker_extents()
	refresh()


func refresh() -> void:
	if _marker_layer == null:
		return
	# Stage id may have changed since the last refresh (operator picked
	# a different mission on the Campaign tab). Reload the basemap so
	# the click target matches the body the placements will deploy to.
	_apply_basemap_for_selected_stage()
	_marker_layer.configs = PlayerLoadout.surface_units
	_marker_layer.queue_redraw()


# Look up the active body off PlayerLoadout's selected stage and bind
# the matching cylindrical map to the rect. Skips the texture load when
# the stage hasn't changed since the last bind so flipping back to a
# tab the operator already configured doesn't churn texture memory.
func _apply_basemap_for_selected_stage() -> void:
	if _map_rect == null:
		return
	var stage_id := String(PlayerLoadout.selected_stage_id)
	if stage_id == _bound_stage_id and _map_rect.texture != null:
		return
	_bound_stage_id = stage_id
	_map_rect.texture = _load_basemap_for_stage(stage_id)


# Forward the basemap rect's pixel extents into the marker layer so the
# (lat, lon) → pixel projection lines up with the visible map area.
# Resized signal drives this on layout changes.
func _update_marker_extents() -> void:
	if _marker_layer == null:
		return
	_marker_layer.origin = Vector2(PAD_LEFT, PAD_TOP)
	_marker_layer.map_size = Vector2(
		maxf(size.x - PAD_LEFT - PAD_RIGHT, 1.0),
		maxf(size.y - PAD_TOP - PAD_BOTTOM, 1.0),
	)


func _load_basemap_for_stage(stage_id: String) -> Texture2D:
	var body := CelestialBody.for_stage(stage_id)
	var tex := body.load_albedo_texture()
	if tex != null:
		return tex
	# Fallback so the click target still has a backdrop in headless /
	# asset-stripped runs. Tint pulled from the body record so the panel
	# still reads as the right planet's colour even with no texture.
	var img := Image.create(4, 4, false, Image.FORMAT_RGB8)
	img.fill(body.fallback_color)
	return ImageTexture.create_from_image(img)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
			return
		var local := mb.position
		var w := maxf(size.x - PAD_LEFT - PAD_RIGHT, 1.0)
		var h := maxf(size.y - PAD_TOP - PAD_BOTTOM, 1.0)
		var u: float = clampf((local.x - PAD_LEFT) / w, 0.0, 1.0)
		var v: float = clampf((local.y - PAD_TOP) / h, 0.0, 1.0)
		var lon := (u - 0.5) * 360.0
		var lat := 90.0 - v * 180.0
		placed.emit(lat, lon)
