class_name ReconEditor
extends VBoxContainer
## Recon editor — the player's view onto ReconSettings. Mounted as a
## tab in the pre-game menu (`Recon`) and as the in-game pause-menu
## "Settings" panel; both bind to PlayerLoadout.recon_settings so an
## edit in either surface persists for the next launch.
##
## Two sections, stacked vertically:
##
##   1. Wave-Unit Classes — three per-class panels (alpha / beta /
##      gamma) side-by-side, each containing a RangeSlider for the
##      object count, a RangeSlider for the decaying ratio, and a
##      TrianglePicker for the per-object size mix (the triangle's
##      S/M/L corners pick *object* mass bands inside one wave-unit;
##      the alpha/beta/gamma label belongs to the wave-unit itself).
##
##   2. Wave Composition — a vertical list of waves, one row per
##      wave. Each row carries spinboxes for the number of alpha /
##      beta / gamma wave-units, a RangeSlider for the wave's
##      duration, a RangeSlider for the inter-wave delay, and a
##      "Random" checkbox toggling even-vs-random distribution.
##      Buttons at the bottom add or remove waves; deletes apply
##      from the end of the list (so a launch never has gaps).
##
## All edits go to the ReconSettings instance live; mid-mission edits
## queue for the next launch (Mission snapshots ReconSettings at
## start and never re-reads). The editor has no "save" affordance —
## changes are durable as soon as the player makes them.

const ReconSettings = preload("res://scripts/recon_settings.gd")
const WaveUnitClass = preload("res://scripts/wave_unit_class.gd")
const WaveComposition = preload("res://scripts/wave_composition.gd")
const RangeSlider = preload("res://scripts/controls/range_slider.gd")
const TrianglePicker = preload("res://scripts/controls/triangle_picker.gd")

const COLOR_PANEL := Color(0.07, 0.085, 0.11)
const COLOR_PANEL_DIM := Color(0.05, 0.06, 0.08)
const COLOR_LINE := Color(0.18, 0.20, 0.24)
const COLOR_FG := Color(0.86, 0.88, 0.92)
const COLOR_FG_DIM := Color(0.55, 0.58, 0.64)
const COLOR_FG_FAINT := Color(0.34, 0.36, 0.40)
const COLOR_ACCENT := Color(1.0, 0.706, 0.329)

# Default-spread fractions — when a slider opens at min==max, expand
# the handles to this fraction of the total range so the bar is
# visible / draggable. Different per-knob so duration sliders don't
# look as wide as count sliders by default.
const COUNT_DEFAULT_SPREAD: float = 0.15
const RATIO_DEFAULT_SPREAD: float = 0.20
const DURATION_DEFAULT_SPREAD: float = 0.20
const DELAY_DEFAULT_SPREAD: float = 0.10

const COUNT_MIN_BOUND: float = 1.0
# Wave-unit class object-count cap: the engine starts dropping frames
# as a single wave-unit's body count climbs past ~50 on the
# Compatibility renderer, so the per-class slider tops out here.
# Mission additionally enforces a per-wave 250-body cap across
# siblings so the slider's top end is always reachable in isolation.
const COUNT_MAX_BOUND: float = 50.0
const RATIO_MIN_BOUND: float = 0.0
const RATIO_MAX_BOUND: float = 1.0
# Duration / delay are now expressed in *game-time hours* (see
# WaveComposition). Bounds picked to give the editor room for
# multi-hour delays between waves and sub-hour spawn windows; mission
# tick advances in sim-time so these scale with time_factor.
const DURATION_MIN_BOUND: float = 0.0
const DURATION_MAX_BOUND: float = 6.0
const DELAY_MIN_BOUND: float = 0.0
const DELAY_MAX_BOUND: float = 24.0
const UNIT_COUNT_MAX_BOUND: float = 50.0

var _settings: ReconSettings
var _waves_list_root: VBoxContainer


func _ready() -> void:
	add_theme_constant_override("separation", 12)
	# If the host scene didn't pre-bind a settings instance, fall back
	# to PlayerLoadout's so the editor is usable in isolation as well.
	if _settings == null:
		_settings = _resolve_default_settings()
	_build_ui()


# Bind the editor to a specific ReconSettings instance. Call before
# adding the editor to the tree if you want a non-default binding;
# safe to call after _ready as well — it triggers a rebuild.
func bind_settings(settings: ReconSettings) -> void:
	_settings = settings
	if is_inside_tree():
		_rebuild_ui()


