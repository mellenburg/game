extends Control
## Pre-game player GUI. Five tabs that configure the run before the
## stage scene loads:
##
##   * Campaign     — pick a stage; LAUNCH starts the game.
##   * Hangar       — manage the unit pool. Each unit picks a chassis
##                    (slot layout) and a part for every slot.
##                    "Build Unit" creates a fresh entry.
##   * Orbital Ops  — manage launches. Each launch picks an orbit and
##                    must be assigned a unit from the pool; unassigned
##                    launches are dropped on tab-leave / LAUNCH.
##   * Surface Ops  — click-to-place fixed installations on the Earth
##                    surface; placed units spawn anchored to (lat, lon).
##   * Research     — placeholder for now.
##
## State lives on the PlayerLoadout autoload so this scene is free to
## be torn down on launch without losing the configuration.
##
## UI is built imperatively in _ready rather than declared in the .tscn
## so iterating on layout doesn't require touching scene-file boilerplate
## for every row.

const UnitConfig = preload("res://scripts/unit_config.gd")
const UnitChassis = preload("res://scripts/unit_chassis.gd")
const UnitPart = preload("res://scripts/unit_part.gd")
const Launch = preload("res://scripts/launch.gd")
const SurfaceUnitConfig = preload("res://scripts/surface_unit_config.gd")
const OrbitPreview = preload("res://scripts/menu/orbit_preview.gd")
const SurfacePlacementMap = preload("res://scripts/menu/surface_placement_map.gd")

const STAGE_SCENE_PATH := "res://scenes/main.tscn"

# Right-column width on Campaign / Hangar / Orbital Ops. Fixed so the
# centre column flexes with viewport width but the brief panel stays
# the same comfortable reading width.
const SIDE_PANEL_WIDTH: float = 320.0
const HANGAR_LEFT_WIDTH: float = 280.0

const COLOR_BG := Color(0.024, 0.031, 0.043)
const COLOR_PANEL := Color(0.07, 0.085, 0.11)
const COLOR_PANEL_DIM := Color(0.05, 0.06, 0.08)
const COLOR_LINE := Color(0.18, 0.20, 0.24)
const COLOR_FG := Color(0.86, 0.88, 0.92)
const COLOR_FG_DIM := Color(0.55, 0.58, 0.64)
const COLOR_FG_FAINT := Color(0.34, 0.36, 0.40)
const COLOR_ACCENT := Color(1.0, 0.706, 0.329)
const COLOR_OK := Color(0.40, 0.85, 0.55)
const COLOR_WARN := Color(1.0, 0.55, 0.35)

# Stable indices into the Hangar tab's "kind row" — the part-kind
# editor row inside the unit-edit pane is one entry per kind, and we
# rebuild rows by index when the chassis changes. Order matches the
# vertical layout (weapons on top → reactors at bottom).
const KINDS: Array[int] = [
	UnitPart.KIND_WEAPON,
	UnitPart.KIND_RADIATOR,
	UnitPart.KIND_ENERGY_STORAGE,
	UnitPart.KIND_REACTOR,
]

var _tabs: TabContainer
var _stage_list: ItemList
var _stage_brief_title: Label
var _stage_brief_meta: Label
var _stage_brief_summary: Label
var _launch_button: Button

# Hangar state
var _unit_list: ItemList
var _unit_editor: VBoxContainer
var _hangar_summary: VBoxContainer
var _selected_unit_id: String = ""

# Orbital Ops state
var _launches_root: VBoxContainer
var _orbit_preview: OrbitPreview
var _previous_tab_index: int = 0

# Surface Ops state
var _surface_root: VBoxContainer
var _surface_placement: SurfacePlacementMap
var _surface_count_label: Label


func _ready() -> void:
	# Coming back to the menu after a run: clear the launched flag so
	# the player has to re-confirm Launch. Pool / launches / stage
	# selection are preserved (operator probably wants to retry the
	# same setup).
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

	_previous_tab_index = _tabs.current_tab
	_tabs.tab_changed.connect(_on_tab_changed)


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
	version.text = "v0.5.0-MVP · PRE-GAME"
	version.add_theme_color_override("font_color", COLOR_FG_DIM)
	version.add_theme_font_size_override("font_size", 11)
	bar.add_child(version)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(spacer)

	var hint := Label.new()
	hint.text = "Build units, schedule launches, then return to Campaign and LAUNCH."
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
	return hbox


