class_name EndGameOverlay
extends Control
## End-of-run summary overlay. Bound to the `end_game` action (Enter
## by default), and also openable programmatically via `show_summary`
## when MassCenterSystem detects the mission has cleared. Pauses the
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
var _per_unit_body: VBoxContainer
var _per_unit_toggle: Button
var _per_unit_expanded: bool = false


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
		# Defensive: if we can't find an MassCenterSystem (e.g. the scene
		# was reorganised), just open the menu rather than freezing
		# the player on a blank overlay.
		get_tree().change_scene_to_file(MENU_SCENE_PATH)
		return
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = true
	visible = true
	_render_summary(summary)


# Walk up to the MassCenterSystem ancestor and pull its summary dict. The
# overlay sits under CanvasLayer which sits under MassCenterSystem, so the
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
	# Panel height is bounded; the per-unit table can be arbitrarily long
	# on a busy run, so the middle section is wrapped in a ScrollContainer
	# (see _build_ui below) rather than letting the panel stretch off-
	# screen.
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
	_content_root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pad.add_child(_content_root)


func _render_summary(summary: Dictionary) -> void:
	# Wholesale rebuild so re-opening the panel with a different game
	# state (e.g. after a future "play again" path) doesn't carry
	# stale rows. Cheap — at most a handful of children.
	for child in _content_root.get_children():
		_content_root.remove_child(child)
		child.queue_free()
	_per_unit_body = null
	_per_unit_toggle = null
	_per_unit_expanded = false

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

	# The middle section can overflow on a busy run (long per-unit list,
	# many surface tally rows). Wrap it in a ScrollContainer so the panel
	# stays a fixed size and the player can scroll to whatever they care
	# about, with the title above and Acknowledge button below pinned in
	# place.
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_content_root.add_child(scroll)

	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 12)
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(inner)

	var per_unit: Array = summary.get("per_unit", [])
	# Per-unit stats are detail-on-demand: hidden behind a toggle so the
	# default summary view stays glanceable. The toggle button replaces
	# the bare PER-UNIT section header for that reason.
	var per_unit_count := per_unit.size()
	_per_unit_toggle = Button.new()
	_per_unit_toggle.toggle_mode = true
	_per_unit_toggle.text = _per_unit_toggle_text(false, per_unit_count)
	_per_unit_toggle.add_theme_font_size_override("font_size", 11)
	_per_unit_toggle.toggled.connect(_on_per_unit_toggled)
	inner.add_child(_per_unit_toggle)

	_per_unit_body = VBoxContainer.new()
	_per_unit_body.add_theme_constant_override("separation", 4)
	_per_unit_body.visible = false
	if per_unit.is_empty():
		var none := Label.new()
		none.text = "No player units logged this run."
		none.add_theme_color_override("font_color", COLOR_FG_FAINT)
		none.add_theme_font_size_override("font_size", 11)
		_per_unit_body.add_child(none)
	else:
		_per_unit_body.add_child(_per_unit_header())
		for entry: Dictionary in per_unit:
			_per_unit_body.add_child(_per_unit_row(entry))
	inner.add_child(_per_unit_body)

	inner.add_child(_hr())

	# Earth-side totals: count of impactors that reached the ground +
	# the sum of mass they delivered (i.e. the physical payload the
	# surface absorbed). Both numbers come from MassCenterSystem's dead-sat
	# sweep so they stay consistent with the in-game kill counter.
	inner.add_child(_section_header("SURFACE"))
	var impacts := int(summary.get("total_impacts", 0))
	var impact_mass_kg := float(summary.get("total_impact_mass_kg", 0.0))
	inner.add_child(_kv_row("Impacts on surface", "%d" % impacts))
	inner.add_child(_kv_row(
		"Mass delivered to surface", _format_mass_grams(impact_mass_kg * 1000.0),
	))

	# Atmospheric defense: bodies the atmosphere finished off — either
	# spawned below the burn-up threshold or chipped down by the fleet
	# until the mass-HP coupling drove them inert. The HP shown is the
	# residual HP at burn-up, i.e. the work the atmosphere did for free.
	var atmo_count := int(summary.get("atmosphere_burnup_count", 0))
	var atmo_hp := float(summary.get("atmosphere_burnup_hp", 0.0))
	inner.add_child(_kv_row(
		"Burned up in atmosphere", "%d" % atmo_count,
	))
	inner.add_child(_kv_row(
		"HP lost to atmospheric entry", "%.0f" % atmo_hp,
	))

	var deflected_count := int(summary.get("asteroids_deflected", 0))
	var deflected_mass_kg := float(summary.get("deflected_mass_kg", 0.0))
	inner.add_child(_kv_row(
		"Deflected (escaped system)", "%d" % deflected_count,
	))
	inner.add_child(_kv_row(
		"Mass deflected", _format_mass_grams(deflected_mass_kg * 1000.0),
	))

	var captured_count := int(summary.get("asteroids_captured", 0))
	var captured_mass_kg := float(summary.get("captured_mass_kg", 0.0))
	inner.add_child(_kv_row(
		"Captured (stable orbit)", "%d" % captured_count,
	))
	inner.add_child(_kv_row(
		"Total captured mass", _format_mass_grams(captured_mass_kg * 1000.0),
	))

	_content_root.add_child(_hr())

	var ack := Button.new()
	ack.text = "Acknowledge ▶"
	ack.custom_minimum_size = Vector2(0, 40)
	ack.add_theme_font_size_override("font_size", 14)
	ack.pressed.connect(_on_acknowledge_pressed)
	_content_root.add_child(ack)


func _on_per_unit_toggled(pressed: bool) -> void:
	_per_unit_expanded = pressed
	if _per_unit_body != null:
		_per_unit_body.visible = pressed
	if _per_unit_toggle != null:
		var count := 0
		if _per_unit_body != null:
			# A "no units logged" placeholder counts as zero rows for the
			# header so the button still reads "(0)" cleanly.
			count = _per_unit_body.get_child_count()
			if count == 1 and _per_unit_body.get_child(0) is Label:
				count = 0
		_per_unit_toggle.text = _per_unit_toggle_text(pressed, count)


func _per_unit_toggle_text(expanded: bool, count: int) -> String:
	var arrow := "▼" if expanded else "▶"
	return "%s  PER-UNIT  (%d)" % [arrow, count]


# Format a mass in grams using a unit large enough to keep the leading
# significant figure ≤ 999, so the display fits in three significant
# figures. Steps in factor-1000 jumps from grams up through kg, t, kt,
# Mt, Gt — the asteroid masses involved here can comfortably reach the
# tonne / kilotonne range so the upper bins matter.
func _format_mass_grams(grams: float) -> String:
	var units := [
		["g", 1.0],
		["kg", 1.0e3],
		["t", 1.0e6],
		["kt", 1.0e9],
		["Mt", 1.0e12],
		["Gt", 1.0e15],
	]
	var abs_g: float = absf(grams)
	var label: String = "g"
	var scale: float = 1.0
	for entry in units:
		var entry_label: String = entry[0]
		var entry_scale: float = entry[1]
		if abs_g >= entry_scale:
			label = entry_label
			scale = entry_scale
	var value: float = grams / scale
	var abs_v: float = absf(value)
	# Three significant figures: pick decimal places by magnitude so the
	# total digit count stays at 3.
	var formatted: String = "%.0f" % value
	if abs_v < 10.0:
		formatted = "%.2f" % value
	elif abs_v < 100.0:
		formatted = "%.1f" % value
	return "%s %s" % [formatted, label]


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
