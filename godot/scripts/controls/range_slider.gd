class_name RangeSlider
extends Control
## A 1-D range slider: a horizontal track with a draggable bar between
## a `low` and a `high` handle. Drag either handle to nudge that side
## of the range; drag the bar between them to move both handles
## simultaneously while preserving the spread.
##
## Used by the Recon editor for "min may equal max" parameters
## (object count, decaying ratio, wave duration, wave delay). Emits
## `value_changed` whenever the user releases or drags either handle;
## the editor mirrors the new (low, high) into the Resource and the
## sim picks them up on next launch.

signal value_changed(low: float, high: float)

const COLOR_TRACK := Color(0.10, 0.12, 0.16)
const COLOR_TRACK_FILL := Color(1.0, 0.706, 0.329)
const COLOR_HANDLE := Color(0.96, 0.97, 1.0)
const COLOR_HANDLE_HOVER := Color(1.0, 0.85, 0.55)
const COLOR_LABEL := Color(0.86, 0.88, 0.92)

const TRACK_THICKNESS: float = 6.0
const HANDLE_RADIUS: float = 7.0
const VERTICAL_PAD: float = 14.0  # leaves room for the value label below

@export var min_value: float = 0.0
@export var max_value: float = 1.0
@export var step: float = 0.0  # 0 = continuous; >0 quantises both handles
@export var low: float = 0.0
@export var high: float = 1.0
# Default spread used when the editor first opens a slider whose
# stored low == high. Lets the user "see" both handles instead of one
# point. Set in fraction-of-range units; 0.2 = 20% of (max - min).
@export var default_spread_fraction: float = 0.2
# Optional formatter for the readout label below the track. Defaults
# to two-decimal float; the editor overrides this for integer fields.
@export var value_format: String = "%.2f"

enum DragKind {NONE, LOW, HIGH, BAR}

var _drag_kind: int = DragKind.NONE
var _drag_origin_x: float = 0.0
var _drag_origin_low: float = 0.0
var _drag_origin_high: float = 0.0
var _hovered_kind: int = DragKind.NONE


func _ready() -> void:
	custom_minimum_size = Vector2(160, TRACK_THICKNESS + HANDLE_RADIUS * 2 + VERTICAL_PAD)
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	# If the loaded values collapsed to a point, expand them by the
	# configured default spread so the bar is visually editable.
	_expand_to_default_spread_if_collapsed()


# Public reset — call when the host editor pushes new values into the
# slider so the redraw picks them up.
func set_range_values(new_low: float, new_high: float) -> void:
	low = clampf(new_low, min_value, max_value)
	high = clampf(new_high, min_value, max_value)
	if low > high:
		var tmp := low
		low = high
		high = tmp
	queue_redraw()


# If both handles collapsed to the same point at construction, push
# them apart by the configured fraction so the bar has a visible
# default spread the user can grab. The collapsed value is preserved
# as the centre.
func _expand_to_default_spread_if_collapsed() -> void:
	if absf(high - low) > 1.0e-6:
		return
	var span := max_value - min_value
	if span <= 0.0:
		return
	var spread := span * default_spread_fraction
	var centre := low
	low = clampf(centre - spread * 0.5, min_value, max_value)
	high = clampf(centre + spread * 0.5, min_value, max_value)


func _draw() -> void:
	var rect := _track_rect()
	# Bare track fills the full slider extent.
	draw_rect(rect, COLOR_TRACK, true)
	# Filled span between the two handles.
	var lo_x := _value_to_x(low)
	var hi_x := _value_to_x(high)
	var fill := Rect2(
		Vector2(lo_x, rect.position.y),
		Vector2(maxf(hi_x - lo_x, 1.0), rect.size.y),
	)
	draw_rect(fill, COLOR_TRACK_FILL, true)
	# Two handles drawn after fill so they overlap the bar's edges.
	_draw_handle(lo_x, rect, _hovered_kind == DragKind.LOW)
	_draw_handle(hi_x, rect, _hovered_kind == DragKind.HIGH)
	# Readout label centred under the bar.
	_draw_label()