# Title-bar section panel. Returns a (panel, content_vbox) pair: caller
# adds `panel` to the layout HBox and appends content into `content`.
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

	# Centre column: system-map placeholder.
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
		_launch_button.text = "LAUNCH (assign at least one launch)"
		_launch_button.add_theme_color_override("font_color", COLOR_FG_FAINT)
	else:
		_launch_button.text = "LAUNCH ▶"
		_launch_button.add_theme_color_override("font_color", COLOR_ACCENT)


func _on_launch_pressed() -> void:
	# Drop nullified launches before handing off so SpawnDirector only
	# sees rows the operator actually committed to.
	PlayerLoadout.purge_unassigned_launches()
	if not PlayerLoadout.can_launch():
		_refresh_stage_brief()
		return
	PlayerLoadout.launched = true
	get_tree().change_scene_to_file(STAGE_SCENE_PATH)


# Tab navigation gate: when the operator leaves the Orbital Ops tab,
# drop any launches they didn't finish assigning so the orbit preview
# (and the post-launch spawn list) doesn't carry empty rows. Catching
# this on tab_changed instead of only on LAUNCH means the operator's
# pool count and launch count agree the moment they switch back.
func _on_tab_changed(new_index: int) -> void:
	var orbital_index := _tabs.get_node("Orbital Ops").get_index()
	if _previous_tab_index == orbital_index and new_index != orbital_index:
		PlayerLoadout.purge_unassigned_launches()
		_rebuild_launch_rows()
	# When entering the Orbital Ops tab, refresh the unit-picker
	# OptionButtons against the current pool — adding a unit on the
	# Hangar tab needs to show up as a pickable option immediately.
	if new_index == orbital_index:
		_rebuild_launch_rows()
	_previous_tab_index = new_index
	_refresh_stage_brief()


# ---------------------------------------------------------------- Hangar

# Three-column layout:
#   * Unit pool list (left) — every unit the operator has built, plus a
#     "+ Build Unit" button.
#   * Unit editor (centre) — chassis dropdown + one row per slot. Empty
#     when no unit is selected.
#   * Notes (right) — reading material so the operator knows what each
#     part does before clicking through the dropdowns.
func _build_hangar_tab() -> Control:
	var hbox := _padded_hbox()
	var pad: Control = hbox.get_parent() as Control

	# Left: unit pool
	var left := _section("Unit Pool", HANGAR_LEFT_WIDTH)
	hbox.add_child(left[0])

	_unit_list = ItemList.new()
	_unit_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_unit_list.allow_reselect = true
	_unit_list.add_theme_color_override("font_color", COLOR_FG)
	_unit_list.add_theme_color_override("font_selected_color", COLOR_ACCENT)
	_unit_list.item_selected.connect(_on_unit_selected)
	left[1].add_child(_unit_list)

	var pool_actions := HBoxContainer.new()
	pool_actions.add_theme_constant_override("separation", 8)
	left[1].add_child(pool_actions)

	var build_btn := Button.new()
	build_btn.text = "+ Build Unit"
	build_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	build_btn.pressed.connect(_on_build_unit_pressed)
	pool_actions.add_child(build_btn)

	var remove_btn := Button.new()
	remove_btn.text = "Remove"
	remove_btn.pressed.connect(_on_remove_unit_pressed)
	pool_actions.add_child(remove_btn)

	# Centre: unit editor
	var center := _section("Unit Designer", 0)
	hbox.add_child(center[0])

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center[1].add_child(scroll)

	_unit_editor = VBoxContainer.new()
	_unit_editor.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_unit_editor.add_theme_constant_override("separation", 10)
	scroll.add_child(_unit_editor)

	# Right: live unit summary. Rebuilt on every selection / part /
	# chassis / name change so the operator can see in real time how a
	# part swap shifts the unit's stats.
	var right := _section("Unit Summary", SIDE_PANEL_WIDTH)
	hbox.add_child(right[0])
	_hangar_summary = VBoxContainer.new()
	_hangar_summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hangar_summary.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_hangar_summary.add_theme_constant_override("separation", 4)
	right[1].add_child(_hangar_summary)

	_rebuild_unit_list()
	if _selected_unit_id == "" and not PlayerLoadout.unit_pool.is_empty():
		_selected_unit_id = PlayerLoadout.unit_pool[0].id
		_unit_list.select(0)
	_rebuild_unit_editor()
	_rebuild_unit_summary()

	return pad