func _resolve_default_settings() -> ReconSettings:
	var tree := get_tree()
	if tree != null:
		var loadout := tree.root.get_node_or_null("PlayerLoadout")
		if loadout != null and loadout.recon_settings != null:
			return loadout.recon_settings
	return ReconSettings.default_settings()


func _rebuild_ui() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_build_ui()


func _build_ui() -> void:
	add_child(_build_classes_section())
	add_child(_build_waves_section())


# ============================================================
# Section 1 — wave-unit class panels
# ============================================================

func _build_classes_section() -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _flat_stylebox(COLOR_PANEL))
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 16)
	pad.add_theme_constant_override("margin_right", 16)
	pad.add_theme_constant_override("margin_top", 12)
	pad.add_theme_constant_override("margin_bottom", 12)
	panel.add_child(pad)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	pad.add_child(col)

	var header := Label.new()
	header.text = "WAVE-UNIT CLASSES"
	header.add_theme_color_override("font_color", COLOR_ACCENT)
	header.add_theme_font_size_override("font_size", 13)
	col.add_child(header)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(row)

	row.add_child(_build_class_panel("α", "Alpha", _settings.alpha_class))
	row.add_child(_build_class_panel("β", "Beta", _settings.beta_class))
	row.add_child(_build_class_panel("γ", "Gamma", _settings.gamma_class))
	return panel


func _build_class_panel(
	glyph: String, name: String, c: WaveUnitClass
) -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _flat_stylebox(COLOR_PANEL_DIM))
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_stretch_ratio = 1.0

	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 12)
	pad.add_theme_constant_override("margin_right", 12)
	pad.add_theme_constant_override("margin_top", 10)
	pad.add_theme_constant_override("margin_bottom", 10)
	panel.add_child(pad)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	pad.add_child(col)

	# Greek glyph + roman name as two side-by-side labels so the glyph
	# can dominate (it's the editor-wide identifier) while the spelled
	# name reads as a quieter affordance. A single Label with both
	# substrings would force one font size on both.
	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 8)
	col.add_child(title_row)

	var glyph_lbl := Label.new()
	glyph_lbl.text = glyph
	glyph_lbl.add_theme_color_override("font_color", COLOR_FG)
	glyph_lbl.add_theme_font_size_override("font_size", 22)
	title_row.add_child(glyph_lbl)

	var name_lbl := Label.new()
	name_lbl.text = name
	name_lbl.add_theme_color_override("font_color", COLOR_FG_DIM)
	name_lbl.add_theme_font_size_override("font_size", 13)
	# Anchor the spelled name vertically against the glyph's baseline.
	name_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	title_row.add_child(name_lbl)

	col.add_child(_field_label("Object count"))
	var count_slider := RangeSlider.new()
	count_slider.min_value = COUNT_MIN_BOUND
	count_slider.max_value = COUNT_MAX_BOUND
	count_slider.step = 1.0
	count_slider.value_format = "%d"
	count_slider.default_spread_fraction = COUNT_DEFAULT_SPREAD
	count_slider.set_range_values(float(c.count_min), float(c.count_max))
	count_slider.value_changed.connect(
		func(low: float, high: float) -> void:
			c.count_min = int(round(low))
			c.count_max = int(round(high))
			c.clamp_count_range()
	)
	col.add_child(count_slider)

	col.add_child(_field_label("Decaying ratio"))
	var ratio_slider := RangeSlider.new()
	ratio_slider.min_value = RATIO_MIN_BOUND
	ratio_slider.max_value = RATIO_MAX_BOUND
	ratio_slider.value_format = "%.2f"
	ratio_slider.default_spread_fraction = RATIO_DEFAULT_SPREAD
	ratio_slider.set_range_values(c.decaying_ratio_min, c.decaying_ratio_max)
	ratio_slider.value_changed.connect(
		func(low: float, high: float) -> void:
			c.decaying_ratio_min = low
			c.decaying_ratio_max = high
			c.clamp_decaying_range()
	)
	col.add_child(ratio_slider)

	col.add_child(_field_label("Object size mix"))
	var triangle := TrianglePicker.new()
	triangle.set_weights(c.size_small, c.size_medium, c.size_large)
	# The triangle is intrinsically square (it self-clamps to a square
	# render area), so we don't expand it vertically — letting it
	# stretch in a tall column would just leave empty space above /
	# below the rendered triangle.
	triangle.weights_changed.connect(
		func(s: float, m: float, l: float) -> void:
			c.size_small = s
			c.size_medium = m
			c.size_large = l
	)
	col.add_child(triangle)

	col.add_child(_field_label("Location spread (arc°)"))
	col.add_child(_single_value_slider(
		c.location_arc_deg,
		WaveUnitClass.ARC_MIN_DEG,
		WaveUnitClass.ARC_MAX_DEG,
		1.0, "%d°",
		func(v: float) -> void:
			c.location_arc_deg = v
			c.clamp_location_arc(),
	))

	col.add_child(_field_label("Time spread (min)"))
	col.add_child(_single_value_slider(
		c.time_spread_min,
		WaveUnitClass.TIME_SPREAD_MIN_MIN,
		WaveUnitClass.TIME_SPREAD_MAX_MIN,
		1.0, "%d",
		func(v: float) -> void:
			c.time_spread_min = v
			c.clamp_time_spread(),
	))

	return panel


