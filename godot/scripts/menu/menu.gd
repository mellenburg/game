extends Control
## Pre-game player GUI: four tabs that configure the run before the
## stage scene loads. Layout follows the wireframe at
## `Orbital Defense GUI Mockup _standalone_.html`:
##
##   * Campaign     — pick a stage; LAUNCH starts the game.
##   * Hangar       — choose each unit's weapon loadout.
##   * Orbital Ops  — choose each unit's initial orbit (alt/inc/RAAN/ν).
##   * Research     — placeholder for now.
##
## State lives on the PlayerLoadout autoload so this scene is free to
## be torn down on launch without losing the configuration. SpawnDirector
## reads PlayerLoadout.units when starting the stage.
##
## UI is built imperatively in _ready rather than declared in the .tscn
## so iterating on layout doesn't require touching scene-file boilerplate
## for every row.

const UnitConfig = preload("res://scripts/unit_config.gd")
const SurfaceUnitConfig = preload("res://scripts/surface_unit_config.gd")
const OrbitPreview = preload("res://scripts/menu/orbit_preview.gd")
const SurfacePlacementMap = preload("res://scripts/menu/surface_placement_map.gd")

const STAGE_SCENE_PATH := "res://scenes/main.tscn"

# Right-column width on Campaign / Hangar / Orbital Ops. Fixed so the
# centre column flexes with viewport width but the brief panel stays
# the same comfortable reading width.
const SIDE_PANEL_WIDTH: float = 320.0

const COLOR_BG := Color(0.024, 0.031, 0.043)
const COLOR_PANEL := Color(0.07, 0.085, 0.11)
const COLOR_PANEL_DIM := Color(0.05, 0.06, 0.08)
const COLOR_LINE := Color(0.18, 0.20, 0.24)
const COLOR_FG := Color(0.86, 0.88, 0.92)
const COLOR_FG_DIM := Color(0.55, 0.58, 0.64)
const COLOR_FG_FAINT := Color(0.34, 0.36, 0.40)
const COLOR_ACCENT := Color(1.0, 0.706, 0.329)
const COLOR_OK := Color(0.40, 0.85, 0.55)

var _tabs: TabContainer
var _stage_list: ItemList
var _stage_brief_title: Label
var _stage_brief_meta: Label
var _stage_brief_summary: Label
var _launch_button: Button
var _hangar_root: VBoxContainer
var _orbital_root: VBoxContainer
var _orbit_preview: OrbitPreview
var _surface_root: VBoxContainer
var _surface_placement: SurfacePlacementMap
var _surface_count_label: Label


func _ready() -> void:
	# Coming back to the menu after a run: clear the launched flag so
	# the player has to re-confirm Launch. Units / stage selection are
	# preserved (operator probably wants to retry the same setup).
	PlayerLoadout.launched = false

	anchor_right = 1.0
	anchor_bottom = 1.0
	_paint_background()
	_build_chrome()


func _paint_background() -> void:
	var bg := ColorRect.new()
	bg.color = COLOR_BG
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)


func _build_chrome() -> void:
	var root := VBoxContainer.new()
	root.anchor_right = 1.0
	root.anchor_bottom = 1.0
	root.add_theme_constant_override("separation", 0)
	add_child(root)

	root.add_child(_build_topbar())

	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tabs.add_theme_color_override("font_selected_color", COLOR_ACCENT)
	_tabs.add_theme_color_override("font_unselected_color", COLOR_FG_DIM)
	root.add_child(_tabs)

	var campaign := _build_campaign_tab()
	campaign.name = "Campaign"
	_tabs.add_child(campaign)

	var hangar := _build_hangar_tab()
	hangar.name = "Hangar"
	_tabs.add_child(hangar)

	var orbital := _build_orbital_ops_tab()
	orbital.name = "Orbital Ops"
	_tabs.add_child(orbital)

	var surface := _build_surface_ops_tab()
	surface.name = "Surface Ops"
	_tabs.add_child(surface)

	var research := _build_research_tab()
	research.name = "Research"
	_tabs.add_child(research)


