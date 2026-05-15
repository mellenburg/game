class_name PlansList
extends Control
## Lower-right overlay listing every committed planning maneuver: ship
## name, time-to-burn, and a directional summary of the queued Δv.
## Clicking a row routes back into planning mode at the maneuver's
## scrub point so the operator can inspect (and with cancel_plan,
## remove) the entry.
##
## EarthSystem owns the plan list; this panel reads it directly each
## frame — same no-signal pattern ImpactMap / RadarMap use. The
## EarthSystem reference is bound at scene boot.

const Satellite = preload("res://scripts/satellite.gd")
const SimClock = preload("res://scripts/sim_clock.gd")

const PANEL_SIZE := Vector2(436.0, 378.0)
const PANEL_BG := Color(0.04, 0.04, 0.08, 0.85)
const VIEW_BG := Color(0.02, 0.04, 0.07, 0.95)
const TITLE_COLOR := Color(0.85, 0.92, 1.0)
const ROW_HEIGHT: float = 44.0
const ROW_BG := Color(0.08, 0.10, 0.14, 0.92)
const ROW_BG_SELECTED := Color(0.18, 0.32, 0.20, 0.95)
const ROW_BG_HOVER := Color(0.12, 0.16, 0.20, 0.95)
const ROW_FG := Color(0.86, 0.88, 0.92)
const ROW_FG_DIM := Color(0.55, 0.58, 0.64)
const ROW_FG_ACCENT := Color(1.0, 0.706, 0.329)

const PAD_LEFT: float = 8.0
const PAD_RIGHT: float = 8.0
const PAD_TOP: float = 22.0
const PAD_BOTTOM: float = 32.0
const ROW_GAP: float = 4.0

# Bound by EarthSystem at scene boot. The panel reads .committed_plans
# and .selected_plan_index directly off the controller, and calls back
# into select_plan() / clear_selection() when the operator clicks a row.
var earth_system: Node = null

var _panel: Panel
var _title: Label
var _scroll: ScrollContainer
var _rows: VBoxContainer
var _hint: RichTextLabel
# Cached signature of the last-rendered plan list so we only rebuild
# the row Controls when the data actually changes — saves a heap of
# Button allocations per second while the panel sits visible.
var _last_signature: String = ""


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = PANEL_SIZE
	size = PANEL_SIZE

	_panel = Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL_BG
	sb.set_corner_radius_all(6)
	_panel.add_theme_stylebox_override("panel", sb)
	_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_panel)

	_title = Label.new()
	_title.text = "Planned maneuvers"
	_title.add_theme_font_size_override("font_size", 12)
	_title.add_theme_color_override("font_color", TITLE_COLOR)
	_title.position = Vector2(PAD_LEFT, 4.0)
	_title.size = Vector2(PANEL_SIZE.x - PAD_LEFT - PAD_RIGHT, 16.0)
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_title)

	var view_bg := ColorRect.new()
	view_bg.position = Vector2(PAD_LEFT, PAD_TOP)
	view_bg.size = Vector2(
		PANEL_SIZE.x - PAD_LEFT - PAD_RIGHT,
		PANEL_SIZE.y - PAD_TOP - PAD_BOTTOM,
	)
	view_bg.color = VIEW_BG
	view_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(view_bg)

	_scroll = ScrollContainer.new()
	_scroll.position = view_bg.position + Vector2(4.0, 4.0)
	_scroll.size = view_bg.size - Vector2(8.0, 8.0)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(_scroll)

	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", int(ROW_GAP))
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_rows)

	_hint = RichTextLabel.new()
	_hint.bbcode_enabled = true
	_hint.scroll_active = false
	_hint.fit_content = true
	_hint.position = Vector2(
		PAD_LEFT,
		PANEL_SIZE.y - PAD_BOTTOM + 4.0,
	)
	_hint.size = Vector2(
		PANEL_SIZE.x - PAD_LEFT - PAD_RIGHT,
		PAD_BOTTOM - 6.0,
	)
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hint)


func _process(_delta: float) -> void:
	if not visible:
		return
	_refresh()