func _rebuild_unit_list() -> void:
	if _unit_list == null:
		return
	_unit_list.clear()
	var selected_idx := -1
	for i in range(PlayerLoadout.unit_pool.size()):
		var unit: UnitConfig = PlayerLoadout.unit_pool[i]
		# Pool list shows only the user-provided name. The chassis +
		# parts breakdown is one click away in the unit editor and is
		# duplicated in the right-column summary, so cluttering the
		# row with the same string just makes the list noisier.
		_unit_list.add_item(unit.name)
		if unit.id == _selected_unit_id:
			selected_idx = i
	if selected_idx >= 0:
		_unit_list.select(selected_idx)


func _on_unit_selected(idx: int) -> void:
	if idx < 0 or idx >= PlayerLoadout.unit_pool.size():
		return
	_selected_unit_id = PlayerLoadout.unit_pool[idx].id
	_rebuild_unit_editor()
	_rebuild_unit_summary()


func _on_build_unit_pressed() -> void:
	var unit := PlayerLoadout.add_unit()
	_selected_unit_id = unit.id
	_rebuild_unit_list()
	_rebuild_unit_editor()
	_rebuild_unit_summary()


func _on_remove_unit_pressed() -> void:
	if _selected_unit_id == "":
		return
	PlayerLoadout.remove_unit(_selected_unit_id)
	_selected_unit_id = ""
	if not PlayerLoadout.unit_pool.is_empty():
		_selected_unit_id = PlayerLoadout.unit_pool[0].id
	_rebuild_unit_list()
	_rebuild_unit_editor()
	_rebuild_unit_summary()
	# Removing a unit may have left launches unassigned; the launch
	# rows reflect that on the next tab visit, but proactively rebuild
	# in case the operator switches tabs without us hearing about it.
	_rebuild_launch_rows()


func _rebuild_unit_editor() -> void:
	if _unit_editor == null:
		return
	for child in _unit_editor.get_children():
		_unit_editor.remove_child(child)
		child.queue_free()
	if _selected_unit_id == "":
		var empty := Label.new()
		empty.text = "Select a unit on the left, or click + Build Unit."
		empty.add_theme_color_override("font_color", COLOR_FG_DIM)
		_unit_editor.add_child(empty)
		return
	var unit := PlayerLoadout.unit_for_id(_selected_unit_id)
	if unit == null:
		return

	# Header row: editable name + chassis picker. The name is the
	# string the Orbital Ops tab shows in its launch dropdown, so the
	# edit propagates: text_changed updates unit.name and refreshes the
	# pool list label so the row visually agrees with the editor before
	# the operator switches tabs.
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	_unit_editor.add_child(header)

	var name_caption := Label.new()
	name_caption.text = "Name"
	name_caption.add_theme_color_override("font_color", COLOR_FG_DIM)
	name_caption.add_theme_font_size_override("font_size", 11)
	header.add_child(name_caption)

	var name_field := LineEdit.new()
	name_field.text = unit.name
	name_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_field.placeholder_text = "Unit name"
	name_field.add_theme_color_override("font_color", COLOR_ACCENT)
	name_field.add_theme_font_size_override("font_size", 16)
	name_field.text_changed.connect(_on_unit_name_changed)
	header.add_child(name_field)

	var chassis_label := Label.new()
	chassis_label.text = "Chassis"
	chassis_label.add_theme_color_override("font_color", COLOR_FG_DIM)
	chassis_label.add_theme_font_size_override("font_size", 11)
	header.add_child(chassis_label)

	var chassis_picker := OptionButton.new()
	var chassis_catalog := UnitChassis.catalog()
	for i in range(chassis_catalog.size()):
		var c: UnitChassis = chassis_catalog[i]
		chassis_picker.add_item("%s (%dW · %dR · %dE · %dC)" % [
			c.label, c.weapon_slots, c.radiator_slots,
			c.energy_storage_slots, c.reactor_slots,
		])
		chassis_picker.set_item_metadata(i, c.id)
		if c.id == unit.chassis_id:
			chassis_picker.select(i)
	chassis_picker.item_selected.connect(
		func(idx: int) -> void:
			_on_chassis_selected(String(chassis_picker.get_item_metadata(idx)))
	)
	header.add_child(chassis_picker)

	_unit_editor.add_child(_hr())

	# One section per kind, listing each slot's part dropdown.
	for kind in KINDS:
		_unit_editor.add_child(_build_kind_section(unit, kind))