func _draw_handle(x: float, track: Rect2, hovered: bool) -> void:
	var c := COLOR_HANDLE_HOVER if hovered else COLOR_HANDLE
	var centre := Vector2(x, track.position.y + track.size.y * 0.5)
	draw_circle(centre, HANDLE_RADIUS, c)


func _draw_label() -> void:
	var font := get_theme_default_font()
	if font == null:
		return
	var size_px := 11
	var text := "%s — %s" % [value_format % low, value_format % high]
	var w := size.x
	var pos := Vector2(
		w * 0.5 - font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px).x * 0.5,
		size.y - 2.0,
	)
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, COLOR_LABEL)


func _track_rect() -> Rect2:
	return Rect2(
		Vector2(HANDLE_RADIUS, (size.y - VERTICAL_PAD - TRACK_THICKNESS) * 0.5),
		Vector2(maxf(size.x - HANDLE_RADIUS * 2.0, 1.0), TRACK_THICKNESS),
	)


func _value_to_x(value: float) -> float:
	var t := 0.5
	if max_value > min_value:
		t = (value - min_value) / (max_value - min_value)
	var rect := _track_rect()
	return rect.position.x + rect.size.x * t


func _x_to_value(x: float) -> float:
	var rect := _track_rect()
	if rect.size.x <= 0.0:
		return min_value
	var t := clampf((x - rect.position.x) / rect.size.x, 0.0, 1.0)
	var v := min_value + t * (max_value - min_value)
	if step > 0.0:
		v = roundf(v / step) * step
	return clampf(v, min_value, max_value)


# Hit test for cursor-shape feedback. Handles take priority because
# they're the more precise drag target; the bar-between fallback
# kicks in when the cursor is over the fill but not directly on a
# handle.
func _kind_at(pos: Vector2) -> int:
	var lo_x := _value_to_x(low)
	var hi_x := _value_to_x(high)
	var rect := _track_rect()
	var centre_y := rect.position.y + rect.size.y * 0.5
	if absf(pos.x - lo_x) <= HANDLE_RADIUS and absf(pos.y - centre_y) <= HANDLE_RADIUS:
		return DragKind.LOW
	if absf(pos.x - hi_x) <= HANDLE_RADIUS and absf(pos.y - centre_y) <= HANDLE_RADIUS:
		return DragKind.HIGH
	if pos.x >= lo_x and pos.x <= hi_x and absf(pos.y - centre_y) <= rect.size.y:
		return DragKind.BAR
	return DragKind.NONE


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		_handle_mouse_button(event)
	elif event is InputEventMouseMotion:
		_handle_mouse_motion(event)


func _handle_mouse_button(event: InputEventMouseButton) -> void:
	if event.button_index != MOUSE_BUTTON_LEFT:
		return
	if event.pressed:
		_drag_kind = _kind_at(event.position)
		_drag_origin_x = event.position.x
		_drag_origin_low = low
		_drag_origin_high = high
		grab_focus()
	else:
		if _drag_kind != DragKind.NONE:
			_drag_kind = DragKind.NONE
			emit_signal("value_changed", low, high)


func _handle_mouse_motion(event: InputEventMouseMotion) -> void:
	var prev_hover := _hovered_kind
	_hovered_kind = _kind_at(event.position)
	if _hovered_kind != prev_hover:
		queue_redraw()
	if _drag_kind == DragKind.NONE:
		return
	var v := _x_to_value(event.position.x)
	match _drag_kind:
		DragKind.LOW:
			low = minf(v, high)
		DragKind.HIGH:
			high = maxf(v, low)
		DragKind.BAR:
			# Translate the bar by the cursor delta, preserving span.
			# Clamp at both edges so the bar can't be dragged off-track.
			var span := _drag_origin_high - _drag_origin_low
			var origin_v := _x_to_value(_drag_origin_x)
			var delta := v - origin_v
			var new_low := clampf(_drag_origin_low + delta, min_value, max_value - span)
			low = new_low
			high = new_low + span
	queue_redraw()
	emit_signal("value_changed", low, high)
