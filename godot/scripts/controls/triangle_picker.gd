class_name TrianglePicker
extends Control
## Equilateral barycentric picker for a (small, medium, large) ratio.
## Vertices map to "100% of one class"; the centre is 1/3 each;
## edge midpoints are 1/2 / 1/2 / 0 of the two adjacent classes.
## Click or drag inside the triangle to set the ratio; the picker
## emits `weights_changed(s, m, l)` with components summing to 1.0.
##
## Used by the Recon editor's per-wave-unit-class panel: each class
## (small / medium / large wave-unit) has its own triangle that
## controls the *object* size mix inside one wave-unit of that class.

signal weights_changed(small: float, medium: float, large: float)

const COLOR_TRIANGLE := Color(0.10, 0.12, 0.16)
const COLOR_TRIANGLE_BORDER := Color(0.18, 0.20, 0.24)
const COLOR_LABEL := Color(0.86, 0.88, 0.92)
const COLOR_LABEL_DIM := Color(0.55, 0.58, 0.64)
const COLOR_HANDLE := Color(1.0, 0.706, 0.329)
const COLOR_HANDLE_OUTLINE := Color(0.04, 0.05, 0.07)
const COLOR_GUIDE := Color(0.18, 0.20, 0.24)

const HANDLE_RADIUS: float = 7.0
const TRIANGLE_PAD: float = 18.0  # leaves room for vertex labels
const VERTEX_LABEL_FONT_SIZE: int = 12

@export var weight_small: float = 1.0 / 3.0
@export var weight_medium: float = 1.0 / 3.0
@export var weight_large: float = 1.0 / 3.0

var _dragging: bool = false


func _ready() -> void:
	custom_minimum_size = Vector2(180, 180)
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL


# Public reset — reseed the picker after the host editor wrote new
# weights into the bound resource. Renormalises to keep the centre
# dot in a valid spot even if the caller passed unnormalised values.
func set_weights(s: float, m: float, l: float) -> void:
	var n := _normalise(s, m, l)
	weight_small = n[0]
	weight_medium = n[1]
	weight_large = n[2]
	queue_redraw()


# Vertices, in window space. Equilateral triangle inscribed in the
# (size minus padding) rect with the small vertex at the top-left,
# medium at the top-right, large at the bottom centre — chosen so the
# label order reads left → right → bottom and matches the natural
# "small / medium / large" progression most editors render.
func _vertices() -> Array[Vector2]:
	var w := size.x - TRIANGLE_PAD * 2.0
	var h := size.y - TRIANGLE_PAD * 2.0
	var ox := TRIANGLE_PAD
	var oy := TRIANGLE_PAD
	# Equilateral triangle centred horizontally, with one vertex at
	# the top centre and the other two at the base. We rotate the
	# convention so SMALL = top, MEDIUM = bottom-left, LARGE =
	# bottom-right; that puts the "more dangerous" classes lower on
	# screen, mirroring the radar-overlay convention.
	var top := Vector2(ox + w * 0.5, oy)
	var bl := Vector2(ox, oy + h)
	var br := Vector2(ox + w, oy + h)
	return [top, bl, br]


func _draw() -> void:
	var v := _vertices()
	# Body fill + border.
	draw_polygon(
		PackedVector2Array([v[0], v[1], v[2]]),
		PackedColorArray([COLOR_TRIANGLE, COLOR_TRIANGLE, COLOR_TRIANGLE]),
	)
	for i in range(3):
		draw_line(v[i], v[(i + 1) % 3], COLOR_TRIANGLE_BORDER, 1.5)
	# Median guides from each vertex to the opposite edge midpoint —
	# the lines the picker "snaps" along visually so the user can read
	# off pure-class and edge-midpoint positions.
	var m_bl := (v[1] + v[2]) * 0.5
	var m_br := (v[0] + v[2]) * 0.5
	var m_top := (v[0] + v[1]) * 0.5
	draw_line(v[0], m_bl, COLOR_GUIDE, 1.0)
	draw_line(v[1], m_br, COLOR_GUIDE, 1.0)
	draw_line(v[2], m_top, COLOR_GUIDE, 1.0)
	# Vertex labels.
	var font := get_theme_default_font()
	if font != null:
		_draw_vertex_label(font, v[0], "S %d%%" % int(round(weight_small * 100.0)),
			Vector2(-20, -6), COLOR_LABEL_DIM)
		_draw_vertex_label(font, v[1], "M %d%%" % int(round(weight_medium * 100.0)),
			Vector2(-44, 16), COLOR_LABEL_DIM)
		_draw_vertex_label(font, v[2], "L %d%%" % int(round(weight_large * 100.0)),
			Vector2(8, 16), COLOR_LABEL_DIM)
	# Handle dot at the current barycentric position.
	var p := _barycentric_to_pixel(weight_small, weight_medium, weight_large)
	draw_circle(p, HANDLE_RADIUS + 1.0, COLOR_HANDLE_OUTLINE)
	draw_circle(p, HANDLE_RADIUS, COLOR_HANDLE)


func _draw_vertex_label(
	font: Font, anchor: Vector2, text: String, offset: Vector2, color: Color
) -> void:
	draw_string(
		font, anchor + offset, text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, VERTEX_LABEL_FONT_SIZE, color,
	)


# Barycentric (s, m, l) → pixel position inside the triangle. Mirrors
# the vertex assignment in `_vertices`: s → top, m → bottom-left,
# l → bottom-right.
func _barycentric_to_pixel(s: float, m: float, l: float) -> Vector2:
	var v := _vertices()
	return v[0] * s + v[1] * m + v[2] * l


# Pixel → barycentric. Standard inverse via signed-area weights;
# clamps each component to [0, 1] and renormalises so the result
# stays inside the triangle even if the click landed slightly outside.
func _pixel_to_barycentric(p: Vector2) -> Array[float]:
	var v := _vertices()
	var d := (v[1].y - v[2].y) * (v[0].x - v[2].x) + (v[2].x - v[1].x) * (v[0].y - v[2].y)
	if absf(d) < 1.0e-6:
		return [1.0 / 3.0, 1.0 / 3.0, 1.0 / 3.0]
	var s := ((v[1].y - v[2].y) * (p.x - v[2].x) + (v[2].x - v[1].x) * (p.y - v[2].y)) / d
	var m := ((v[2].y - v[0].y) * (p.x - v[2].x) + (v[0].x - v[2].x) * (p.y - v[2].y)) / d
	var l := 1.0 - s - m
	return _normalise(maxf(s, 0.0), maxf(m, 0.0), maxf(l, 0.0))


func _normalise(s: float, m: float, l: float) -> Array[float]:
	var total := s + m + l
	if total <= 0.0:
		return [1.0 / 3.0, 1.0 / 3.0, 1.0 / 3.0]
	return [s / total, m / total, l / total]


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return
		if mb.pressed:
			_dragging = true
			_apply_pixel(mb.position)
			grab_focus()
		else:
			if _dragging:
				_dragging = false
				_apply_pixel(mb.position)
				emit_signal(
					"weights_changed",
					weight_small, weight_medium, weight_large,
				)
	elif event is InputEventMouseMotion and _dragging:
		var mm := event as InputEventMouseMotion
		_apply_pixel(mm.position)
		emit_signal(
			"weights_changed",
			weight_small, weight_medium, weight_large,
		)


func _apply_pixel(p: Vector2) -> void:
	var b := _pixel_to_barycentric(p)
	weight_small = b[0]
	weight_medium = b[1]
	weight_large = b[2]
	queue_redraw()