# Title strip across the top — branding + a static hint. The live
# in-game stat row from the wireframe belongs to the in-game HUD, not
# to the pre-game menu, so it's omitted here.
func _build_topbar() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _flat_stylebox(COLOR_PANEL_DIM))
	panel.custom_minimum_size = Vector2(0, 48)

	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 16)
	pad.add_theme_constant_override("margin_right", 16)
	pad.add_theme_constant_override("margin_top", 10)
	pad.add_theme_constant_override("margin_bottom", 6)
	panel.add_child(pad)

	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 16)
	pad.add_child(bar)

	var brand := Label.new()
	brand.text = "GRAVITY/WELL"
	brand.add_theme_color_override("font_color", COLOR_ACCENT)
	brand.add_theme_font_size_override("font_size", 18)
	bar.add_child(brand)

	var version := Label.new()
	version.text = "v0.4.1-MVP · PRE-GAME"
	version.add_theme_color_override("font_color", COLOR_FG_DIM)
	version.add_theme_font_size_override("font_size", 11)
	bar.add_child(version)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(spacer)

	var hint := Label.new()
	hint.text = "Configure your fleet, then return to Campaign and LAUNCH."
	hint.add_theme_color_override("font_color", COLOR_FG_DIM)
	hint.add_theme_font_size_override("font_size", 11)
	bar.add_child(hint)

	var exit_btn := Button.new()
	exit_btn.text = "EXIT"
	exit_btn.add_theme_font_size_override("font_size", 12)
	exit_btn.custom_minimum_size = Vector2(80, 0)
	exit_btn.pressed.connect(_on_exit_pressed)
	bar.add_child(exit_btn)
	return panel


func _on_exit_pressed() -> void:
	get_tree().quit()


# Layout helper. Each tab's body is a margin around an HBox that
# children are appended to as side-by-side columns.
func _padded_hbox() -> HBoxContainer:
	var pad := MarginContainer.new()
	pad.anchor_right = 1.0
	pad.anchor_bottom = 1.0
	pad.add_theme_constant_override("margin_left", 12)
	pad.add_theme_constant_override("margin_right", 12)
	pad.add_theme_constant_override("margin_top", 12)
	pad.add_theme_constant_override("margin_bottom", 12)

	var hbox := HBoxContainer.new()
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hbox.add_theme_constant_override("separation", 12)
	pad.add_child(hbox)

	# Stash the inner hbox on the pad so callers (which only hold a
	# reference to the pad they hand to the TabContainer) can append
	# columns by walking through pad.get_child(0).
	pad.set_meta("_columns", hbox)
	return hbox


# Title-bar section panel. Returns a (panel, content_vbox) pair: caller
# adds `panel` to the layout HBox and appends content into `content`.
# Splitting these two roles avoids the metadata shuffle the previous
# revision needed.
func _section(header: String, fixed_width: float) -> Array:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _flat_stylebox(COLOR_PANEL))
	if fixed_width > 0.0:
		panel.custom_minimum_size = Vector2(fixed_width, 0)
	else:
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 12)
	pad.add_theme_constant_override("margin_right", 12)
	pad.add_theme_constant_override("margin_top", 10)
	pad.add_theme_constant_override("margin_bottom", 10)
	panel.add_child(pad)

	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 8)
	pad.add_child(col)

	var hdr := Label.new()
	hdr.text = header.to_upper()
	hdr.add_theme_color_override("font_color", COLOR_FG_DIM)
	hdr.add_theme_font_size_override("font_size", 11)
	col.add_child(hdr)
	col.add_child(_hr())

	return [panel, col]


# ---------------------------------------------------------------- Campaign

