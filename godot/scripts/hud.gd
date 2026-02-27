class_name HUD
extends Control
## HUD overlay showing orbital info, targeting lines, and LOS indicators.
## Port of hud.cpp.

const EARTH_RADIUS_SQ: float = 6371.0 * 6371.0  # km^2

@onready var info_label: RichTextLabel = $InfoLabel
@onready var target_container: Control = $TargetContainer

var camera: Camera3D


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Check if Earth blocks line of sight between two positions (km)
static func check_los_blocked(start: Vector3, end: Vector3) -> bool:
	var dir := end - start
	var a_coeff := dir.dot(dir)
	var b_coeff := 2.0 * dir.dot(start)
	var c_coeff := start.dot(start) - EARTH_RADIUS_SQ
	var discr := b_coeff * b_coeff - 4.0 * a_coeff * c_coeff
	if discr < 0.0:
		return false
	var sqrt_discr := sqrt(discr)
	var q: float
	if b_coeff > 0.0:
		q = -0.5 * (b_coeff + sqrt_discr)
	else:
		q = -0.5 * (b_coeff - sqrt_discr)
	var t0 := q / a_coeff
	var t1 := c_coeff / q
	if t0 > t1:
		var tmp := t0
		t0 = t1
		t1 = tmp
	if t0 < 0.0:
		t0 = t1
		if t0 < 0.0:
			return false
	if t0 > 1.0:
		return false
	return true


func update_hud(orbital_set: Node, planning_mode: bool, time_factor: int, dt: int) -> void:
	if not info_label:
		return

	var satellites = orbital_set.satellites
	var selected_idx = orbital_set.selected_ship
	if satellites.is_empty():
		info_label.text = ""
		return

	var selected: Satellite = satellites[selected_idx]
	var main_pos := selected.get_r()
	var main_vel := selected.get_v()

	var text := "[font_size=14]"

	# Mode indicator
	if planning_mode:
		text += "[color=yellow]PLANNING MODE[/color]\n"
	text += "Time Factor: %d\n" % time_factor
	if planning_mode:
		text += "Planning dt: %d\n" % dt
	text += "\n"

	# Selected ship info
	text += "[color=green]Selected Ship[/color]\n"
	text += "  Alt: %.0f km\n" % (selected.orbit.norm_r - 6371.0)
	text += "  Vel: %.3f km/s\n" % selected.orbit.norm_v
	text += "  Ecc: %.4f\n" % selected.orbit.ecc
	text += "  Inc: %.2f deg\n" % rad_to_deg(selected.orbit.inc)
	text += "  Per: %.0f s\n" % selected.orbit.period
	text += "\n"

	# Target info for each other satellite
	for i in range(satellites.size()):
		if i == selected_idx:
			continue
		var other: Satellite = satellites[i]
		var other_pos := other.get_r()
		var other_vel := other.get_v()
		var distance := main_pos.distance_to(other_pos)
		var rel_vel := main_vel.distance_to(other_vel)
		var blocked := check_los_blocked(main_pos, other_pos)

		var los_color := "yellow" if blocked else "red"
		text += "[color=%s]Target %d[/color]\n" % [los_color, i]
		text += "  Distance: %.0f km\n" % distance
		text += "  delta-V: %.2f km/s\n" % rel_vel
		text += "  LOS: %s\n" % ("BLOCKED" if blocked else "CLEAR")

	text += "[/font_size]"
	info_label.text = text


func draw_target_lines(orbital_set: Node, cam: Camera3D) -> void:
	camera = cam
	queue_redraw()
	# Store data for _draw
	_draw_data_set = orbital_set


var _draw_data_set: Node = null


func _draw() -> void:
	if not _draw_data_set or not camera:
		return
	var satellites = _draw_data_set.satellites
	var selected_idx = _draw_data_set.selected_ship
	if satellites.is_empty():
		return

	var selected: Satellite = satellites[selected_idx]
	var main_pos := selected.get_r_scaled()

	for i in range(satellites.size()):
		if i == selected_idx:
			continue
		var other: Satellite = satellites[i]
		var other_pos := other.get_r_scaled()

		var screen_a := camera.unproject_position(main_pos)
		var screen_b := camera.unproject_position(other_pos)

		# Check if both positions are in front of the camera
		var behind_a := camera.is_position_behind(main_pos)
		var behind_b := camera.is_position_behind(other_pos)
		if behind_a and behind_b:
			continue

		var blocked := HUD.check_los_blocked(selected.get_r(), other.get_r())
		var line_color := Color.YELLOW if blocked else Color.RED
		draw_line(screen_a, screen_b, line_color, 1.0)
