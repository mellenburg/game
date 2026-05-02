class_name ThreatAlert
extends Control
## Center-screen "THREAT DETECTED" overlay fired when a new meteorite
## wave begins. A semi-opaque red panel + bold all-caps two-line label,
## anchored to the screen center, fading from full alpha through a
## sustain hold and then a linear decay to zero. Hidden when idle.
##
## trigger() resets the timer to 0 — pressing the wave key several
## times in quick succession just retriggers a fresh flash rather than
## stacking multiple overlays.

const UIStyle = preload("res://scripts/ui/ui_style.gd")

const ALERT_HOLD_SEC: float = 0.7        # full-alpha hold after trigger
const ALERT_FADE_SEC: float = 0.9        # linear fade from hold-end to 0
const PANEL_SIZE := Vector2(560.0, 180.0)
# Translucent BAD-tinted fill in the GUI palette; the bordered Panel
# (vs the prior raw ColorRect) carries the 1px BAD edge that ties it
# to the rest of the chip / status language. Same hue as UIStyle.BAD
# (#ff5c5c) at 18% alpha — inlined to keep the constant parse-time
# foldable.
const PANEL_COLOR := Color(1.0, 0.36, 0.36, 0.18)
const TEXT_COLOR := UIStyle.BAD
const TEXT_FONT_SIZE: int = 56
const ALERT_TEXT: String = "THREAT\nDETECTED"

var _t: float = INF  # > total → modulate.a = 0, hidden
var _panel: Panel
var _label: Label


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Span the full HUD so child anchors can centre against the screen,
	# regardless of what offsets the parent set on this node in the
	# scene file.
	set_anchors_preset(Control.PRESET_FULL_RECT)

	_panel = Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL_COLOR
	sb.set_corner_radius_all(0)
	sb.set_border_width_all(1)
	sb.border_color = UIStyle.BAD
	_panel.add_theme_stylebox_override("panel", sb)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_center_anchor(_panel, PANEL_SIZE)
	add_child(_panel)

	_label = Label.new()
	_label.text = ALERT_TEXT
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size", TEXT_FONT_SIZE)
	_label.add_theme_color_override("font_color", TEXT_COLOR)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_center_anchor(_label, PANEL_SIZE)
	add_child(_label)

	visible = false


# Anchor a child Control at the parent's centre, sized at `size`. We
# can't use Control.PRESET_CENTER directly because that preset bakes
# the size into offsets at preset-set time; doing it manually keeps
# PANEL_SIZE the source of truth.
func _center_anchor(node: Control, size: Vector2) -> void:
	node.anchor_left = 0.5
	node.anchor_top = 0.5
	node.anchor_right = 0.5
	node.anchor_bottom = 0.5
	node.offset_left = -size.x * 0.5
	node.offset_top = -size.y * 0.5
	node.offset_right = size.x * 0.5
	node.offset_bottom = size.y * 0.5


## Refire the alert. Stacked presses just reset the timer.
func trigger() -> void:
	_t = 0.0
	modulate.a = 1.0
	visible = true


func _process(delta: float) -> void:
	if not visible:
		return
	_t += delta
	var total := ALERT_HOLD_SEC + ALERT_FADE_SEC
	if _t >= total:
		visible = false
		modulate.a = 1.0
		return
	if _t <= ALERT_HOLD_SEC:
		modulate.a = 1.0
	else:
		var fade_t := (_t - ALERT_HOLD_SEC) / ALERT_FADE_SEC
		modulate.a = clampf(1.0 - fade_t, 0.0, 1.0)