# Rebuild row controls only when the underlying list has changed. The
# signature is the cheapest stable digest we can compute without
# touching the satellites themselves — order, count, Δv, and burn time
# are enough to detect any mutation that needs a redraw.
func _refresh() -> void:
	if earth_system == null:
		_last_signature = ""
		_clear_rows()
		_update_hint(0)
		return
	var plans: Array = earth_system.committed_plans
	var selected: int = earth_system.selected_plan_index
	var sim_time: float = earth_system.sim_time
	var sig := _signature(plans, selected, sim_time)
	if sig == _last_signature:
		# Even with stable rows, the "in N seconds" countdown moves —
		# refresh the time labels in place so they stay live.
		_refresh_time_labels(plans, sim_time)
		return
	_last_signature = sig
	_clear_rows()
	# Bucket plans by their owning satellite so each unit gets a
	# header followed by its plans. Preserves first-seen order across
	# units so the panel layout is stable across renders.
	var groups: Dictionary = {}
	var group_order: Array = []
	for i in range(plans.size()):
		var plan: Dictionary = plans[i]
		var sat: Satellite = plan.get("sat")
		var key: int = sat.get_instance_id() if sat != null else 0
		if not groups.has(key):
			groups[key] = []
			group_order.append(key)
		groups[key].append(i)
	for key in group_order:
		var plan_indices: Array = groups[key]
		var first_plan: Dictionary = plans[int(plan_indices[0])]
		var owner: Satellite = first_plan.get("sat")
		_rows.add_child(_build_group_header(owner))
		# Sort each group's plans chronologically so a stack of
		# committed burns reads top-down in firing order.
		var sorted_indices: Array = plan_indices.duplicate()
		sorted_indices.sort_custom(
			func(a: int, b: int) -> bool:
				return float(plans[a].get("apply_at", 0.0)) \
					< float(plans[b].get("apply_at", 0.0))
		)
		for idx_v in sorted_indices:
			var idx: int = int(idx_v)
			_rows.add_child(
				_build_row(idx, plans[idx], idx == selected, sim_time)
			)
	_update_hint(plans.size())


# Banner row for a satellite — its display name in the accent colour
# above the indented plan rows beneath. Mouse_filter set to IGNORE so
# clicks fall through to the panel background; only the plan rows
# themselves are clickable.
func _build_group_header(sat: Satellite) -> Control:
	var box := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.0, 0.0, 0.0, 0.0)
	sb.content_margin_left = 4.0
	sb.content_margin_right = 4.0
	sb.content_margin_top = 6.0
	sb.content_margin_bottom = 0.0
	box.add_theme_stylebox_override("panel", sb)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var label := Label.new()
	label.text = (
		sat.unit_name if sat != null and sat.unit_name != "" else "Unnamed unit"
	)
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", ROW_FG_ACCENT)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(label)
	return box


func _signature(plans: Array, selected: int, sim_time: float) -> String:
	# sim_time is intentionally omitted from the signature so the rebuild
	# isn't triggered every tick — _refresh_time_labels handles the
	# countdown update path. selected is in the signature so picking a
	# different row repaints the green highlight.
	var parts := PackedStringArray()
	parts.append(str(selected))
	for plan: Dictionary in plans:
		var sat: Satellite = plan.get("sat")
		var dv: Vector3 = plan.get("dv", Vector3.ZERO)
		parts.append("%s|%.3f|%.3f|%.3f|%.1f|%s" % [
			sat.get_instance_id() if sat != null else 0,
			dv.x, dv.y, dv.z,
			float(plan.get("apply_at", 0.0)),
			"applied" if bool(plan.get("applied", false)) else "pending",
		])
	return "\n".join(parts)


func _refresh_time_labels(plans: Array, sim_time: float) -> void:
	# Walk the children and rewrite the countdown label on every row
	# that carries a `plan_index` meta. Group headers don't carry one
	# and are skipped automatically. A mid-frame mutation that drops
	# the source plan just falls through the bounds check — the next
	# _refresh() rebuilds from scratch anyway.
	for child in _rows.get_children():
		var row := child as Control
		if row == null or not row.has_meta("plan_index"):
			continue
		var idx: int = int(row.get_meta("plan_index"))
		if idx < 0 or idx >= plans.size():
			continue
		var time_label := row.get_node_or_null("Time") as RichTextLabel
		if time_label == null:
			continue
		var apply_at: float = float(plans[idx].get("apply_at", 0.0))
		var eta: float = maxf(apply_at - sim_time, 0.0)
		time_label.text = _format_eta_bbcode(eta, apply_at)


func _clear_rows() -> void:
	for child in _rows.get_children():
		child.queue_free()


