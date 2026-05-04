class_name RadarMap
extends Control
## 2-D radar overlay of the meteorite wave currently spawning. The X axis
## is a 1-D projection of each pending body's lateral offset (along the
## entry-frame tangent), normalised to [-1, 1] of the wave's lateral
## spread. The Y axis is the time remaining until that body enters play,
## with Y=Max at the top (= the configured wave duration, "10 seconds
## away") and Y=0 at the bottom (= about to spawn). Blips visually scroll
## downward as their countdown elapses; reaching Y=0 means the body just
## spawned in the game area and the wave dropped it from its queue.
##
## The overlay reads pending specs straight off the EarthSystem's active
## wave list — no signal plumbing — and queues a redraw each frame.
## Multiple concurrent waves overlay their blips on the same axes.
##
## The map node is a Panel + title + inner _BlipLayer Control sized at
## RADAR_SIZE; the blip layer is added LAST so it draws on top of the
## panel background, mirroring the back-to-front layering ImpactMap uses
## for its impact markers.

const MeteoriteWave = preload("res://scripts/meteorite_wave.gd")


# Inner Control that paints the grid + blips. Reads `waves` straight off
# its parent each frame; lives as a child added AFTER the panel so the
# blips draw on top of the background fill.
class _BlipLayer extends Control:
	# Plain Array (not Array[MeteoriteWave]) because the inner class can't
	# import the outer file's typed-array element binding cleanly; we
	# treat each entry as a duck-typed wave and reach into its fields.
	var waves: Array = []
	var origin: Vector2 = Vector2.ZERO
	var view_size: Vector2 = Vector2.ZERO
	var grid_color: Color = Color(0.6, 0.7, 0.85, 0.18)
	var axis_color: Color = Color(0.85, 0.92, 1.0, 0.35)
	var blip_outer: Color = Color(1.0, 0.35, 0.35, 0.95)
	var blip_inner: Color = Color(1.0, 0.85, 0.4, 0.95)
	# Decaying-orbit threats get a magenta tint so the operator can
	# distinguish them at a glance from sub-orbital meteorites — they
	# behave very differently (long spiral-in vs straight ground impact)
	# and mixing the two color codes them on the wave radar.
	var blip_decaying_outer: Color = Color(0.95, 0.45, 0.95, 0.95)
	var blip_decaying_inner: Color = Color(1.0, 0.85, 0.4, 0.95)
	var blip_radius: float = 3.0
	# Mass^(2/3) scaling of the blip radius: a body whose mass equals
	# this reference renders at the unscaled blip_radius. Heavier bodies
	# scale up at the 2/3 power (proportional to a sphere's projected
	# cross-section under linear-radius scaling), lighter shrink. 1000 kg
	# matches Satellite.DEFAULT_MASS_KG so the legacy fixed-radius look
	# falls out for default bodies.
	var blip_reference_mass_kg: float = 1000.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(_delta: float) -> void:
		queue_redraw()

	func _draw() -> void:
		_draw_grid()
		for wave: Object in waves:
			if wave == null:
				continue
			_draw_wave(wave)

	func _draw_grid() -> void:
		# Center vertical axis (X = 0) and three evenly-spaced horizontals
		# at Y/Max = 0.25, 0.50, 0.75. The top + bottom edges are already
		# drawn by the panel border, so don't duplicate them.
		var center_x := origin.x + view_size.x * 0.5
		draw_line(
			Vector2(center_x, origin.y),
			Vector2(center_x, origin.y + view_size.y),
			axis_color, 1.0,
		)
		var rows: Array[float] = [0.25, 0.50, 0.75]
		for f in rows:
			var y := origin.y + view_size.y * f
			draw_line(
				Vector2(origin.x, y),
				Vector2(origin.x + view_size.x, y),
				grid_color, 1.0,
			)

	func _draw_wave(wave: Object) -> void:
		# Guard against a wave that hasn't been populated (zero-spread /
		# zero-window divisions) — the empty grid is the right visual.
		var window: float = wave.warning_window_sec
		var spread: float = wave.lateral_spread_km
		if window <= 0.0 or spread <= 0.0:
			return
		var pending: Array = wave.pending
		for entry: Dictionary in pending:
			var lat: Vector2 = entry["lateral"]
			var t: float = entry["t"]
			# Bodies whose t exceeds the warning window are still queued
			# beyond the radar's lead-time horizon — skip until they
			# scroll into view from the top.
			if t > window:
				continue
			# X projection: tangent-axis component of the in-plane offset,
			# normalised to [-1, 1] of the wave's lateral spread. A wave
			# uniformly distributed on the entry disc collapses to the
			# semicircle-density bell shape on this axis, matching the
			# operator's mental model for "incoming spread".
			var x_norm := clampf(lat.x / spread, -1.0, 1.0)
			# Y projection: t = window → top (just appeared on the radar);
			# t = 0 → bottom (about to spawn). Godot's local Y grows
			# downward, so larger t maps to smaller pixel_y. The window's
			# sim-seconds scale with time_factor, so a higher Research
			# tier (longer warning) naturally extends the visible lead.
			var y_norm := clampf(1.0 - t / window, 0.0, 1.0)
			var p := Vector2(
				origin.x + (x_norm * 0.5 + 0.5) * view_size.x,
				origin.y + y_norm * view_size.y,
			)
			# Mass^(2/3) gives the radar blip a "size on screen"
			# proportional to a body's cross-section (radius ∝ mass^(1/3),
			# projected area ∝ mass^(2/3)) — matches the player's mental
			# model that a heavier rock should look bigger. Specs without
			# a mass key (legacy storms) fall back to the reference mass.
			var mass: float = entry.get("mass", blip_reference_mass_kg)
			var r := blip_radius * pow(
				maxf(mass, 1.0) / blip_reference_mass_kg, 2.0 / 3.0
			)
			var is_decaying: bool = entry.get("is_decaying", false)
			var outer := blip_decaying_outer if is_decaying else blip_outer
			var inner := blip_decaying_inner if is_decaying else blip_inner
			draw_circle(p, r + 1.5, outer)
			draw_circle(p, maxf(r - 1.0, 0.5), inner)