# Rebuild the right-column stat readout for the currently-selected
# unit. Cheap — pulls a Dictionary from UnitConfig.summary_stats() and
# emits one labelled row per stat. Called after any change that could
# move the numbers (chassis swap, part swap, selection change). Laser
# and railgun rows are suppressed when the unit carries none of that
# weapon class, so a railgun-only ship doesn't show "Laser DPS: 0".
func _rebuild_unit_summary() -> void:
	if _hangar_summary == null:
		return
	for child in _hangar_summary.get_children():
		_hangar_summary.remove_child(child)
		child.queue_free()
	if _selected_unit_id == "":
		var empty := Label.new()
		empty.text = "Select a unit to see its stats."
		empty.add_theme_color_override("font_color", COLOR_FG_DIM)
		empty.add_theme_font_size_override("font_size", 12)
		_hangar_summary.add_child(empty)
		return
	var unit := PlayerLoadout.unit_for_id(_selected_unit_id)
	if unit == null:
		return
	var stats := unit.summary_stats()

	_hangar_summary.add_child(_summary_row("HP", "%.0f" % float(stats["hp"])))
	_hangar_summary.add_child(_summary_row(
		"Mass", "%.0f kg" % float(stats["mass_kg"])
	))

	if int(stats["laser_count"]) > 0:
		_hangar_summary.add_child(_summary_section("LASERS"))
		_hangar_summary.add_child(_summary_row(
			"Max DPS", "%.1f /s" % float(stats["laser_dps_total"])
		))
		_hangar_summary.add_child(_summary_row(
			"Max range", "%.0f km" % float(stats["laser_max_range"])
		))
		_hangar_summary.add_child(_summary_row(
			"Cooldown",
			_format_cooldown(float(stats["laser_cooldown_sec"])),
		))

	if int(stats["railgun_count"]) > 0:
		_hangar_summary.add_child(_summary_section("RAILGUNS"))
		_hangar_summary.add_child(_summary_row(
			"Damage / shot", "%.1f" % float(stats["railgun_damage_total"])
		))
		_hangar_summary.add_child(_summary_row(
			"Cooldown",
			_format_cooldown(float(stats["railgun_cooldown_sec"])),
		))

	_hangar_summary.add_child(_summary_section("ENERGY"))
	_hangar_summary.add_child(_summary_row(
		"Storage", "%.2f" % float(stats["energy_storage"])
	))
	_hangar_summary.add_child(_summary_row(
		"Production", "%.5f /s" % float(stats["energy_production"])
	))


# Single key/value row in the summary panel. Right-aligned value so the
# numeric column reads as a table.
func _summary_row(key: String, value: String) -> Control:
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


# Format a cooldown duration in sim-seconds. INF surfaces the
# "no radiator" case as a clear "n/a" so the operator sees that the
# weapon could fire once and never recover; finite values render as
# whole sim-seconds (the granularity that matches the integer wall
# numbers radiators produce).
func _format_cooldown(seconds: float) -> String:
	if not is_finite(seconds):
		return "n/a (no radiator)"
	return "%.0f s" % seconds


func _summary_section(title: String) -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	col.add_child(_hr())
	var lbl := Label.new()
	lbl.text = title
	lbl.add_theme_color_override("font_color", COLOR_ACCENT)
	lbl.add_theme_font_size_override("font_size", 11)
	col.add_child(lbl)
	return col