func _build_campaign_tab() -> Control:
	var hbox := _padded_hbox()
	var pad: Control = hbox.get_parent() as Control

	# Left column: stage list.
	var left := _section("Theatre Index", 280)
	hbox.add_child(left[0])
	_stage_list = ItemList.new()
	_stage_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_stage_list.allow_reselect = true
	_stage_list.add_theme_color_override("font_color", COLOR_FG)
	_stage_list.add_theme_color_override("font_selected_color", COLOR_ACCENT)
	for stage in PlayerLoadout.STAGES:
		var label := "%s\n%s · %s · %d waves" % [
			stage["name"],
			stage["code"],
			stage["difficulty"],
			int(stage["waves"]),
		]
		if not bool(stage.get("playable", false)):
			label += "  [LOCKED]"
		var idx := _stage_list.add_item(label)
		if not bool(stage.get("playable", false)):
			_stage_list.set_item_custom_fg_color(idx, COLOR_FG_FAINT)
			_stage_list.set_item_disabled(idx, true)
		if stage.get("id", "") == PlayerLoadout.selected_stage_id:
			_stage_list.select(idx)
	_stage_list.item_selected.connect(_on_stage_selected)
	left[1].add_child(_stage_list)

	# Centre column: system-map placeholder. The decorative orrery
	# from the wireframe isn't on the MVP critical path; the slot is
	# reserved here so the layout matches.
	var center := _section("Theatre Map", 0)
	hbox.add_child(center[0])
	var center_note := Label.new()
	center_note.text = "(System map placeholder)"
	center_note.add_theme_color_override("font_color", COLOR_FG_DIM)
	center_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center_note.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	center_note.size_flags_vertical = Control.SIZE_EXPAND_FILL
	center_note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center[1].add_child(center_note)

	# Right column: stage brief + LAUNCH.
	var right := _section("Mission Brief", SIDE_PANEL_WIDTH)
	hbox.add_child(right[0])

	_stage_brief_title = Label.new()
	_stage_brief_title.add_theme_color_override("font_color", COLOR_FG)
	_stage_brief_title.add_theme_font_size_override("font_size", 18)
	right[1].add_child(_stage_brief_title)

	_stage_brief_meta = Label.new()
	_stage_brief_meta.add_theme_color_override("font_color", COLOR_FG_DIM)
	_stage_brief_meta.add_theme_font_size_override("font_size", 11)
	right[1].add_child(_stage_brief_meta)

	right[1].add_child(_hr())

	_stage_brief_summary = Label.new()
	_stage_brief_summary.add_theme_color_override("font_color", COLOR_FG)
	_stage_brief_summary.add_theme_font_size_override("font_size", 12)
	_stage_brief_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_stage_brief_summary.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right[1].add_child(_stage_brief_summary)

	_launch_button = Button.new()
	_launch_button.text = "LAUNCH ▶"
	_launch_button.custom_minimum_size = Vector2(0, 44)
	_launch_button.add_theme_font_size_override("font_size", 14)
	_launch_button.pressed.connect(_on_launch_pressed)
	right[1].add_child(_launch_button)

	_refresh_stage_brief()
	return pad


func _on_stage_selected(idx: int) -> void:
	if idx < 0 or idx >= PlayerLoadout.STAGES.size():
		return
	var stage: Dictionary = PlayerLoadout.STAGES[idx]
	# Locked rows are flagged disabled in the ItemList, which already
	# blocks selection on click. Belt-and-braces: refuse to write a
	# locked id either way so manual API wiring can't ship.
	if not bool(stage.get("playable", false)):
		return
	PlayerLoadout.selected_stage_id = String(stage.get("id", ""))
	_refresh_stage_brief()


func _refresh_stage_brief() -> void:
	var stage := PlayerLoadout.selected_stage()
	if stage.is_empty():
		_stage_brief_title.text = "(no stage selected)"
		_stage_brief_meta.text = ""
		_stage_brief_summary.text = ""
	else:
		_stage_brief_title.text = String(stage.get("name", ""))
		_stage_brief_meta.text = "%s · %s · %d waves" % [
			stage.get("code", ""),
			stage.get("difficulty", ""),
			int(stage.get("waves", 0)),
		]
		_stage_brief_summary.text = String(stage.get("summary", ""))
	_launch_button.disabled = not PlayerLoadout.can_launch()
	if _launch_button.disabled:
		_launch_button.text = "LAUNCH (LOCKED)"
		_launch_button.add_theme_color_override("font_color", COLOR_FG_FAINT)
	else:
		_launch_button.text = "LAUNCH ▶"
		_launch_button.add_theme_color_override("font_color", COLOR_ACCENT)