# 1-D slider with a current-value readout below the bar. Used for the
# per-wave-unit-class arc and time-spread fields, which are point
# values rather than ranges. Built around HSlider + a Label so we
# don't grow yet another custom Control for a one-handle case.
func _single_value_slider(
	initial: float,
	min_bound: float,
	max_bound: float,
	step: float,
	value_format: String,
	on_change: Callable,
) -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)

	var slider := HSlider.new()
	slider.min_value = min_bound
	slider.max_value = max_bound
	slider.step = step
	slider.value = initial
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(slider)

	var readout := Label.new()
	readout.text = value_format % initial
	readout.add_theme_color_override("font_color", COLOR_FG_FAINT)
	readout.add_theme_font_size_override("font_size", 10)
	readout.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(readout)

	slider.value_changed.connect(
		func(v: float) -> void:
			readout.text = value_format % v
			on_change.call(v)
	)
	return col


# ============================================================
# Section 2 — wave list
# ============================================================

func _build_waves_section() -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _flat_stylebox(COLOR_PANEL))
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 16)
	pad.add_theme_constant_override("margin_right", 16)
	pad.add_theme_constant_override("margin_top", 12)
	pad.add_theme_constant_override("margin_bottom", 12)
	panel.add_child(pad)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pad.add_child(col)

	var header_row := HBoxContainer.new()
	header_row.add_theme_constant_override("separation", 8)
	col.add_child(header_row)

	var header := Label.new()
	header.text = "WAVE COMPOSITION"
	header.add_theme_color_override("font_color", COLOR_ACCENT)
	header.add_theme_font_size_override("font_size", 13)
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_row.add_child(header)

	var add_btn := Button.new()
	add_btn.text = "+ Add Wave"
	add_btn.add_theme_font_size_override("font_size", 12)
	add_btn.pressed.connect(_on_add_wave_pressed)
	header_row.add_child(add_btn)

	var reset_btn := Button.new()
	reset_btn.text = "Reset"
	reset_btn.add_theme_font_size_override("font_size", 12)
	reset_btn.pressed.connect(_on_reset_pressed)
	header_row.add_child(reset_btn)

	# Waves list lives inside a scroll container so a long campaign
	# doesn't push the per-class panels off-screen on small viewports.
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(scroll)

	_waves_list_root = VBoxContainer.new()
	_waves_list_root.add_theme_constant_override("separation", 6)
	_waves_list_root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_waves_list_root)

	_rebuild_waves_list()
	return panel


func _rebuild_waves_list() -> void:
	if _waves_list_root == null:
		return
	for child in _waves_list_root.get_children():
		_waves_list_root.remove_child(child)
		child.queue_free()
	for i in range(_settings.waves.size()):
		_waves_list_root.add_child(_build_wave_row(i))


