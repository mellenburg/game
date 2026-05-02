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
const UIStyle = preload("res://scripts/ui/ui_style.gd")


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
	var blip_radius: float = 3.0

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
		# Guard against a wave that hasn't been populated (zero-duration
		# divisions) — the empty grid is the right visual.
		var duration: float = wave.duration_sec
		var spread: float = wave.lateral_spread_km
		if duration <= 0.0 or spread <= 0.0:
			return
		var pending: Array = wave.pending
		for entry: Dictionary in pending:
			var lat: Vector2 = entry["lateral"]
			var t: float = entry["t"]
			# Bodies still in the preroll window (t > duration) are above
			# the radar — skip until they scroll into view from the top.
			if t > duration:
				continue
			# X projection: tangent-axis component of the in-plane offset,
			# normalised to [-1, 1] of the wave's lateral spread. A wave
			# uniformly distributed on the entry disc collapses to the
			# semicircle-density bell shape on this axis, matching the
			# operator's mental model for "incoming spread".
			var x_norm := clampf(lat.x / spread, -1.0, 1.0)
			# Y projection: t = duration → top (just queued, far away);
			# t = 0 → bottom (about to spawn). Godot's local Y grows
			# downward, so larger t maps to smaller pixel_y.
			var y_norm := clampf(1.0 - t / duration, 0.0, 1.0)
			var p := Vector2(
				origin.x + (x_norm * 0.5 + 0.5) * view_size.x,
				origin.y + y_norm * view_size.y,
			)
			draw_circle(p, blip_radius + 1.5, blip_outer)
			draw_circle(p, blip_radius - 1.0, blip_inner)


const RADAR_SIZE := Vector2(420.0, 320.0)
const VIEW_BG := UIStyle.BG_0
const TITLE_COLOR := UIStyle.FG_2
# Same hue as UIStyle.ACCENT (#ffb454), inlined as literal Color values
# at the alphas used here. See impact_map.gd for the rationale.
const GRID_COLOR := Color(1.0, 0.706, 0.329, 0.18)
const AXIS_COLOR := Color(1.0, 0.706, 0.329, 0.45)
const BLIP_OUTER := UIStyle.BAD
const BLIP_INNER := UIStyle.WARN
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
	var sb := UIStyle.make_panel_stylebox(false)
	sb.content_margin_left = 0
	sb.content_margin_right = 0
	sb.content_margin_top = 0
	sb.content_margin_bottom = 0
	_panel.add_theme_stylebox_override("panel", sb)
	_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_panel)

	_title = Label.new()
	_title.text = "WAVE RADAR"
	_title.add_theme_font_size_override("font_size", UIStyle.FONT_LABEL_XS)
	_title.add_theme_color_override("font_color", TITLE_COLOR)
	_title.position = Vector2(PAD_LEFT, 6.0)
	_title.size = Vector2(RADAR_SIZE.x, 14.0)
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
	var max_duration := 0.0
	for w: MeteoriteWave in waves:
		if w == null:
			continue
		pending_total += w.pending.size()
		if w.duration_sec > max_duration:
			max_duration = w.duration_sec
	var fg2 := UIStyle.FG_2.to_html(false)
	var accent := UIStyle.ACCENT.to_html(false)
	var good := UIStyle.GOOD.to_html(false)
	if pending_total == 0:
		_readout.text = (
			"[font_size=%d][color=#%s]NO ACTIVE WAVE  ·  PRESS I[/color][/font_size]"
		) % [UIStyle.FONT_LABEL_XS, fg2]
		return
	_readout.text = (
		"[font_size=%d][color=#%s]PENDING[/color]  [color=#%s]%d[/color]"
		+ "    [color=#%s]WINDOW[/color]  [color=#%s]%.1fs[/color][/font_size]"
	) % [UIStyle.FONT_BODY_SM, fg2, accent, pending_total, fg2, good, max_duration]