func _on_launch_pressed() -> void:
	if not PlayerLoadout.can_launch():
		return
	PlayerLoadout.launched = true
	get_tree().change_scene_to_file(STAGE_SCENE_PATH)


# ---------------------------------------------------------------- Hangar

func _build_hangar_tab() -> Control:
	var hbox := _padded_hbox()
	var pad: Control = hbox.get_parent() as Control

	var center := _section("Hangar · Unit Loadout", 0)
	hbox.add_child(center[0])
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center[1].add_child(scroll)

	_hangar_root = VBoxContainer.new()
	_hangar_root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hangar_root.add_theme_constant_override("separation", 8)
	scroll.add_child(_hangar_root)

	for i in range(PlayerLoadout.units.size()):
		_hangar_root.add_child(_build_hangar_row(i))

	# Right brief: explain what the choices mean. Static — no per-unit
	# preview yet, but the wireframe mockup keeps a column here so the
	# layout space is reserved for the eventual designer view.
	var right := _section("Loadout Notes", SIDE_PANEL_WIDTH)
	hbox.add_child(right[0])
	var notes := Label.new()
	notes.text = (
		"Pick the weapon mix for each unit before launch.\n\n"
		+ "• Laser — continuous beam, no recoil. Good for sustained DPS\n"
		+ "  on inbound clusters but drains the energy reservoir.\n\n"
		+ "• Railgun — high-impulse kinetic. Each shot recoil-shifts the\n"
		+ "  firing satellite's orbit, so use sparingly from anchor passes.\n\n"
		+ "• Laser + Railgun — flexible but heavier; one of each on the\n"
		+ "  same hull splits the energy budget."
	)
	notes.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	notes.add_theme_color_override("font_color", COLOR_FG_DIM)
	notes.add_theme_font_size_override("font_size", 12)
	right[1].add_child(notes)

	return pad


func _build_hangar_row(index: int) -> Control:
	var unit: UnitConfig = PlayerLoadout.units[index]

	var row := PanelContainer.new()
	row.add_theme_stylebox_override("panel", _flat_stylebox(COLOR_PANEL_DIM))
	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 12)
	pad.add_theme_constant_override("margin_right", 12)
	pad.add_theme_constant_override("margin_top", 10)
	pad.add_theme_constant_override("margin_bottom", 10)
	row.add_child(pad)
	var inner := HBoxContainer.new()
	inner.add_theme_constant_override("separation", 12)
	pad.add_child(inner)

	var name_label := Label.new()
	name_label.text = unit.name
	name_label.custom_minimum_size = Vector2(70, 0)
	name_label.add_theme_color_override("font_color", COLOR_ACCENT)
	name_label.add_theme_font_size_override("font_size", 14)
	inner.add_child(name_label)

	var picker := OptionButton.new()
	for label in UnitConfig.WEAPON_LABELS:
		picker.add_item(label)
	picker.select(unit.weapon_kind)
	picker.custom_minimum_size = Vector2(220, 0)
	picker.item_selected.connect(_on_weapon_picked.bind(index))
	inner.add_child(picker)

	var desc := Label.new()
	desc.text = _weapon_blurb(unit.weapon_kind)
	desc.add_theme_color_override("font_color", COLOR_FG_DIM)
	desc.add_theme_font_size_override("font_size", 11)
	desc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# Tag with a stable name so the picker callback can rewrite it
	# without re-walking the row's children by index.
	desc.name = "Blurb"
	inner.add_child(desc)

	return row


