class_name HPBar
extends Control
## Thin horizontal HP indicator. Owns one float (`hp_ratio` in [0,1])
## and repaints itself when it changes; HUD sets the ratio each tick
## from whatever satellite is currently selected. Color lerps from a
## red "almost dead" tint at 0 toward green at full HP so the bar
## reads as a damage gauge at a glance, distinct from the textual
## stats above it.

const BAR_HEIGHT: float = 4.0
const COLOR_BG := Color(0.08, 0.10, 0.14, 0.85)
const COLOR_FULL := Color(0.40, 0.80, 0.50, 0.90)
const COLOR_LOW := Color(0.90, 0.40, 0.30, 0.90)

var hp_ratio: float = 0.0:
	set(value):
		var clamped: float = clampf(value, 0.0, 1.0)
		if not is_equal_approx(clamped, hp_ratio):
			hp_ratio = clamped
			queue_redraw()


func _ready() -> void:
	custom_minimum_size = Vector2(0, BAR_HEIGHT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var w: float = size.x
	var h: float = BAR_HEIGHT
	draw_rect(Rect2(0.0, 0.0, w, h), COLOR_BG, true)
	if hp_ratio <= 0.0:
		return
	var fill_color: Color = COLOR_LOW.lerp(COLOR_FULL, hp_ratio)
	draw_rect(Rect2(0.0, 0.0, w * hp_ratio, h), fill_color, true)
