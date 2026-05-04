extends Control
## Stylized (not-to-scale) solar-system map for the Campaign tab.
##
## Draws the Sun in the centre, a faint orbital ring per stage, and a
## clickable disc for each body at its (orbit_radius, angle_deg) layout
## offset. Locked stages render dimmer and don't accept clicks. Ceres
## sits visually inside a faded asteroid-belt band between Mars and
## Jupiter; the band is a pure decoration with no per-body data.
##
## Selection state lives on PlayerLoadout (single source of truth across
## the Mission Select list and this map). Clicks emit `body_selected`
## with the stage id so the menu can refresh the brief without this
## widget reaching back into PlayerLoadout itself.

signal body_selected(stage_id: String)

const COLOR_BG := Color(0.024, 0.031, 0.043)
const COLOR_ORBIT := Color(0.22, 0.26, 0.32)
const COLOR_ORBIT_LOCKED := Color(0.14, 0.16, 0.20)
const COLOR_BELT := Color(0.30, 0.28, 0.24, 0.35)
const COLOR_SUN_CORE := Color(1.0, 0.85, 0.40)
const COLOR_SUN_GLOW := Color(1.0, 0.65, 0.20, 0.25)
const COLOR_LABEL := Color(0.86, 0.88, 0.92)
const COLOR_LABEL_LOCKED := Color(0.50, 0.52, 0.58)
const COLOR_SELECT_RING := Color(1.0, 0.706, 0.329)
const COLOR_HOVER_RING := Color(1.0, 0.706, 0.329, 0.55)

const SUN_CORE_RADIUS: float = 14.0
const SUN_GLOW_RADIUS: float = 26.0
# Asteroid belt extents in the same normalised radius units as
# `orbit_radius` on each stage record. Ceres sits inside this band by
# design — bumping these values must keep that visual relationship.
const BELT_INNER: float = 0.40
const BELT_OUTER: float = 0.52
const PICK_PAD: float = 6.0

var _hover_id: String = ""


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(360, 360)
	resized.connect(queue_redraw)


func _draw() -> void:
	var rect := get_rect()
	var size_px := rect.size
	var centre := size_px * 0.5
	# Map normalised radius 1.0 → 95% of the shorter half-axis so the
	# outermost orbit (Neptune at ~0.94) stays inside the panel even
	# after labels overflow a few pixels outward.
	var max_r := minf(size_px.x, size_px.y) * 0.5 - 16.0
	max_r = maxf(max_r, 80.0)

	# Asteroid belt — drawn before orbit rings so Ceres's ring + body
	# stack on top of the band. Fill via a fan of thin annular wedges
	# since Godot's draw API has no direct "donut" primitive.
	_draw_belt(centre, max_r * BELT_INNER, max_r * BELT_OUTER)

	# Sun glow + core.
	draw_circle(centre, SUN_GLOW_RADIUS, COLOR_SUN_GLOW)
	draw_circle(centre, SUN_CORE_RADIUS, COLOR_SUN_CORE)

	var selected_id: String = PlayerLoadout.selected_stage_id

	# Orbit rings first, planet bodies second so bodies overdraw the
	# rings cleanly at the intersection point.
	for stage in PlayerLoadout.STAGES:
		var r: float = float(stage.get("orbit_radius", 0.5)) * max_r
		var playable := bool(stage.get("playable", false))
		var ring_colour := COLOR_ORBIT if playable else COLOR_ORBIT_LOCKED
		draw_arc(centre, r, 0.0, TAU, 96, ring_colour, 1.0, true)

	for stage in PlayerLoadout.STAGES:
		_draw_body(stage, centre, max_r, selected_id)


func _draw_belt(centre: Vector2, inner: float, outer: float) -> void:
	# Speckled band: a translucent ring fill plus a sparse pattern of
	# dots to suggest debris. The dots use a deterministic pseudo-random
	# layout so successive redraws don't shimmer.
	var steps := 48
	var prev_in := centre + Vector2(inner, 0.0)
	var prev_out := centre + Vector2(outer, 0.0)
	for i in range(1, steps + 1):
		var a: float = TAU * float(i) / float(steps)
		var dir := Vector2(cos(a), sin(a))
		var next_in := centre + dir * inner
		var next_out := centre + dir * outer
		draw_colored_polygon(
			PackedVector2Array([prev_in, prev_out, next_out, next_in]),
			COLOR_BELT,
		)
		prev_in = next_in
		prev_out = next_out

	var rng := RandomNumberGenerator.new()
	rng.seed = 0xBE17  # deterministic dot pattern
	for i in range(60):
		var a: float = rng.randf() * TAU
		var r: float = lerpf(inner, outer, rng.randf())
		var p := centre + Vector2(cos(a), sin(a)) * r
		draw_circle(p, 1.2, Color(0.78, 0.74, 0.66, 0.55))