func _on_weapon_picked(weapon_kind: int, unit_index: int) -> void:
	if unit_index < 0 or unit_index >= PlayerLoadout.units.size():
		return
	var unit: UnitConfig = PlayerLoadout.units[unit_index]
	unit.weapon_kind = weapon_kind
	var row: Control = _hangar_root.get_child(unit_index) as Control
	if row == null:
		return
	var blurb: Label = row.find_child("Blurb", true, false) as Label
	if blurb != null:
		blurb.text = _weapon_blurb(weapon_kind)
	# The orbital-ops tab shows the chosen weapon as a chip; refresh
	# that label too so the two tabs stay consistent without polling.
	if _orbital_root != null and unit_index < _orbital_root.get_child_count():
		var orow: Control = _orbital_root.get_child(unit_index) as Control
		var chip: Label = orow.find_child("WeaponChip", true, false) as Label
		if chip != null:
			chip.text = UnitConfig.WEAPON_LABELS[weapon_kind]


func _weapon_blurb(weapon_kind: int) -> String:
	match weapon_kind:
		UnitConfig.WEAPON_LASER:
			return "Continuous beam · no recoil · drains energy."
		UnitConfig.WEAPON_RAILGUN:
			return "Kinetic impulse · recoil shifts orbit · slow cooldown."
		UnitConfig.WEAPON_MIXED:
			return "Flexible · split energy budget · heavier hull."
	return ""


# ---------------------------------------------------------------- Orbital Ops

func _build_orbital_ops_tab() -> Control:
	var hbox := _padded_hbox()
	var pad: Control = hbox.get_parent() as Control

	var left := _section("Initial Orbits", 540)
	hbox.add_child(left[0])
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left[1].add_child(scroll)

	_orbital_root = VBoxContainer.new()
	_orbital_root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_orbital_root.add_theme_constant_override("separation", 10)
	scroll.add_child(_orbital_root)

	for i in range(PlayerLoadout.units.size()):
		_orbital_root.add_child(_build_orbit_row(i))

	# Centre: 2D top-down preview that redraws when sliders change.
	var center := _section("Equatorial Preview", 0)
	hbox.add_child(center[0])
	_orbit_preview = OrbitPreview.new()
	_orbit_preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_orbit_preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	center[1].add_child(_orbit_preview)
	_orbit_preview.refresh()

	return pad


func _build_orbit_row(index: int) -> Control:
	var unit: UnitConfig = PlayerLoadout.units[index]

	var row := PanelContainer.new()
	row.add_theme_stylebox_override("panel", _flat_stylebox(COLOR_PANEL_DIM))
	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 12)
	pad.add_theme_constant_override("margin_right", 12)
	pad.add_theme_constant_override("margin_top", 10)
	pad.add_theme_constant_override("margin_bottom", 10)
	row.add_child(pad)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	pad.add_child(col)

	var head := HBoxContainer.new()
	var name_label := Label.new()
	name_label.text = unit.name
	name_label.add_theme_color_override("font_color", COLOR_ACCENT)
	name_label.add_theme_font_size_override("font_size", 14)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(name_label)
	var weapon_chip := Label.new()
	weapon_chip.name = "WeaponChip"
	weapon_chip.text = UnitConfig.WEAPON_LABELS[unit.weapon_kind]
	weapon_chip.add_theme_color_override("font_color", COLOR_FG_DIM)
	weapon_chip.add_theme_font_size_override("font_size", 11)
	head.add_child(weapon_chip)
	col.add_child(head)

	col.add_child(_orbit_slider_row(
		"Altitude (km)", unit.altitude_km,
		UnitConfig.ALT_MIN_KM, UnitConfig.ALT_MAX_KM, 10.0,
		index, "altitude_km",
	))
	col.add_child(_orbit_slider_row(
		"Inclination (°)", unit.inclination_deg,
		UnitConfig.INC_MIN_DEG, UnitConfig.INC_MAX_DEG, 1.0,
		index, "inclination_deg",
	))
	col.add_child(_orbit_slider_row(
		"RAAN (°)", unit.raan_deg,
		UnitConfig.RAAN_MIN_DEG, UnitConfig.RAAN_MAX_DEG, 1.0,
		index, "raan_deg",
	))
	col.add_child(_orbit_slider_row(
		"True Anomaly (°)", unit.true_anomaly_deg,
		UnitConfig.NU_MIN_DEG, UnitConfig.NU_MAX_DEG, 1.0,
		index, "true_anomaly_deg",
	))
	return row