const RADAR_SIZE := Vector2(420.0, 320.0)
const PANEL_BG := Color(0.04, 0.04, 0.08, 0.85)
const VIEW_BG := Color(0.02, 0.06, 0.04, 0.95)
const TITLE_COLOR := Color(0.85, 0.92, 1.0)
const GRID_COLOR := Color(0.6, 0.7, 0.85, 0.18)
const AXIS_COLOR := Color(0.85, 0.92, 1.0, 0.35)
const BLIP_OUTER := Color(1.0, 0.35, 0.35, 0.95)
const BLIP_INNER := Color(1.0, 0.85, 0.4, 0.95)
const BLIP_RADIUS: float = 3.0

const PAD_LEFT: float = 8.0
const PAD_RIGHT: float = 8.0
const PAD_TOP: float = 22.0
const PAD_BOTTOM: float = 36.0


# Bound to the EarthSystem's active wave list at _ready. Read-only from
# the radar's perspective; the system owns add/remove of waves, the
# radar just reflects whatever's pending.
var waves: Array[MeteoriteWave] = []:
	set(value):
		waves = value
		if _blip_layer != null:
			_blip_layer.waves = value
var _panel: Panel
var _view_bg: ColorRect
var _title: Label
var _readout: RichTextLabel
var _blip_layer: _BlipLayer


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(
		RADAR_SIZE.x + PAD_LEFT + PAD_RIGHT,
		RADAR_SIZE.y + PAD_TOP + PAD_BOTTOM,
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
	_title.text = "Wave radar"
	_title.add_theme_font_size_override("font_size", 12)
	_title.add_theme_color_override("font_color", TITLE_COLOR)
	_title.position = Vector2(PAD_LEFT, 4.0)
	_title.size = Vector2(RADAR_SIZE.x, 16.0)
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_title)

	_view_bg = ColorRect.new()
	_view_bg.position = Vector2(PAD_LEFT, PAD_TOP)
	_view_bg.size = RADAR_SIZE
	_view_bg.color = VIEW_BG
	_view_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_view_bg)

	_readout = RichTextLabel.new()
	_readout.bbcode_enabled = true
	_readout.scroll_active = false
	_readout.fit_content = true
	_readout.position = Vector2(PAD_LEFT, PAD_TOP + RADAR_SIZE.y + 2.0)
	_readout.size = Vector2(RADAR_SIZE.x, PAD_BOTTOM - 4.0)
	_readout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_readout)

	# Blip layer added LAST so children draw on top of the view bg.
	_blip_layer = _BlipLayer.new()
	_blip_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_blip_layer.origin = Vector2(PAD_LEFT, PAD_TOP)
	_blip_layer.view_size = RADAR_SIZE
	_blip_layer.grid_color = GRID_COLOR
	_blip_layer.axis_color = AXIS_COLOR
	_blip_layer.blip_outer = BLIP_OUTER
	_blip_layer.blip_inner = BLIP_INNER
	_blip_layer.blip_radius = BLIP_RADIUS
	_blip_layer.waves = waves
	add_child(_blip_layer)


func _process(_delta: float) -> void:
	if not visible:
		return
	_update_readout()


func _update_readout() -> void:
	if _readout == null:
		return
	var pending_total := 0
	var max_window := 0.0
	for w: MeteoriteWave in waves:
		if w == null:
			continue
		pending_total += w.pending.size()
		if w.warning_window_sec > max_window:
			max_window = w.warning_window_sec
	if pending_total == 0:
		_readout.text = (
			"[font_size=11][color=#9aa9b8]"
			+ "No active wave. Press I to summon one."
			+ "[/color][/font_size]"
		)
		return
	# Window readout in game-time hours — the radar lead is upgradable
	# via Research and lives on the same hour-scale clock as the wave
	# delays in the Recon editor.
	_readout.text = (
		"[font_size=11][color=#9aa9b8]Pending: [color=#ffd27a]%d[/color]"
		+ "  Warning: [color=#7fcf7f]%.1f h[/color][/color][/font_size]"
	) % [pending_total, max_window / 3600.0]
