class_name HUD
extends Control
## Orbital info readout + targeting lines. Throttles BBCode rebuilds to
## ~10 Hz so the RichTextLabel parser isn't burning frame budget every
## tick. Targeting lines are drawn directly via _draw().

const Satellite = preload("res://scripts/satellite.gd")
const LosCheck = preload("res://scripts/los_check.gd")

const HUD_UPDATE_INTERVAL: float = 0.1  # seconds

@onready var info_label: RichTextLabel = $InfoLabel as RichTextLabel
@onready var target_container: Control = $TargetContainer as Control

var _camera: Camera3D
var _system: Node = null
var _last_text_update: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func update_hud(orbital_set: Node, planning_mode: bool, time_factor: int, dt: int) -> void:
	if info_label == null:
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now - _last_text_update < HUD_UPDATE_INTERVAL:
		return
	_last_text_update = now

	var satellites: Array = orbital_set.satellites
	# In planning mode, satellites is planning_satellites and the active
	# index is planning_selected — selected_ship indexes real_satellites
	# and can disagree if the user has added/removed ships mid-plan.
	var selected_idx: int = (
		orbital_set.planning_selected if planning_mode
		else orbital_set.selected_ship
	)
	if satellites.is_empty() or selected_idx < 0 or selected_idx >= satellites.size():
		info_label.text = ""
		return

	var selected: Satellite = satellites[selected_idx]
	if not selected.alive:
		info_label.text = "[color=red]Selected satellite is destroyed.[/color]"
		return
	if not selected.orbit_alive:
		info_label.text = "[color=red]Selected satellite is dead.[/color]"
		return

	var main_pos: Vector3 = selected.orbit.r
	var main_vel: Vector3 = selected.orbit.v

	var lines := PackedStringArray()
	lines.append("[font_size=14]")
	if planning_mode:
		lines.append("[color=yellow]PLANNING MODE[/color]")
	lines.append("Time Factor: %d" % time_factor)
	if planning_mode:
		lines.append("Planning dt: %d" % dt)
	lines.append("")
	var team_label := "Enemy" if selected.team == Satellite.TEAM_ENEMY else "Selected Ship"
	var team_color := "red" if selected.team == Satellite.TEAM_ENEMY else "green"
	lines.append("[color=%s]%s[/color]" % [team_color, team_label])
	lines.append("  HP: %.0f / %.0f" % [selected.hp, Satellite.MAX_HP])
	if selected.weapon != null:
		lines.append("  Energy: %d%%" % int(selected.weapon.energy * 100.0))
	lines.append("  Alt: %.0f km" % (selected.orbit.norm_r - 6371.0))
	lines.append("  Vel: %.3f km/s" % selected.orbit.norm_v)
	lines.append("  Ecc: %.4f" % selected.orbit.ecc)
	lines.append("  Inc: %.2f deg" % rad_to_deg(selected.orbit.inc))
	if is_finite(selected.orbit.period):
		lines.append("  Per: %.0f s" % selected.orbit.period)
	lines.append("")

	for i in range(satellites.size()):
		if i == selected_idx:
			continue
		var other: Satellite = satellites[i]
		if not other.orbit_alive or not other.alive:
			continue
		var other_pos: Vector3 = other.orbit.r
		var other_vel: Vector3 = other.orbit.v
		var distance := main_pos.distance_to(other_pos)
		var rel_vel := main_vel.distance_to(other_vel)
		var blocked := LosCheck.is_blocked(main_pos, other_pos)
		var los_color := "yellow" if blocked else "red"
		var label := "Enemy %d" if other.team == Satellite.TEAM_ENEMY else "Target %d"
		lines.append("[color=%s]%s[/color]" % [los_color, label % i])
		lines.append("  HP: %.0f / %.0f" % [other.hp, Satellite.MAX_HP])
		lines.append("  Distance: %.0f km" % distance)
		lines.append("  delta-V: %.2f km/s" % rel_vel)
		lines.append("  LOS: %s" % ("BLOCKED" if blocked else "CLEAR"))

	lines.append("[/font_size]")
	info_label.text = "\n".join(lines)


func draw_target_lines(orbital_set: Node, cam: Camera3D) -> void:
	_camera = cam
	_system = orbital_set
	queue_redraw()


func _draw() -> void:
	if _system == null or _camera == null:
		return
	var satellites: Array = _system.satellites
	var selected_idx: int = (
		_system.planning_selected if _system.planning_mode
		else _system.selected_ship
	)
	if satellites.is_empty() or selected_idx < 0 or selected_idx >= satellites.size():
		return
	var selected: Satellite = satellites[selected_idx]
	if not selected.orbit_alive or not selected.alive:
		return
	var main_eci := selected.orbit.r
	var main_scene := main_eci * Satellite.SCENE_SCALE

	for i in range(satellites.size()):
		if i == selected_idx:
			continue
		var other: Satellite = satellites[i]
		if not other.orbit_alive or not other.alive:
			continue
		var other_scene := other.orbit.r * Satellite.SCENE_SCALE
		if _camera.is_position_behind(main_scene) and _camera.is_position_behind(other_scene):
			continue
		var screen_a := _camera.unproject_position(main_scene)
		var screen_b := _camera.unproject_position(other_scene)
		var blocked := LosCheck.is_blocked(main_eci, other.orbit.r)
		var line_color := Color.YELLOW if blocked else Color.RED
		draw_line(screen_a, screen_b, line_color, 1.0)