# Build a [label, slider, value] row. The slider drives the named
# UnitConfig field directly; the linked Label updates as the operator
# drags so the numeric readout stays in sync without polling.
func _orbit_slider_row(
	label: String,
	value: float,
	min_v: float,
	max_v: float,
	step: float,
	unit_index: int,
	field: String,
) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var lbl := Label.new()
	lbl.text = label
	lbl.custom_minimum_size = Vector2(140, 0)
	lbl.add_theme_color_override("font_color", COLOR_FG_DIM)
	lbl.add_theme_font_size_override("font_size", 11)
	row.add_child(lbl)

	var slider := HSlider.new()
	slider.min_value = min_v
	slider.max_value = max_v
	slider.step = step
	slider.value = value
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.custom_minimum_size = Vector2(180, 0)
	row.add_child(slider)

	var readout := Label.new()
	readout.text = "%.0f" % value
	readout.custom_minimum_size = Vector2(60, 0)
	readout.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	readout.add_theme_color_override("font_color", COLOR_FG)
	readout.add_theme_font_size_override("font_size", 11)
	row.add_child(readout)

	slider.value_changed.connect(
		func(new_value: float) -> void:
			_on_orbit_field_changed(unit_index, field, new_value, readout)
	)
	return row


func _on_orbit_field_changed(
	unit_index: int, field: String, new_value: float, readout: Label
) -> void:
	if unit_index < 0 or unit_index >= PlayerLoadout.units.size():
		return
	var unit: UnitConfig = PlayerLoadout.units[unit_index]
	unit.set(field, new_value)
	readout.text = "%.0f" % new_value
	if _orbit_preview != null:
		_orbit_preview.refresh()


# ---------------------------------------------------------------- Surface Ops

# Tab layout: left column shows the list of placed surface units (with
# a remove button per row), centre column is a click-to-place world
# map, right column carries notes. The placement map's `placed` signal
# is wired straight to PlayerLoadout.add_surface_unit so the menu
# state stays the single source of truth — clicking the map mutates
# PlayerLoadout.surface_units, which is what the spawner reads on
# Launch.
func _build_surface_ops_tab() -> Control:
	var hbox := _padded_hbox()
	var pad: Control = hbox.get_parent() as Control

	# Left column: placed-unit list.
	var left := _section("Placed Installations", 320)
	hbox.add_child(left[0])

	_surface_count_label = Label.new()
	_surface_count_label.add_theme_color_override("font_color", COLOR_FG_DIM)
	_surface_count_label.add_theme_font_size_override("font_size", 11)
	left[1].add_child(_surface_count_label)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left[1].add_child(scroll)

	_surface_root = VBoxContainer.new()
	_surface_root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_surface_root.add_theme_constant_override("separation", 6)
	scroll.add_child(_surface_root)

	# Centre column: click-to-place equirectangular world map.
	var center := _section("Surface Map · Click to Place", 0)
	hbox.add_child(center[0])
	_surface_placement = SurfacePlacementMap.new()
	_surface_placement.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_surface_placement.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_surface_placement.placed.connect(_on_surface_placed)
	center[1].add_child(_surface_placement)

	# Right column: explanatory notes.
	var right := _section("Surface Ops Notes", SIDE_PANEL_WIDTH)
	hbox.add_child(right[0])
	var notes := Label.new()
	notes.text = (
		"Click the world map to drop a fixed surface installation at\n"
		+ "that lat / lon. Each unit defends the ground around it with\n"
		+ "a laser turret, draws from its own energy reservoir, and\n"
		+ "rotates with Earth's daily spin.\n\n"
		+ "• Place as many as you like — there's no fleet cap here.\n"
		+ "• Surface installations don't accept thrust input; they just\n"
		+ "  fire when a hostile body crosses their engagement envelope.\n"
		+ "• Their positions are reflected on the in-game minimap as\n"
		+ "  green squares so you can correlate fire with ground cover.\n\n"
		+ "Use the Remove button on a row to drop an installation before\n"
		+ "Launch — once the stage is running the placement is locked in."
	)
	notes.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	notes.add_theme_color_override("font_color", COLOR_FG_DIM)
	notes.add_theme_font_size_override("font_size", 12)
	right[1].add_child(notes)

	_refresh_surface_list()
	return pad


