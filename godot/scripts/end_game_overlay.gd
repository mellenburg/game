class_name EndGameOverlay
extends Control
## End-of-run summary overlay. Bound to the `end_game` action (Enter
## by default), and also openable programmatically via `show_summary`
## when EarthSystem detects the mission has cleared. Pauses the
## simulation, shows a per-unit damage / kill breakdown plus aggregate
## Earth-impact stats, and routes the user back to the pre-game menu
## when acknowledged.
##
## process_mode = ALWAYS so this node keeps ticking once paused —
## without it the Acknowledge input would never fire and the player
## would be stuck.
##
## Built imperatively in `_ready` matching the pause-menu style so the
## scene tree only has to mount one bare Control node.

const Satellite = preload("res://scripts/satellite.gd")

const MENU_SCENE_PATH := "res://scenes/menu.tscn"

const COLOR_OVERLAY := Color(0.0, 0.0, 0.0, 0.65)
const COLOR_PANEL := Color(0.07, 0.085, 0.11)
const COLOR_PANEL_DIM := Color(0.05, 0.06, 0.08)
const COLOR_LINE := Color(0.18, 0.20, 0.24)
const COLOR_FG := Color(0.86, 0.88, 0.92)
const COLOR_FG_DIM := Color(0.55, 0.58, 0.64)
const COLOR_FG_FAINT := Color(0.34, 0.36, 0.40)
const COLOR_ACCENT := Color(1.0, 0.706, 0.329)
const COLOR_DANGER := Color(1.0, 0.45, 0.35)
const COLOR_OK := Color(0.40, 0.85, 0.55)

var _root_panel: PanelContainer
var _content_root: VBoxContainer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	anchor_right = 1.0
	anchor_bottom = 1.0
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	_build_ui()


# Catch the end_game action whether the sim is running or already
# paused — process_mode=ALWAYS keeps this firing during a paused tree.
# Once the overlay's up the action is consumed (set_input_as_handled)
# so a stray repeat tap can't re-show or close the panel.
func _unhandled_input(event: InputEvent) -> void:
	if visible:
		return
	if event.is_action_pressed("end_game"):
		show_summary()
		get_viewport().set_input_as_handled()


# Public entry point so the controller can pop the summary itself when
# the mission clears (every wave fired and no enemies remain). Idempotent
# — once visible the panel keeps its rendered state until acknowledged.
func show_summary() -> void:
	if visible:
		return
	_show_summary()


func _show_summary() -> void:
	var summary := _gather_summary()
	if summary.is_empty():
		# Defensive: if we can't find an EarthSystem (e.g. the scene
		# was reorganised), just open the menu rather than freezing
		# the player on a blank overlay.
		get_tree().change_scene_to_file(MENU_SCENE_PATH)
		return
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = true
	visible = true
	_render_summary(summary)


# Walk up to the EarthSystem ancestor and pull its summary dict. The
# overlay sits under CanvasLayer which sits under EarthSystem, so the
# walk is short — but doing it dynamically keeps the overlay node-path
# independent of the surrounding scene structure.
func _gather_summary() -> Dictionary:
	var node: Node = self
	while node != null:
		if node.has_method("end_game_summary"):
			return node.end_game_summary()
		node = node.get_parent()
	return {}


func _build_ui() -> void:
	var overlay := ColorRect.new()
	overlay.color = COLOR_OVERLAY
	overlay.anchor_right = 1.0
	overlay.anchor_bottom = 1.0
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(overlay)

	_root_panel = PanelContainer.new()
	_root_panel.add_theme_stylebox_override("panel", _flat_stylebox(COLOR_PANEL))
	_root_panel.anchor_left = 0.5
	_root_panel.anchor_top = 0.5
	_root_panel.anchor_right = 0.5
	_root_panel.anchor_bottom = 0.5
	_root_panel.offset_left = -300
	_root_panel.offset_right = 300
	_root_panel.offset_top = -260
	_root_panel.offset_bottom = 260
	add_child(_root_panel)

	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 24)
	pad.add_theme_constant_override("margin_right", 24)
	pad.add_theme_constant_override("margin_top", 20)
	pad.add_theme_constant_override("margin_bottom", 20)
	_root_panel.add_child(pad)

	_content_root = VBoxContainer.new()
	_content_root.add_theme_constant_override("separation", 12)
	pad.add_child(_content_root)