func _draw_body(
	stage: Dictionary, centre: Vector2, max_r: float, selected_id: String
) -> void:
	var pos := _body_position(stage, centre, max_r)
	var radius := float(stage.get("body_radius", 6.0))
	var colour: Color = stage.get("color", Color(0.7, 0.7, 0.7))
	var playable := bool(stage.get("playable", false))
	var id := String(stage.get("id", ""))

	if not playable:
		# Wash out colour for locked stages so the playable target
		# reads as the obvious selection.
		colour = colour.lerp(Color(0.18, 0.20, 0.24), 0.55)

	# Saturn ring as a flat ellipse beneath the body — purely cosmetic;
	# there's nothing structural about being Saturn.
	if id == "saturn":
		_draw_saturn_ring(pos, radius, colour, playable)

	draw_circle(pos, radius, colour)
	# Faint outline for legibility against the orbit ring.
	draw_arc(pos, radius, 0.0, TAU, 32, Color(0, 0, 0, 0.4), 1.0, true)

	if id == selected_id:
		draw_arc(pos, radius + 4.0, 0.0, TAU, 48, COLOR_SELECT_RING, 2.0, true)
	elif id == _hover_id and playable:
		draw_arc(pos, radius + 3.0, 0.0, TAU, 48, COLOR_HOVER_RING, 1.5, true)

	var label := String(stage.get("name", ""))
	var font := get_theme_default_font()
	var font_size := 11
	var text_size := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var text_pos := pos + Vector2(radius + 6.0, text_size.y * 0.35)
	# Flip label to the inside if it would otherwise spill past the
	# panel's right edge.
	if text_pos.x + text_size.x > size.x - 4.0:
		text_pos = pos + Vector2(-radius - 6.0 - text_size.x, text_size.y * 0.35)
	draw_string(
		font,
		text_pos,
		label,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		font_size,
		COLOR_LABEL if playable else COLOR_LABEL_LOCKED,
	)


func _draw_saturn_ring(pos: Vector2, body_radius: float, body_colour: Color, playable: bool) -> void:
	var ring_outer := body_radius * 1.9
	var ring_inner := body_radius * 1.25
	var ring_colour := body_colour.lerp(Color(1.0, 1.0, 1.0), 0.25)
	if not playable:
		ring_colour.a = 0.55
	# Squashed ellipse via a triangle fan in screen space.
	var pts_outer := PackedVector2Array()
	var pts_inner := PackedVector2Array()
	var steps := 40
	for i in range(steps + 1):
		var a: float = TAU * float(i) / float(steps)
		pts_outer.append(pos + Vector2(cos(a) * ring_outer, sin(a) * ring_outer * 0.32))
		pts_inner.append(pos + Vector2(cos(a) * ring_inner, sin(a) * ring_inner * 0.32))
	for i in range(steps):
		draw_colored_polygon(
			PackedVector2Array(
				[pts_outer[i], pts_outer[i + 1], pts_inner[i + 1], pts_inner[i]]
			),
			ring_colour,
		)


func _body_position(stage: Dictionary, centre: Vector2, max_r: float) -> Vector2:
	var r: float = float(stage.get("orbit_radius", 0.5)) * max_r
	var a: float = deg_to_rad(float(stage.get("angle_deg", 0.0)))
	return centre + Vector2(cos(a), sin(a)) * r


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		var hover := _stage_at(motion.position)
		var new_hover_id := ""
		if not hover.is_empty() and bool(hover.get("playable", false)):
			new_hover_id = String(hover.get("id", ""))
		if new_hover_id != _hover_id:
			_hover_id = new_hover_id
			mouse_default_cursor_shape = (
				Control.CURSOR_POINTING_HAND if _hover_id != "" else Control.CURSOR_ARROW
			)
			queue_redraw()
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
			return
		var stage := _stage_at(mb.position)
		if stage.is_empty() or not bool(stage.get("playable", false)):
			return
		body_selected.emit(String(stage.get("id", "")))


func _stage_at(local_pos: Vector2) -> Dictionary:
	var rect_size := size
	var centre := rect_size * 0.5
	var max_r := minf(rect_size.x, rect_size.y) * 0.5 - 16.0
	max_r = maxf(max_r, 80.0)
	# Walk in reverse so outer bodies (drawn last) win hit-tests if two
	# discs overlap after a layout tweak.
	for i in range(PlayerLoadout.STAGES.size() - 1, -1, -1):
		var stage: Dictionary = PlayerLoadout.STAGES[i]
		var pos := _body_position(stage, centre, max_r)
		var r := float(stage.get("body_radius", 6.0)) + PICK_PAD
		if local_pos.distance_to(pos) <= r:
			return stage
	return {}


# Called by the menu when the selection changes elsewhere (the Mission
# Select list) so the highlight ring tracks the list selection.
func refresh() -> void:
	queue_redraw()
