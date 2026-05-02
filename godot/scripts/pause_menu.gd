extends Control
## In-game pause overlay. Bound to the `pause_game` action (Backspace
## by default). Toggles `get_tree().paused`, releases the mouse so the
## operator can click the menu, and restores the prior mouse capture
## state on resume.
##
## process_mode = ALWAYS so this node keeps ticking when the rest of
## the tree is paused — without it the resume input would never fire
## once paused and the player would be stuck.
##
## UI is built imperatively in _ready (matching the pre-game menu's
## style) and lives entirely on a CanvasLayer parent so it draws over
## the 3D scene independent of camera state.

const MENU_SCENE_PATH := "res://scenes/menu.tscn"
const ReconEditor = preload("res://scripts/menu/recon_editor.gd")

const COLOR_OVERLAY := Color(0.0, 0.0, 0.0, 0.55)
const COLOR_PANEL := Color(0.07, 0.085, 0.11)
const COLOR_PANEL_DIM := Color(0.05, 0.06, 0.08)
const COLOR_LINE := Color(0.18, 0.20, 0.24)
const COLOR_FG := Color(0.86, 0.88, 0.92)
const COLOR_FG_DIM := Color(0.55, 0.58, 0.64)
const COLOR_ACCENT := Color(1.0, 0.706, 0.329)

var _root_panel: PanelContainer
var _settings_panel: PanelContainer

# Mouse mode at the moment of pausing — restored on resume so a
# captured-look player drops back into FPS-look without an extra
# click. If the player was browsing (visible cursor) at pause time
# they stay browsing on resume.
var _saved_mouse_mode: Input.MouseMode = Input.MOUSE_MODE_VISIBLE


func _ready() -> void:
	# Stay live during pause; the rest of the scene halts but this
	# overlay must keep handling input.
	process_mode = Node.PROCESS_MODE_ALWAYS
	anchor_right = 1.0
	anchor_bottom = 1.0
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	_build_ui()


# Toggle on the pause action. _unhandled_input runs even while paused
# (process_mode=ALWAYS), so this is the entry point regardless of
# whether the rest of the scene is ticking.
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause_game"):
		toggle()
		get_viewport().set_input_as_handled()


func toggle() -> void:
	if get_tree().paused:
		_resume()
	else:
		_pause()


func _pause() -> void:
	_saved_mouse_mode = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = true
	visible = true
	_settings_panel.visible = false
	_root_panel.visible = true


func _resume() -> void:
	get_tree().paused = false
	visible = false
	Input.mouse_mode = _saved_mouse_mode


# ---------------------------------------------------------------- UI

func _build_ui() -> void:
	# Dim overlay covers the whole viewport. mouse_filter=STOP on this
	# Control would already block clicks through to the 3D camera; the
	# explicit ColorRect just adds the visual dim.
	var overlay := ColorRect.new()
	overlay.color = COLOR_OVERLAY
	overlay.anchor_right = 1.0
	overlay.anchor_bottom = 1.0
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(overlay)

	_root_panel = _build_main_panel()
	_root_panel.anchor_left = 0.5
	_root_panel.anchor_top = 0.5
	_root_panel.anchor_right = 0.5
	_root_panel.anchor_bottom = 0.5
	_root_panel.offset_left = -180
	_root_panel.offset_right = 180
	_root_panel.offset_top = -180
	_root_panel.offset_bottom = 180
	add_child(_root_panel)

	_settings_panel = _build_settings_panel()
	# Recon editor needs more room than the previous placeholder; size
	# it as a comfortable margin off the viewport edges so the per-class
	# triangles + wave list aren't cramped.
	_settings_panel.anchor_left = 0.0
	_settings_panel.anchor_top = 0.0
	_settings_panel.anchor_right = 1.0
	_settings_panel.anchor_bottom = 1.0
	_settings_panel.offset_left = 60
	_settings_panel.offset_right = -60
	_settings_panel.offset_top = 60
	_settings_panel.offset_bottom = -60
	_settings_panel.visible = false
	add_child(_settings_panel)


func _build_main_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _flat_stylebox(COLOR_PANEL))

	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 24)
	pad.add_theme_constant_override("margin_right", 24)
	pad.add_theme_constant_override("margin_top", 20)
	pad.add_theme_constant_override("margin_bottom", 20)
	panel.add_child(pad)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	pad.add_child(col)

	var title := Label.new()
	title.text = "PAUSED"
	title.add_theme_color_override("font_color", COLOR_ACCENT)
	title.add_theme_font_size_override("font_size", 22)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)

	var sub := Label.new()
	sub.text = "Backspace to resume"
	sub.add_theme_color_override("font_color", COLOR_FG_DIM)
	sub.add_theme_font_size_override("font_size", 11)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(sub)

	col.add_child(_hr())

	col.add_child(_make_button("Resume", _on_resume_pressed))
	col.add_child(_make_button("Settings", _on_settings_pressed))
	col.add_child(_make_button("Abort Mission", _on_abort_pressed))
	col.add_child(_make_button("Exit Game", _on_exit_pressed))
	return panel


# Settings panel is the same Recon editor the pre-game menu's Recon
# tab mounts. Both bind to PlayerLoadout.recon_settings, so an edit
# made while paused persists for the next launch — Mission snapshots
# the settings at start and never re-reads them mid-run, so live
# changes don't reroll the running schedule.
func _build_settings_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _flat_stylebox(COLOR_PANEL))

	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 24)
	pad.add_theme_constant_override("margin_right", 24)
	pad.add_theme_constant_override("margin_top", 20)
	pad.add_theme_constant_override("margin_bottom", 20)
	panel.add_child(pad)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pad.add_child(col)

	var title := Label.new()
	title.text = "RECON"
	title.add_theme_color_override("font_color", COLOR_ACCENT)
	title.add_theme_font_size_override("font_size", 20)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)

	col.add_child(_hr())

	var editor := ReconEditor.new()
	editor.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	editor.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# Bind explicitly even though the editor would resolve the same
	# loadout on its own — being explicit means swapping this overlay
	# in for a different Resource later (e.g. a "scratch" sandbox)
	# only takes the one-line bind change.
	if Engine.has_singleton("PlayerLoadout") or get_tree().root.has_node("PlayerLoadout"):
		editor.bind_settings(get_tree().root.get_node("PlayerLoadout").recon_settings)
	col.add_child(editor)

	col.add_child(_hr())

	col.add_child(_make_button("Back", _on_settings_back_pressed))
	return panel


func _make_button(text: String, handler: Callable) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(0, 36)
	btn.add_theme_font_size_override("font_size", 14)
	btn.pressed.connect(handler)
	return btn


# ---------------------------------------------------------------- handlers

func _on_resume_pressed() -> void:
	_resume()


func _on_settings_pressed() -> void:
	_root_panel.visible = false
	_settings_panel.visible = true


func _on_settings_back_pressed() -> void:
	_settings_panel.visible = false
	_root_panel.visible = true


# Drop straight back to the pre-game menu. Unpause first so the new
# scene starts ticking; restore the cursor since the menu UI needs it.
func _on_abort_pressed() -> void:
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	# PlayerLoadout.launched stays true here; the menu's _ready clears
	# it so a fresh Launch is required to re-enter the stage.
	get_tree().change_scene_to_file(MENU_SCENE_PATH)


func _on_exit_pressed() -> void:
	get_tree().quit()


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