func _build_kind_section(unit: UnitConfig, kind: int) -> Control:
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", _flat_stylebox(COLOR_PANEL_DIM))
	var box_pad := MarginContainer.new()
	box_pad.add_theme_constant_override("margin_left", 10)
	box_pad.add_theme_constant_override("margin_right", 10)
	box_pad.add_theme_constant_override("margin_top", 8)
	box_pad.add_theme_constant_override("margin_bottom", 8)
	box.add_child(box_pad)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	box_pad.add_child(col)

	var heading := Label.new()
	heading.text = "%s · %d slot(s)" % [
		UnitPart.KIND_LABELS[kind],
		UnitChassis.slot_count_for_kind(unit.chassis_id, kind),
	]
	heading.add_theme_color_override("font_color", COLOR_FG_DIM)
	heading.add_theme_font_size_override("font_size", 11)
	col.add_child(heading)

	var part_ids := unit.part_ids_for_kind(kind)
	var available := UnitPart.parts_of_kind(kind)
	if part_ids.is_empty():
		var none := Label.new()
		none.text = "(no slots on this chassis)"
		none.add_theme_color_override("font_color", COLOR_FG_FAINT)
		none.add_theme_font_size_override("font_size", 11)
		col.add_child(none)
		return box

	for slot_idx in range(part_ids.size()):
		col.add_child(_build_slot_row(unit, kind, slot_idx, available))
	return box


func _build_slot_row(
	unit: UnitConfig,
	kind: int,
	slot_index: int,
	available: Array[UnitPart],
) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var label := Label.new()
	label.text = "Slot %d" % (slot_index + 1)
	label.custom_minimum_size = Vector2(70, 0)
	label.add_theme_color_override("font_color", COLOR_FG_DIM)
	label.add_theme_font_size_override("font_size", 11)
	row.add_child(label)

	var picker := OptionButton.new()
	picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var current_id: String = unit.part_ids_for_kind(kind)[slot_index]
	for i in range(available.size()):
		var p: UnitPart = available[i]
		picker.add_item(p.label)
		picker.set_item_metadata(i, p.id)
		if p.id == current_id:
			picker.select(i)
	picker.item_selected.connect(
		func(idx: int) -> void:
			_on_part_picked(kind, slot_index, picker.get_item_metadata(idx))
	)
	row.add_child(picker)

	return row


func _on_chassis_selected(chassis_id: String) -> void:
	if _selected_unit_id == "":
		return
	var unit := PlayerLoadout.unit_for_id(_selected_unit_id)
	if unit == null:
		return
	unit.set_chassis(chassis_id)
	_rebuild_unit_list()
	_rebuild_unit_editor()
	_rebuild_unit_summary()


func _on_part_picked(kind: int, slot_index: int, part_id: Variant) -> void:
	if _selected_unit_id == "":
		return
	var unit := PlayerLoadout.unit_for_id(_selected_unit_id)
	if unit == null:
		return
	unit.set_part_id(kind, slot_index, String(part_id))
	_rebuild_unit_list()
	_rebuild_unit_summary()


# Live name edit. Updates the unit and the pool-list label without
# rebuilding the editor (which would yank focus mid-edit). The launch
# dropdowns on the Orbital Ops tab pull from `unit.name` directly, so
# they pick up the new label on the next tab visit / row rebuild.
func _on_unit_name_changed(new_text: String) -> void:
	if _selected_unit_id == "":
		return
	var unit := PlayerLoadout.unit_for_id(_selected_unit_id)
	if unit == null:
		return
	unit.name = new_text
	if _unit_list != null:
		for i in range(PlayerLoadout.unit_pool.size()):
			if PlayerLoadout.unit_pool[i].id == _selected_unit_id:
				_unit_list.set_item_text(i, unit.name)
				break


# ---------------------------------------------------------------- Orbital Ops

func _build_orbital_ops_tab() -> Control:
	var hbox := _padded_hbox()
	var pad: Control = hbox.get_parent() as Control

	var left := _section("Scheduled Launches", 540)
	hbox.add_child(left[0])

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left[1].add_child(scroll)

	_launches_root = VBoxContainer.new()
	_launches_root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_launches_root.add_theme_constant_override("separation", 10)
	scroll.add_child(_launches_root)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	left[1].add_child(actions)

	var add_btn := Button.new()
	add_btn.text = "+ Add Launch"
	add_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_btn.pressed.connect(_on_add_launch_pressed)
	actions.add_child(add_btn)

	# Centre: 2D top-down preview that redraws when sliders change.
	var center := _section("Equatorial Preview", 0)
	hbox.add_child(center[0])
	_orbit_preview = OrbitPreview.new()
	_orbit_preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_orbit_preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	center[1].add_child(_orbit_preview)

	_rebuild_launch_rows()
	return pad