func _render_summary(summary: Dictionary) -> void:
	# Wholesale rebuild so re-opening the panel with a different game
	# state (e.g. after a future "play again" path) doesn't carry
	# stale rows. Cheap — at most a handful of children.
	for child in _content_root.get_children():
		_content_root.remove_child(child)
		child.queue_free()

	var title := Label.new()
	title.text = "MISSION ENDED"
	title.add_theme_color_override("font_color", COLOR_ACCENT)
	title.add_theme_font_size_override("font_size", 22)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_content_root.add_child(title)

	var sub := Label.new()
	sub.text = "Final tally — press Acknowledge to return to base."
	sub.add_theme_color_override("font_color", COLOR_FG_DIM)
	sub.add_theme_font_size_override("font_size", 11)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_content_root.add_child(sub)

	_content_root.add_child(_hr())

	var per_unit: Array = summary.get("per_unit", [])
	_content_root.add_child(_section_header("PER-UNIT"))
	if per_unit.is_empty():
		var none := Label.new()
		none.text = "No player units logged this run."
		none.add_theme_color_override("font_color", COLOR_FG_FAINT)
		none.add_theme_font_size_override("font_size", 11)
		_content_root.add_child(none)
	else:
		_content_root.add_child(_per_unit_header())
		for entry: Dictionary in per_unit:
			_content_root.add_child(_per_unit_row(entry))

	_content_root.add_child(_hr())

	# Earth-side totals: count of impactors that reached the ground +
	# the sum of HP they were still carrying at impact (i.e. the damage
	# Earth absorbed). Both numbers come from EarthSystem's dead-sat
	# sweep so they stay consistent with the in-game kill counter.
	_content_root.add_child(_section_header("EARTH"))
	var impacts := int(summary.get("total_impacts", 0))
	var impact_hp := float(summary.get("total_impact_hp", 0.0))
	_content_root.add_child(_kv_row("Impacts on Earth", "%d" % impacts))
	_content_root.add_child(_kv_row(
		"HP delivered to surface", "%.0f" % impact_hp,
	))

	_content_root.add_child(_hr())

	var ack := Button.new()
	ack.text = "Acknowledge ▶"
	ack.custom_minimum_size = Vector2(0, 40)
	ack.add_theme_font_size_override("font_size", 14)
	ack.pressed.connect(_on_acknowledge_pressed)
	_content_root.add_child(ack)


func _on_acknowledge_pressed() -> void:
	# Unpause first so the new scene's _ready / _process start ticking
	# immediately — change_scene_to_file is queued, so leaving the tree
	# paused would freeze the menu's first frame too.
	get_tree().paused = false
	# Force the cursor visible — we're heading to the menu, not back to
	# the in-game camera, so restoring the saved (captured) mouse mode
	# would leave the player unable to click anything. The menu's _ready
	# also sets this defensively, but doing it here means the cursor
	# reappears immediately even before the scene swap completes.
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	# PlayerLoadout.launched stays true here; the pre-game menu's
	# _ready clears it so a fresh Launch is required to re-enter.
	get_tree().change_scene_to_file(MENU_SCENE_PATH)


# ---------------------------------------------------------------- rows

# 4-column header + row pair so the per-unit list reads as a table.
# Widths are fixed so a long unit name doesn't shove the damage column
# off the right edge.
func _per_unit_header() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.add_child(_col_label("Unit", 130, COLOR_FG_DIM, 11))
	row.add_child(_col_label("Damage", 90, COLOR_FG_DIM, 11, HORIZONTAL_ALIGNMENT_RIGHT))
	row.add_child(_col_label("Kills", 60, COLOR_FG_DIM, 11, HORIZONTAL_ALIGNMENT_RIGHT))
	row.add_child(_col_label("Status", 80, COLOR_FG_DIM, 11, HORIZONTAL_ALIGNMENT_RIGHT))
	return row


func _per_unit_row(entry: Dictionary) -> HBoxContainer:
	var name_text := String(entry.get("unit_name", ""))
	var damage_text := "%.0f" % float(entry.get("damage_dealt", 0.0))
	var kills_text := "%d" % int(entry.get("kills", 0))
	var alive := bool(entry.get("alive", false))
	var status_text := "Alive" if alive else "Lost"
	var status_color := COLOR_OK if alive else COLOR_DANGER

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.add_child(_col_label(name_text, 130, COLOR_FG, 12))
	row.add_child(_col_label(damage_text, 90, COLOR_FG, 12, HORIZONTAL_ALIGNMENT_RIGHT))
	row.add_child(_col_label(kills_text, 60, COLOR_FG, 12, HORIZONTAL_ALIGNMENT_RIGHT))
	row.add_child(_col_label(
		status_text, 80, status_color, 12, HORIZONTAL_ALIGNMENT_RIGHT
	))
	return row


func _kv_row(key: String, value: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var k := Label.new()
	k.text = key
	k.add_theme_color_override("font_color", COLOR_FG_DIM)
	k.add_theme_font_size_override("font_size", 12)
	k.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(k)
	var v := Label.new()
	v.text = value
	v.add_theme_color_override("font_color", COLOR_FG)
	v.add_theme_font_size_override("font_size", 12)
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(v)
	return row


func _section_header(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", COLOR_ACCENT)
	l.add_theme_font_size_override("font_size", 11)
	return l


func _col_label(
	text: String,
	width: float,
	color: Color,
	font_size: int,
	align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT,
) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", color)
	l.add_theme_font_size_override("font_size", font_size)
	l.horizontal_alignment = align
	l.custom_minimum_size = Vector2(width, 0)
	return l


# ---------------------------------------------------------------- helpers

func _flat_stylebox(color: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.border_color = COLOR_LINE
	sb.border_width_left = 1
	sb.border_width_right = 1
	sb.border_width_top = 1
	sb.border_width_bottom = 1
	sb.corner_radius_top_left = 2
	sb.corner_radius_top_right = 2
	sb.corner_radius_bottom_left = 2
	sb.corner_radius_bottom_right = 2
	return sb


func _hr() -> Control:
	var line := ColorRect.new()
	line.color = COLOR_LINE
	line.custom_minimum_size = Vector2(0, 1)
	return line