func _on_surface_placed(lat_deg: float, lon_deg: float) -> void:
	PlayerLoadout.add_surface_unit(lat_deg, lon_deg)
	_refresh_surface_list()
	if _surface_placement != null:
		_surface_placement.refresh()


# Rebuild the per-unit row list from PlayerLoadout.surface_units.
# Cheap brute-force replace — surface unit count is small (single
# digits in expected play) so reusing rows isn't worth the bookkeeping
# the orbital roster pays for.
func _refresh_surface_list() -> void:
	if _surface_root == null:
		return
	for child in _surface_root.get_children():
		_surface_root.remove_child(child)
		child.queue_free()
	var configs: Array[SurfaceUnitConfig] = PlayerLoadout.surface_units
	if _surface_count_label != null:
		_surface_count_label.text = (
			"%d installation(s) placed" % configs.size()
		)
	for i in range(configs.size()):
		_surface_root.add_child(_build_surface_row(i, configs[i]))


func _build_surface_row(index: int, cfg: SurfaceUnitConfig) -> Control:
	var row := PanelContainer.new()
	row.add_theme_stylebox_override("panel", _flat_stylebox(COLOR_PANEL_DIM))
	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 10)
	pad.add_theme_constant_override("margin_right", 10)
	pad.add_theme_constant_override("margin_top", 8)
	pad.add_theme_constant_override("margin_bottom", 8)
	row.add_child(pad)

	var inner := HBoxContainer.new()
	inner.add_theme_constant_override("separation", 8)
	pad.add_child(inner)

	var name_label := Label.new()
	name_label.text = cfg.name
	name_label.custom_minimum_size = Vector2(50, 0)
	name_label.add_theme_color_override("font_color", COLOR_ACCENT)
	name_label.add_theme_font_size_override("font_size", 13)
	inner.add_child(name_label)

	var coords := Label.new()
	coords.text = "%s  %s" % [_format_lat(cfg.lat_deg), _format_lon(cfg.lon_deg)]
	coords.add_theme_color_override("font_color", COLOR_FG_DIM)
	coords.add_theme_font_size_override("font_size", 11)
	coords.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inner.add_child(coords)

	var remove := Button.new()
	remove.text = "Remove"
	remove.add_theme_font_size_override("font_size", 11)
	remove.custom_minimum_size = Vector2(72, 0)
	remove.pressed.connect(_on_surface_remove_pressed.bind(index))
	inner.add_child(remove)

	return row


func _on_surface_remove_pressed(index: int) -> void:
	PlayerLoadout.remove_surface_unit(index)
	_refresh_surface_list()
	if _surface_placement != null:
		_surface_placement.refresh()


static func _format_lat(lat: float) -> String:
	var hemi := "N" if lat >= 0.0 else "S"
	return "%.1f° %s" % [absf(lat), hemi]


static func _format_lon(lon: float) -> String:
	var hemi := "E" if lon >= 0.0 else "W"
	return "%.1f° %s" % [absf(lon), hemi]


# ---------------------------------------------------------------- Research

func _build_research_tab() -> Control:
	var hbox := _padded_hbox()
	var pad: Control = hbox.get_parent() as Control

	var box := _section("Research", 0)
	hbox.add_child(box[0])

	var msg := Label.new()
	msg.text = "Research tree coming soon."
	msg.add_theme_color_override("font_color", COLOR_FG_DIM)
	msg.add_theme_font_size_override("font_size", 16)
	msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	msg.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	msg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	msg.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box[1].add_child(msg)

	return pad


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