func _rebuild_launch_rows() -> void:
	if _launches_root == null:
		return
	for child in _launches_root.get_children():
		_launches_root.remove_child(child)
		child.queue_free()
	for i in range(PlayerLoadout.launches.size()):
		_launches_root.add_child(_build_launch_row(i))
	if _orbit_preview != null:
		_orbit_preview.refresh()


func _on_add_launch_pressed() -> void:
	PlayerLoadout.add_launch()
	_rebuild_launch_rows()
	_refresh_stage_brief()


func _on_remove_launch_pressed(index: int) -> void:
	PlayerLoadout.remove_launch(index)
	_rebuild_launch_rows()
	_refresh_stage_brief()


func _build_launch_row(index: int) -> Control:
	var launch: Launch = PlayerLoadout.launches[index]

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

	# Header: launch name, unit picker, status chip, remove button.
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	col.add_child(head)

	var name_label := Label.new()
	name_label.text = launch.name
	name_label.add_theme_color_override("font_color", COLOR_ACCENT)
	name_label.add_theme_font_size_override("font_size", 14)
	name_label.custom_minimum_size = Vector2(70, 0)
	head.add_child(name_label)

	var unit_label := Label.new()
	unit_label.text = "Unit"
	unit_label.add_theme_color_override("font_color", COLOR_FG_DIM)
	unit_label.add_theme_font_size_override("font_size", 11)
	head.add_child(unit_label)

	var picker := OptionButton.new()
	picker.add_item("(unassigned)")
	picker.set_item_metadata(0, "")
	var selected_picker_idx := 0
	for i in range(PlayerLoadout.unit_pool.size()):
		var unit: UnitConfig = PlayerLoadout.unit_pool[i]
		# Just the operator-set name — the parts breakdown lives in
		# the Hangar's Unit Summary panel and would crowd this picker.
		picker.add_item(unit.name)
		picker.set_item_metadata(i + 1, unit.id)
		if unit.id == launch.unit_id:
			selected_picker_idx = i + 1
	picker.select(selected_picker_idx)
	picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	picker.item_selected.connect(
		func(idx: int) -> void:
			_on_launch_unit_picked(index, picker.get_item_metadata(idx))
	)
	head.add_child(picker)

	var status_chip := Label.new()
	status_chip.add_theme_font_size_override("font_size", 11)
	if launch.has_unit():
		status_chip.text = "ASSIGNED"
		status_chip.add_theme_color_override("font_color", COLOR_OK)
	else:
		status_chip.text = "UNASSIGNED"
		status_chip.add_theme_color_override("font_color", COLOR_WARN)
	head.add_child(status_chip)

	var remove_btn := Button.new()
	remove_btn.text = "✕"
	remove_btn.tooltip_text = "Remove launch"
	remove_btn.pressed.connect(_on_remove_launch_pressed.bind(index))
	head.add_child(remove_btn)

	col.add_child(_orbit_slider_row(
		"Altitude (km)", launch.altitude_km,
		Launch.ALT_MIN_KM, Launch.ALT_MAX_KM, 10.0,
		index, "altitude_km",
	))
	col.add_child(_orbit_slider_row(
		"Inclination (°)", launch.inclination_deg,
		Launch.INC_MIN_DEG, Launch.INC_MAX_DEG, 1.0,
		index, "inclination_deg",
	))
	col.add_child(_orbit_slider_row(
		"RAAN (°)", launch.raan_deg,
		Launch.RAAN_MIN_DEG, Launch.RAAN_MAX_DEG, 1.0,
		index, "raan_deg",
	))
	col.add_child(_orbit_slider_row(
		"True Anomaly (°)", launch.true_anomaly_deg,
		Launch.NU_MIN_DEG, Launch.NU_MAX_DEG, 1.0,
		index, "true_anomaly_deg",
	))
	return row