func _build_row(
	index: int, plan: Dictionary, is_selected: bool, sim_time: float,
) -> Control:
	var btn := Button.new()
	btn.flat = true
	btn.toggle_mode = false
	btn.custom_minimum_size = Vector2(0.0, ROW_HEIGHT)
	btn.focus_mode = Control.FOCUS_NONE
	# Tag the row with its plan index so _refresh_time_labels can
	# rebind the countdown without needing the parent-container order
	# to match the plans array.
	btn.set_meta("plan_index", index)
	# Whole-row click target. Apply a coloured panel under the contents
	# rather than tinting the button itself so the green-selected state
	# reads cleanly even in Godot's default Button skin.
	var sb := StyleBoxFlat.new()
	sb.bg_color = ROW_BG_SELECTED if is_selected else ROW_BG
	sb.set_corner_radius_all(4)
	btn.add_theme_stylebox_override("normal", sb)
	btn.add_theme_stylebox_override("hover", _row_stylebox(ROW_BG_HOVER))
	btn.add_theme_stylebox_override("pressed", _row_stylebox(ROW_BG_SELECTED))
	btn.pressed.connect(func() -> void: _on_row_pressed(index))

	var hbox := HBoxContainer.new()
	hbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	hbox.add_theme_constant_override("separation", 8)
	hbox.offset_left = 8.0
	hbox.offset_right = -8.0
	hbox.offset_top = 4.0
	hbox.offset_bottom = -4.0
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(hbox)

	# Owning-unit name lives on the group header, so each row collapses
	# to a single line of Δv plus the countdown on the right.
	var dv: Vector3 = plan.get("dv", Vector3.ZERO)
	var dv_label := Label.new()
	dv_label.text = "Δv  %s" % _format_dv(dv)
	dv_label.add_theme_font_size_override("font_size", 12)
	dv_label.add_theme_color_override("font_color", ROW_FG)
	dv_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dv_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	dv_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(dv_label)

	var time_label := RichTextLabel.new()
	time_label.name = "Time"
	time_label.bbcode_enabled = true
	time_label.scroll_active = false
	time_label.fit_content = true
	time_label.custom_minimum_size = Vector2(160.0, 0.0)
	time_label.size_flags_horizontal = Control.SIZE_SHRINK_END
	time_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	time_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var apply_at: float = float(plan.get("apply_at", 0.0))
	time_label.text = _format_eta_bbcode(maxf(apply_at - sim_time, 0.0), apply_at)
	hbox.add_child(time_label)

	return btn


func _row_stylebox(color: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(4)
	return sb


func _on_row_pressed(index: int) -> void:
	if earth_system == null:
		return
	earth_system.select_committed_plan(index)


func _format_dv(dv: Vector3) -> String:
	# Local frame: x = prograde/retrograde, y = radial-out / radial-in,
	# z = normal-up / normal-down. Convert km/s → m/s for the readout
	# so the order of magnitude matches the in-flight HUD's Δv labels.
	var parts := PackedStringArray()
	parts.append("%+d pro" % int(round(dv.x * 1000.0)))
	parts.append("%+d rad" % int(round(dv.y * 1000.0)))
	parts.append("%+d nor" % int(round(dv.z * 1000.0)))
	return "  ".join(parts) + " m/s"


func _format_eta_bbcode(eta: float, apply_at: float) -> String:
	var color := "#7fcf7f" if eta > 0.0 else "#9aa9b8"
	var label := _format_eta(eta)
	# Two-line readout: relative ETA on top, absolute UTC underneath so
	# the operator can correlate to mission schedule timestamps.
	return (
		"[right][font_size=12][color=%s]T-%s[/color][/font_size]\n"
		+ "[font_size=10][color=#9aa9b8]%s[/color][/font_size][/right]"
	) % [color, label, SimClock.format_utc(apply_at)]


func _format_eta(eta: float) -> String:
	var s: int = int(round(eta))
	if s < 60:
		return "%ds" % s
	if s < 3600:
		return "%dm %02ds" % [s / 60, s % 60]
	if s < 86400:
		return "%dh %02dm" % [s / 3600, (s % 3600) / 60]
	return "%dd %02dh" % [s / 86400, (s % 86400) / 3600]


func _update_hint(plan_count: int) -> void:
	if _hint == null:
		return
	if plan_count == 0:
		_hint.text = (
			"[font_size=11][color=#9aa9b8]"
			+ "No committed plans.  Press Space to plan a maneuver,"
			+ " Enter to commit."
			+ "[/color][/font_size]"
		)
	else:
		_hint.text = (
			"[font_size=11][color=#9aa9b8]"
			+ "Click a plan to inspect.  X removes the selected plan."
			+ "[/color][/font_size]"
		)