func _build_wave_row(idx: int) -> Control:
	var w: WaveComposition = _settings.waves[idx]

	var row := PanelContainer.new()
	row.add_theme_stylebox_override("panel", _flat_stylebox(COLOR_PANEL_DIM))

	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 10)
	pad.add_theme_constant_override("margin_right", 10)
	pad.add_theme_constant_override("margin_top", 8)
	pad.add_theme_constant_override("margin_bottom", 8)
	row.add_child(pad)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 12)
	pad.add_child(hbox)

	var idx_label := Label.new()
	idx_label.text = "W%02d" % (idx + 1)
	idx_label.add_theme_color_override("font_color", COLOR_ACCENT)
	idx_label.add_theme_font_size_override("font_size", 12)
	idx_label.custom_minimum_size = Vector2(36, 0)
	hbox.add_child(idx_label)

	hbox.add_child(_unit_count_column("α", w.alpha_units,
		func(v: int) -> void: w.alpha_units = v))
	hbox.add_child(_unit_count_column("β", w.beta_units,
		func(v: int) -> void: w.beta_units = v))
	hbox.add_child(_unit_count_column("γ", w.gamma_units,
		func(v: int) -> void: w.gamma_units = v))

	hbox.add_child(_wave_range_column("Duration (h)",
		w.duration_min, w.duration_max,
		DURATION_MIN_BOUND, DURATION_MAX_BOUND,
		DURATION_DEFAULT_SPREAD, "%.2f",
		func(low: float, high: float) -> void:
			w.duration_min = low
			w.duration_max = high
			w.clamp_duration()))

	hbox.add_child(_wave_range_column("Delay (h)",
		w.delay_min, w.delay_max,
		DELAY_MIN_BOUND, DELAY_MAX_BOUND,
		DELAY_DEFAULT_SPREAD, "%.2f",
		func(low: float, high: float) -> void:
			w.delay_min = low
			w.delay_max = high
			w.clamp_delay()))

	hbox.add_child(_random_toggle_column(w))

	var del := Button.new()
	del.text = "✕"
	del.add_theme_font_size_override("font_size", 12)
	del.tooltip_text = "Remove wave"
	del.custom_minimum_size = Vector2(28, 0)
	del.pressed.connect(_on_remove_wave_pressed.bind(idx))
	hbox.add_child(del)
	return row


func _unit_count_column(
	title: String, initial: int, on_change: Callable
) -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	col.custom_minimum_size = Vector2(72, 0)
	# Class glyph rendered larger and brighter than the dim 10pt
	# `_field_label` style that captions the surrounding range
	# columns — these single-character class identifiers are the
	# wave row's anchor and need to read at a glance.
	var glyph_lbl := Label.new()
	glyph_lbl.text = title
	glyph_lbl.add_theme_color_override("font_color", COLOR_FG)
	glyph_lbl.add_theme_font_size_override("font_size", 18)
	glyph_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(glyph_lbl)

	var sb := SpinBox.new()
	sb.min_value = 0
	sb.max_value = UNIT_COUNT_MAX_BOUND
	sb.step = 1
	sb.value = float(initial)
	sb.custom_minimum_size = Vector2(64, 0)
	sb.value_changed.connect(
		func(v: float) -> void: on_change.call(int(round(v)))
	)
	col.add_child(sb)
	return col


func _wave_range_column(
	title: String,
	low: float,
	high: float,
	min_bound: float,
	max_bound: float,
	default_spread: float,
	fmt: String,
	on_change: Callable,
) -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(_field_label(title))

	var slider := RangeSlider.new()
	slider.min_value = min_bound
	slider.max_value = max_bound
	slider.value_format = fmt
	slider.default_spread_fraction = default_spread
	slider.set_range_values(low, high)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.value_changed.connect(on_change)
	col.add_child(slider)
	return col


func _random_toggle_column(w: WaveComposition) -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	col.add_child(_field_label("Random"))
	var cb := CheckBox.new()
	cb.button_pressed = w.randomized
	cb.toggled.connect(func(v: bool) -> void: w.randomized = v)
	col.add_child(cb)
	return col


# ============================================================
# Wave-list buttons
# ============================================================

func _on_add_wave_pressed() -> void:
	_settings.add_wave()
	_rebuild_waves_list()


func _on_remove_wave_pressed(idx: int) -> void:
	_settings.remove_wave_at(idx)
	_rebuild_waves_list()


func _on_reset_pressed() -> void:
	# Mutate in place so any host code holding a ref to the settings
	# (PlayerLoadout, the in-game pause menu) doesn't lose its handle.
	var fresh := ReconSettings.default_settings()
	_settings.alpha_class = fresh.alpha_class
	_settings.beta_class = fresh.beta_class
	_settings.gamma_class = fresh.gamma_class
	_settings.waves = fresh.waves
	_rebuild_ui()


# ============================================================
# Helpers
# ============================================================

func _field_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", COLOR_FG_FAINT)
	l.add_theme_font_size_override("font_size", 10)
	return l


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