func _on_launch_unit_picked(launch_index: int, unit_id: Variant) -> void:
	if launch_index < 0 or launch_index >= PlayerLoadout.launches.size():
		return
	PlayerLoadout.launches[launch_index].unit_id = String(unit_id)
	# Status chip + LAUNCH gate hinge on whether any launch is assigned;
	# rebuild rows to refresh the chip and the campaign brief follows.
	_rebuild_launch_rows()
	_refresh_stage_brief()


# Build a [label, slider, value] row. The slider drives the named
# Launch field directly; the linked Label updates as the operator
# drags so the numeric readout stays in sync without polling.
func _orbit_slider_row(
	label: String,
	value: float,
	min_v: float,
	max_v: float,
	step: float,
	launch_index: int,
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
			_on_orbit_field_changed(launch_index, field, new_value, readout)
	)
	return row


func _on_orbit_field_changed(
	launch_index: int, field: String, new_value: float, readout: Label
) -> void:
	if launch_index < 0 or launch_index >= PlayerLoadout.launches.size():
		return
	var launch: Launch = PlayerLoadout.launches[launch_index]
	launch.set(field, new_value)
	readout.text = "%.0f" % new_value
	if _orbit_preview != null:
		_orbit_preview.refresh()


# ---------------------------------------------------------------- Surface Ops

# Tab layout: equirectangular world map up top (wrapped in an
# AspectRatioContainer so it grows to fill the tab width while
# preserving its 2:1 lon:lat aspect), placed-installations list below.
# The placement map's `placed` signal is wired straight to
# PlayerLoadout.add_surface_unit so the menu state stays the single
# source of truth — clicking the map mutates PlayerLoadout.surface_units,
# which is what the spawner reads on Launch.
func _build_surface_ops_tab() -> Control:
	var pad := MarginContainer.new()
	pad.anchor_right = 1.0
	pad.anchor_bottom = 1.0
	pad.add_theme_constant_override("margin_left", 12)
	pad.add_theme_constant_override("margin_right", 12)
	pad.add_theme_constant_override("margin_top", 12)
	pad.add_theme_constant_override("margin_bottom", 12)

	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 12)
	pad.add_child(col)

	# Top: click-to-place equirectangular world map wrapped in an
	# AspectRatioContainer so it preserves a 2:1 lon:lat ratio while
	# growing into the tab width. The section panel and aspect
	# container both keep size_flags_vertical=EXPAND_FILL so they fill
	# whatever vertical the layout allocates; the AspectRatioContainer
	# in STRETCH_FIT mode centers the 2:1 child inside that rect with
	# letterboxing if the available area's aspect doesn't match. The
	# placement map's custom_minimum_size sets a floor so the layout
	# can't collapse the click target to zero height when nothing else
	# in the section drives a minimum.
	var map_section := _section("Surface Map · Click to Place", 0)
	col.add_child(map_section[0])
	map_section[0].size_flags_stretch_ratio = 3.0
	var aspect := AspectRatioContainer.new()
	aspect.ratio = 2.0
	aspect.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	aspect.size_flags_vertical = Control.SIZE_EXPAND_FILL
	aspect.stretch_mode = AspectRatioContainer.STRETCH_FIT
	map_section[1].add_child(aspect)
	_surface_placement = SurfacePlacementMap.new()
	_surface_placement.custom_minimum_size = Vector2(640.0, 320.0)
	_surface_placement.placed.connect(_on_surface_placed)
	aspect.add_child(_surface_placement)

	# Bottom: placed-installations list. Fills whatever vertical space
	# the map didn't claim — the map's higher stretch_ratio above keeps
	# this section from dominating when there's plenty of room.
	var list_section := _section("Placed Installations", 0)
	col.add_child(list_section[0])
	list_section[0].size_flags_stretch_ratio = 1.0

	_surface_count_label = Label.new()
	_surface_count_label.add_theme_color_override("font_color", COLOR_FG_DIM)
	_surface_count_label.add_theme_font_size_override("font_size", 11)
	list_section[1].add_child(_surface_count_label)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_section[1].add_child(scroll)

	_surface_root = VBoxContainer.new()
	_surface_root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_surface_root.add_theme_constant_override("separation", 6)
	scroll.add_child(_surface_root)

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
