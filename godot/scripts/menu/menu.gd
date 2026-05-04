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
const Satellite = preload("res://scripts/satellite.gd")
const ResearchGraph = preload("res://scripts/menu/research_graph.gd")
const ReconEditor = preload("res://scripts/menu/recon_editor.gd")

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
	UnitPart.KIND_THRUSTER,
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
# Budget panel widgets — built once in _build_orbital_ops_tab, mutated
# by _refresh_launch_budget after every slider / picker change so the
# operator sees the running total update live.
var _budget_label: Label
var _budget_bar_fill: ColorRect
# Per-launch readouts that update live as their sliders / picker
# change, indexed by the launch's slot in PlayerLoadout.launches.
# Repopulated on every _rebuild_launch_rows so they line up with the
# rebuilt PanelContainer children. The slider callbacks index into
# these arrays to refresh just the affected row's labels rather than
# rebuilding the whole list (which would yank slider focus mid-drag).
var _launch_cost_labels: Array[Label] = []
var _launch_apogee_labels: Array[Label] = []
var _previous_tab_index: int = 0
var _add_launch_btn: Button
var _launch_capacity_label: Label

# Surface Ops state
var _surface_root: VBoxContainer
var _surface_placement: SurfacePlacementMap
var _surface_count_label: Label

# Research state
var _research_points_label: Label
var _research_graph: ResearchGraph
var _research_detail_title: Label
var _research_detail_category: Label
var _research_detail_status: Label
var _research_detail_cost: Label
var _research_detail_stats: Label
var _research_detail_prereq: Label
var _research_detail_flavor: Label
var _research_detail_button: Button
var _research_selected_id: String = ""


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

	var recon := _build_recon_tab()
	recon.name = "Recon"
	_tabs.add_child(recon)

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
		# Distinguish "no launches assigned" from "over budget" so the
		# operator knows which knob to turn. Budget gate beats the
		# assignment gate on the message — if launches are assigned and
		# the only failing condition is budget, the over-budget hint is
		# the actionable one.
		var over_budget: bool = (
			PlayerLoadout.has_assigned_launches()
			and PlayerLoadout.total_launch_propellant_used_kg()
				> PlayerLoadout.LAUNCH_PROPELLANT_BUDGET_KG
		)
		if over_budget:
			_launch_button.text = "LAUNCH (over propellant budget)"
		else:
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
		# Energy chain: pool draw → wall-plug efficiency → radiated
		# beam → target coupling → absorbed damage. Showing each stage
		# explicitly so the operator can trace why a 100 MW emitter
		# only deals ~8 HP/s at zero range (30% bus → beam, 40% beam →
		# damage, 5 MJ/HP).
		_hangar_summary.add_child(_summary_row(
			"Energy / sec",
			"%s /s" % _format_joules(float(stats["laser_pool_draw_w"])),
		))
		_hangar_summary.add_child(_summary_row(
			"Radiated power",
			_format_watts(float(stats["laser_radiated_power_w"])),
		))
		_hangar_summary.add_child(_summary_row(
			"Wall-plug efficiency",
			"%.0f%%" % (float(stats["laser_wallplug_efficiency"]) * 100.0),
		))
		_hangar_summary.add_child(_summary_row(
			"Energy coupling on target",
			"%.0f%%" % (float(stats["laser_target_coupling"]) * 100.0),
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
		# Slug + magazine: physical inputs the player can reason about.
		# Velocity prints in km/s for readability (10 km/s reads cleaner
		# than 10000 m/s); slug KE and pool draw use the joule formatter
		# so MJ/GJ prefixes line up with the ENERGY section above.
		_hangar_summary.add_child(_summary_row(
			"Slug mass",
			"%.0f kg" % float(stats["railgun_slug_mass_kg"]),
		))
		_hangar_summary.add_child(_summary_row(
			"Muzzle velocity",
			"%.1f km/s" % (
				float(stats["railgun_muzzle_velocity_m_s"]) * 1.0e-3
			),
		))
		_hangar_summary.add_child(_summary_row(
			"Slug KE",
			_format_joules(float(stats["railgun_slug_ke_j"])),
		))
		_hangar_summary.add_child(_summary_row(
			"Energy / shot",
			_format_joules(float(stats["railgun_energy_per_shot_j"])),
		))
		_hangar_summary.add_child(_summary_row(
			"Magazine",
			"%d rounds" % int(stats["railgun_magazine_size"]),
		))
		# Recoil at full wet mass — the floor; the operator should know
		# their first shot of an engagement is the gentlest, and that
		# every subsequent shot kicks harder as the magazine empties.
		_hangar_summary.add_child(_summary_row(
			"Recoil / shot (full mag)",
			"%.1f m/s" % float(stats["railgun_recoil_dv_ms"]),
		))
		# Energy coupling = fraction of slug KE absorbed as damage. The
		# rest fragments / passes through / spalls off the back face.
		# Momentum transfer is full Newton's third regardless of this
		# number; the target catches the slug's full momentum vector
		# whether 10% or 100% of the KE deposits as HP damage.
		_hangar_summary.add_child(_summary_row(
			"Energy coupling on target",
			"%.0f%%" % (float(stats["railgun_target_coupling"]) * 100.0),
		))

	_hangar_summary.add_child(_summary_section("ENERGY"))
	_hangar_summary.add_child(_summary_row(
		"Storage", _format_joules(float(stats["energy_storage"]))
	))
	_hangar_summary.add_child(_summary_row(
		"Production", _format_watts(float(stats["energy_production"]))
	))

	# Propulsion section. Skipped when the unit carries no thruster
	# (capacity 0 ⇒ nothing to render). Δv capacity is the headline:
	# the m/s pool the unit can spend on in-game maneuvers, computed
	# from Tsiolkovsky at the unit's wet mass and Isp. Thrust is the
	# instantaneous force the unit can apply (reserved for future
	# TWR-gated abilities); Isp and propellant mass are the inputs
	# that determine the Δv pool.
	if float(stats["propellant_capacity_kg"]) > 0.0:
		_hangar_summary.add_child(_summary_section("PROPULSION"))
		_hangar_summary.add_child(_summary_row(
			"Δv capacity",
			"%d m/s" % int(round(float(stats["delta_v_capacity_ms"]))),
		))
		_hangar_summary.add_child(_summary_row(
			"Thrust", "%.1f kN" % (float(stats["thrust_n"]) / 1000.0)
		))
		_hangar_summary.add_child(_summary_row(
			"Isp", "%.0f s" % float(stats["isp_s"])
		))
		_hangar_summary.add_child(_summary_row(
			"Propellant", "%.0f kg" % float(stats["propellant_capacity_kg"])
		))
		_hangar_summary.add_child(_summary_row(
			"Dry mass", "%.0f kg" % float(stats["dry_mass_kg"])
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


# Joules → human-readable energy. Uses GJ above 1 GJ (10^9 J), MJ
# above 1 MJ, kJ above 1 kJ, otherwise raw J. Defaults to one
# decimal place — capacities up to "9.5 GJ" read cleanly without
# trailing zeros from a fixed format.
func _format_joules(joules: float) -> String:
	if joules >= 1.0e9:
		return "%.1f GJ" % (joules * 1.0e-9)
	if joules >= 1.0e6:
		return "%.1f MJ" % (joules * 1.0e-6)
	if joules >= 1.0e3:
		return "%.1f kJ" % (joules * 1.0e-3)
	return "%.0f J" % joules


# Watts → human-readable power, same prefix ladder as _format_joules.
# Reactor outputs are at the GW / MW end of the scale; the kW / W
# branches are belt-and-braces for tiny / zero-reactor builds.
func _format_watts(watts: float) -> String:
	if watts >= 1.0e9:
		return "%.2f GW" % (watts * 1.0e-9)
	if watts >= 1.0e6:
		return "%.1f MW" % (watts * 1.0e-6)
	if watts >= 1.0e3:
		return "%.1f kW" % (watts * 1.0e-3)
	return "%.0f W" % watts


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

	# Locked tiers are still listed in the dropdown so the operator can
	# see what's coming next, but their entries are disabled and tagged
	# "(locked)" — clearer than hiding them entirely. The currently
	# selected part always remains pickable even if research has since
	# been reset, so an existing unit can never trap the editor in an
	# unselectable state.
	var picker := OptionButton.new()
	picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var current_id: String = unit.part_ids_for_kind(kind)[slot_index]
	for i in range(available.size()):
		var p: UnitPart = available[i]
		var unlocked := Research.is_part_unlocked(p.id) or p.id == current_id
		var item_label := p.label if unlocked else "%s (locked)" % p.label
		picker.add_item(item_label)
		picker.set_item_metadata(i, p.id)
		if not unlocked:
			picker.set_item_disabled(i, true)
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

	_add_launch_btn = Button.new()
	_add_launch_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_add_launch_btn.pressed.connect(_on_add_launch_pressed)
	actions.add_child(_add_launch_btn)

	# Capacity readout sits next to the add button so the operator
	# always sees the current cap. Updated alongside the rows in
	# _rebuild_launch_rows().
	_launch_capacity_label = Label.new()
	_launch_capacity_label.add_theme_color_override("font_color", COLOR_FG_DIM)
	_launch_capacity_label.add_theme_font_size_override("font_size", 11)
	actions.add_child(_launch_capacity_label)

	# Budget panel sits below the actions row so the running total of
	# propellant draw across every assigned launch is always visible
	# while the operator drags sliders. Pre-built once; the bar fill
	# and the numeric label are mutated in _refresh_launch_budget()
	# after each slider / picker / add / remove event.
	left[1].add_child(_build_launch_budget_panel())

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
	# Per-row label arrays are reset to match the new PanelContainer
	# children one-for-one as _build_launch_row appends to both.
	_launch_cost_labels.clear()
	_launch_apogee_labels.clear()
	for i in range(PlayerLoadout.launches.size()):
		_launches_root.add_child(_build_launch_row(i))
	if _orbit_preview != null:
		_orbit_preview.refresh()
	_refresh_launch_budget()
	_refresh_launch_capacity_chrome()


# Update the "+ Add Launch" button + the X / Y capacity counter.
# Driven by Research's launch_capacity gate — independent from the
# per-launch propellant budget refresh below.
func _refresh_launch_capacity_chrome() -> void:
	if _add_launch_btn == null or _launch_capacity_label == null:
		return
	var cap := Research.launch_capacity()
	var used := PlayerLoadout.launches.size()
	_launch_capacity_label.text = "%d / %d" % [used, cap]
	var can_add := PlayerLoadout.can_add_launch()
	_add_launch_btn.disabled = not can_add
	if can_add:
		_add_launch_btn.text = "+ Add Launch"
	else:
		_add_launch_btn.text = "Cap reached — research more"


# Refresh just the per-launch cost / apogee labels — invoked from the
# slider callbacks so dragging an altitude / inclination / eccentricity
# slider doesn't tear down the row (which would steal focus from the
# slider the operator is currently holding).
func _refresh_launch_row_readouts(launch_index: int) -> void:
	if launch_index < 0 or launch_index >= PlayerLoadout.launches.size():
		return
	var launch: Launch = PlayerLoadout.launches[launch_index]
	if launch_index < _launch_cost_labels.size():
		var cost_label := _launch_cost_labels[launch_index]
		if cost_label != null:
			cost_label.text = _format_launch_cost(launch)
	if launch_index < _launch_apogee_labels.size():
		var apo_label := _launch_apogee_labels[launch_index]
		if apo_label != null:
			apo_label.text = "Apogee  %d km" % int(round(launch.apogee_altitude_km()))


# Build the launch's cost summary line: "Δv 850 m/s · 145 kg". Costs
# are zero for an unassigned launch (the unit's wet mass is unknown
# until a unit is picked); we still surface the Δv so the operator
# can see the orbit's setup cost before assigning. Returns the
# pre-formatted string so both the row builder and the live updater
# share one source of truth for the layout.
func _format_launch_cost(launch: Launch) -> String:
	var dv_ms: float = launch.setup_dv_ms()
	var prop_kg: float = 0.0
	if launch.has_unit():
		var unit: UnitConfig = PlayerLoadout.unit_for_id(launch.unit_id)
		if unit != null:
			prop_kg = launch.propellant_cost_kg(unit.wet_mass_kg())
	if launch.has_unit():
		return "Δv %d m/s  ·  %d kg" % [
			int(round(dv_ms)), int(round(prop_kg)),
		]
	return "Δv %d m/s  ·  — kg" % int(round(dv_ms))


# Build the propellant-budget panel that lives below the "+ Add Launch"
# button: a labelled progress bar that drains as the cumulative draw
# climbs and turns red the moment the configured launches exceed the
# pre-game capacity. The widgets are stashed on the menu so
# _refresh_launch_budget can mutate them in place — slider drags would
# otherwise rebuild the whole panel and yank focus.
func _build_launch_budget_panel() -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _flat_stylebox(COLOR_PANEL_DIM))

	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 12)
	pad.add_theme_constant_override("margin_right", 12)
	pad.add_theme_constant_override("margin_top", 8)
	pad.add_theme_constant_override("margin_bottom", 10)
	panel.add_child(pad)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	pad.add_child(col)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	col.add_child(header)

	var title := Label.new()
	title.text = "Launch Budget"
	title.add_theme_color_override("font_color", COLOR_ACCENT)
	title.add_theme_font_size_override("font_size", 12)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)

	_budget_label = Label.new()
	_budget_label.add_theme_font_size_override("font_size", 11)
	_budget_label.add_theme_color_override("font_color", COLOR_FG)
	header.add_child(_budget_label)

	# Bar: fixed 8 px tall strip with a dark background and a fill rect
	# whose anchor_right tracks the used/total ratio. ColorRect-on-
	# ColorRect is cheaper than a StyleBox for this — no per-resize
	# allocations during slider drags.
	var bar_bg := ColorRect.new()
	bar_bg.color = COLOR_PANEL
	bar_bg.custom_minimum_size = Vector2(0, 8)
	bar_bg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(bar_bg)

	_budget_bar_fill = ColorRect.new()
	_budget_bar_fill.anchor_left = 0.0
	_budget_bar_fill.anchor_right = 0.0
	_budget_bar_fill.anchor_top = 0.0
	_budget_bar_fill.anchor_bottom = 1.0
	_budget_bar_fill.color = COLOR_OK
	bar_bg.add_child(_budget_bar_fill)

	return panel


# Refresh the budget panel from PlayerLoadout's running totals. Called
# after every slider / picker / add / remove that affects a launch's
# cost. Cheap (one fold over assigned launches) and the panel widgets
# are reused so this never reallocates.
func _refresh_launch_budget() -> void:
	if _budget_label == null or _budget_bar_fill == null:
		return
	var used: float = PlayerLoadout.total_launch_propellant_used_kg()
	var total: float = PlayerLoadout.LAUNCH_PROPELLANT_BUDGET_KG
	_budget_label.text = "%d / %d kg" % [int(round(used)), int(round(total))]
	# Bar fills proportionally up to 1.0; over-budget pegs the fill at
	# the right edge and flips the bar (and label) red so the operator
	# sees the cause of a disabled LAUNCH button at a glance.
	var frac: float = clampf(used / total, 0.0, 1.0) if total > 0.0 else 0.0
	_budget_bar_fill.anchor_right = frac
	if used > total:
		_budget_bar_fill.color = COLOR_WARN
		_budget_label.add_theme_color_override("font_color", COLOR_WARN)
	else:
		_budget_bar_fill.color = COLOR_OK
		_budget_label.add_theme_color_override("font_color", COLOR_FG)


func _on_add_launch_pressed() -> void:
	# add_launch returns null when the operator's at the research cap;
	# the button gate makes that path unreachable in normal use, but
	# guard anyway in case the cap drops between the button repaint and
	# the click.
	if PlayerLoadout.add_launch() == null:
		_refresh_launch_capacity_chrome()
		return
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

	# Sub-header line with this launch's setup Δv and propellant draw.
	# Stashed in _launch_cost_labels so slider drags can update just
	# this one label rather than rebuilding the row.
	var cost_label := Label.new()
	cost_label.text = _format_launch_cost(launch)
	cost_label.add_theme_color_override("font_color", COLOR_FG_DIM)
	cost_label.add_theme_font_size_override("font_size", 11)
	col.add_child(cost_label)
	_launch_cost_labels.append(cost_label)

	col.add_child(_orbit_slider_row(
		"Perigee (km)", launch.altitude_km,
		Launch.ALT_MIN_KM, Launch.ALT_MAX_KM, 10.0,
		index, "altitude_km", 0,
	))
	# Eccentricity uses a fractional step so the operator can dial in
	# small e values; readout shows two decimals.
	col.add_child(_orbit_slider_row(
		"Eccentricity", launch.eccentricity,
		Launch.ECC_MIN, Launch.ECC_MAX, 0.01,
		index, "eccentricity", 2,
	))
	# Apogee is derived (perigee × (1+e)/(1-e)), not edited directly.
	# The label updates from _refresh_launch_row_readouts on every
	# perigee / eccentricity slider drag.
	var apogee_row := HBoxContainer.new()
	apogee_row.add_theme_constant_override("separation", 8)
	var apogee_lbl := Label.new()
	apogee_lbl.text = "Apogee"
	apogee_lbl.custom_minimum_size = Vector2(140, 0)
	apogee_lbl.add_theme_color_override("font_color", COLOR_FG_DIM)
	apogee_lbl.add_theme_font_size_override("font_size", 11)
	apogee_row.add_child(apogee_lbl)
	var apogee_value := Label.new()
	apogee_value.text = "%d km" % int(round(launch.apogee_altitude_km()))
	apogee_value.add_theme_color_override("font_color", COLOR_FG)
	apogee_value.add_theme_font_size_override("font_size", 11)
	apogee_value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	apogee_row.add_child(apogee_value)
	col.add_child(apogee_row)
	_launch_apogee_labels.append(apogee_value)

	col.add_child(_orbit_slider_row(
		"Inclination (°)", launch.inclination_deg,
		Launch.INC_MIN_DEG, Launch.INC_MAX_DEG, 1.0,
		index, "inclination_deg", 0,
	))
	col.add_child(_orbit_slider_row(
		"RAAN (°)", launch.raan_deg,
		Launch.RAAN_MIN_DEG, Launch.RAAN_MAX_DEG, 1.0,
		index, "raan_deg", 0,
	))
	col.add_child(_orbit_slider_row(
		"True Anomaly (°)", launch.true_anomaly_deg,
		Launch.NU_MIN_DEG, Launch.NU_MAX_DEG, 1.0,
		index, "true_anomaly_deg", 0,
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
	decimals: int,
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
	# Format string is built from `decimals` so eccentricity (2 dp) and
	# the angle / altitude sliders (0 dp) share the same row builder.
	var fmt: String = "%%.%df" % decimals
	readout.text = fmt % value
	readout.custom_minimum_size = Vector2(60, 0)
	readout.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	readout.add_theme_color_override("font_color", COLOR_FG)
	readout.add_theme_font_size_override("font_size", 11)
	row.add_child(readout)

	slider.value_changed.connect(
		func(new_value: float) -> void:
			_on_orbit_field_changed(launch_index, field, new_value, readout, fmt)
	)
	return row


func _on_orbit_field_changed(
	launch_index: int,
	field: String,
	new_value: float,
	readout: Label,
	fmt: String,
) -> void:
	if launch_index < 0 or launch_index >= PlayerLoadout.launches.size():
		return
	var launch: Launch = PlayerLoadout.launches[launch_index]
	launch.set(field, new_value)
	readout.text = fmt % new_value
	if _orbit_preview != null:
		_orbit_preview.refresh()
	# Updating perigee, eccentricity, or inclination changes the
	# launch's setup Δv (and therefore its propellant draw); refresh
	# the per-row readouts and the global budget panel so the operator
	# sees the consequence of the drag in real time. RAAN / true
	# anomaly don't affect cost but the cheap refresh is harmless.
	_refresh_launch_row_readouts(launch_index)
	_refresh_launch_budget()
	# Re-evaluate the LAUNCH gate — going over budget disables it.
	_refresh_stage_brief()


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
	# A click on the map at the research-gated cap is a no-op rather
	# than an error — the count label below already tells the operator
	# why nothing happened ("X / Y stations placed").
	if PlayerLoadout.add_surface_unit(lat_deg, lon_deg) == null:
		_refresh_surface_list()
		return
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
			"%d / %d station(s) placed" % [
				configs.size(), Research.ground_defense_capacity(),
			]
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


# ---------------------------------------------------------------- Recon

# Wraps the shared ReconEditor in a padded margin so the editor's
# sections breathe inside the tab. The editor itself binds to
# PlayerLoadout.recon_settings by default, so opening this tab and
# editing here mutates the same Resource the in-game pause-menu
# settings panel sees.
func _build_recon_tab() -> Control:
	var pad := MarginContainer.new()
	pad.anchor_right = 1.0
	pad.anchor_bottom = 1.0
	pad.add_theme_constant_override("margin_left", 12)
	pad.add_theme_constant_override("margin_right", 12)
	pad.add_theme_constant_override("margin_top", 12)
	pad.add_theme_constant_override("margin_bottom", 12)

	var editor := ReconEditor.new()
	editor.bind_settings(PlayerLoadout.recon_settings)
	editor.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	editor.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pad.add_child(editor)
	return pad


# ---------------------------------------------------------------- Research

# Two-column layout: the graph view (left, scrollable) renders every
# chain as a row of polygon nodes; the detail panel (right) populates
# from whichever node the operator last clicked. The point-pool readout
# spans the top so the cost the unlock button shows always reads
# against the visible budget.
func _build_research_tab() -> Control:
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

	col.add_child(_build_research_header())

	var body := HBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 12)
	col.add_child(body)

	var graph_section := _section("Research Graph", 0)
	body.add_child(graph_section[0])
	var graph_scroll := ScrollContainer.new()
	graph_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	graph_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	graph_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	graph_section[1].add_child(graph_scroll)
	_research_graph = ResearchGraph.new()
	_research_graph.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_research_graph.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_research_graph.node_selected.connect(_on_research_node_selected)
	graph_scroll.add_child(_research_graph)

	var detail_section := _section("Node Brief", SIDE_PANEL_WIDTH)
	body.add_child(detail_section[0])
	_build_research_detail_panel(detail_section[1])

	_refresh_research_header()
	_refresh_research_detail()
	return pad


# Top header strip: research-point pool readout + a one-line hint.
# Stored apart from the body so the layout above can keep the panel
# fixed-height while the graph + detail columns flex.
func _build_research_header() -> Control:
	var header := PanelContainer.new()
	header.add_theme_stylebox_override("panel", _flat_stylebox(COLOR_PANEL_DIM))

	var header_pad := MarginContainer.new()
	header_pad.add_theme_constant_override("margin_left", 12)
	header_pad.add_theme_constant_override("margin_right", 12)
	header_pad.add_theme_constant_override("margin_top", 8)
	header_pad.add_theme_constant_override("margin_bottom", 8)
	header.add_child(header_pad)

	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 16)
	header_pad.add_child(box)

	var caption := Label.new()
	caption.text = "RESEARCH POINTS"
	caption.add_theme_color_override("font_color", COLOR_FG_DIM)
	caption.add_theme_font_size_override("font_size", 11)
	box.add_child(caption)

	_research_points_label = Label.new()
	_research_points_label.add_theme_color_override("font_color", COLOR_ACCENT)
	_research_points_label.add_theme_font_size_override("font_size", 18)
	box.add_child(_research_points_label)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(spacer)

	var hint := Label.new()
	hint.text = "Click a node to inspect. Each chain unlocks left to right."
	hint.add_theme_color_override("font_color", COLOR_FG_DIM)
	hint.add_theme_font_size_override("font_size", 11)
	box.add_child(hint)
	return header


# Compose the right-column detail panel into the supplied parent VBox.
# Stored in member labels so `_refresh_research_detail` can rewrite text
# in place without rebuilding the layout — keeps the operator's eye
# anchored to the same row when they click between adjacent nodes.
func _build_research_detail_panel(parent: VBoxContainer) -> void:
	_research_detail_title = Label.new()
	_research_detail_title.add_theme_color_override("font_color", COLOR_ACCENT)
	_research_detail_title.add_theme_font_size_override("font_size", 18)
	_research_detail_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(_research_detail_title)

	_research_detail_category = Label.new()
	_research_detail_category.add_theme_color_override(
		"font_color", COLOR_FG_DIM,
	)
	_research_detail_category.add_theme_font_size_override("font_size", 11)
	parent.add_child(_research_detail_category)

	parent.add_child(_hr())

	_research_detail_status = Label.new()
	_research_detail_status.add_theme_font_size_override("font_size", 12)
	parent.add_child(_research_detail_status)

	_research_detail_cost = Label.new()
	_research_detail_cost.add_theme_color_override("font_color", COLOR_FG)
	_research_detail_cost.add_theme_font_size_override("font_size", 12)
	parent.add_child(_research_detail_cost)

	_research_detail_stats = Label.new()
	_research_detail_stats.add_theme_color_override("font_color", COLOR_FG)
	_research_detail_stats.add_theme_font_size_override("font_size", 12)
	_research_detail_stats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(_research_detail_stats)

	_research_detail_prereq = Label.new()
	_research_detail_prereq.add_theme_color_override("font_color", COLOR_WARN)
	_research_detail_prereq.add_theme_font_size_override("font_size", 11)
	_research_detail_prereq.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(_research_detail_prereq)

	parent.add_child(_hr())

	_research_detail_flavor = Label.new()
	_research_detail_flavor.add_theme_color_override("font_color", COLOR_FG_DIM)
	_research_detail_flavor.add_theme_font_size_override("font_size", 12)
	_research_detail_flavor.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_research_detail_flavor.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(_research_detail_flavor)

	_research_detail_button = Button.new()
	_research_detail_button.custom_minimum_size = Vector2(0, 36)
	_research_detail_button.add_theme_font_size_override("font_size", 13)
	_research_detail_button.pressed.connect(_on_research_unlock_pressed)
	parent.add_child(_research_detail_button)


func _refresh_research_header() -> void:
	if _research_points_label != null:
		_research_points_label.text = "%d" % Research.research_points


func _on_research_node_selected(node_id: String) -> void:
	_research_selected_id = node_id
	_refresh_research_detail()


# Rewrite every label in the detail panel against the currently
# selected node. Empty selection (or an id that doesn't resolve, e.g.
# after a future catalog edit) collapses to a "click a node" prompt
# with the unlock button hidden.
func _refresh_research_detail() -> void:
	if _research_detail_title == null:
		return
	var data: Dictionary = (
		Research.describe(_research_selected_id)
		if _research_selected_id != "" else {}
	)
	if data.is_empty():
		_research_detail_title.text = "(no node selected)"
		_research_detail_category.text = ""
		_research_detail_status.text = ""
		_research_detail_cost.text = ""
		_research_detail_stats.text = ""
		_research_detail_prereq.text = ""
		_research_detail_flavor.text = "Click a node in the graph to inspect it."
		_research_detail_button.visible = false
		return
	_research_detail_button.visible = true

	_research_detail_title.text = String(data["label"])
	_research_detail_category.text = String(data["category"]).to_upper()

	if bool(data["is_unlocked"]):
		_research_detail_status.text = "STATUS · UNLOCKED"
		_research_detail_status.add_theme_color_override("font_color", COLOR_OK)
	elif String(data["prereq_label"]) != "":
		_research_detail_status.text = "STATUS · LOCKED"
		_research_detail_status.add_theme_color_override(
			"font_color", COLOR_FG_FAINT,
		)
	else:
		_research_detail_status.text = "STATUS · AVAILABLE"
		_research_detail_status.add_theme_color_override(
			"font_color", COLOR_ACCENT,
		)

	var cost: int = int(data["cost"])
	if bool(data["is_unlocked"]):
		_research_detail_cost.text = "Cost · paid"
	elif cost == 0:
		_research_detail_cost.text = "Cost · free (starting unlock)"
	else:
		_research_detail_cost.text = "Cost · %d RP" % cost

	_research_detail_stats.text = String(data["stats"])

	var prereq_label := String(data["prereq_label"])
	if prereq_label == "":
		_research_detail_prereq.text = ""
	else:
		_research_detail_prereq.text = "Requires: %s" % prereq_label

	_research_detail_flavor.text = String(data["flavor"])

	if bool(data["is_unlocked"]):
		_research_detail_button.text = "Unlocked"
		_research_detail_button.disabled = true
	elif bool(data["can_unlock"]):
		_research_detail_button.text = "Unlock for %d RP" % cost
		_research_detail_button.disabled = false
	elif prereq_label != "":
		_research_detail_button.text = "Locked — research %s first" % prereq_label
		_research_detail_button.disabled = true
	else:
		_research_detail_button.text = "Need %d RP" % cost
		_research_detail_button.disabled = true


# Triggered by the detail panel's button. Re-reads the currently
# selected node id rather than binding it so a refresh after a
# selection change is unambiguous.
func _on_research_unlock_pressed() -> void:
	if _research_selected_id == "":
		return
	if not Research.unlock(_research_selected_id):
		return
	_refresh_research_header()
	_refresh_research_detail()
	if _research_graph != null:
		_research_graph.refresh()
		_research_graph.set_selected(_research_selected_id)
	# Unlocking a component lets the Hangar dropdowns see the new tier,
	# and unlocking a capacity tier raises the gate on the Orbital /
	# Surface Ops tabs. Refresh those views so the operator doesn't
	# have to bounce out and back to see the change.
	_rebuild_unit_editor()
	_rebuild_launch_rows()
	_refresh_surface_list()


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
