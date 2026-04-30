class_name HUD
extends Control
## Roster + targeting overlay. Player units render as green-tinted boxes
## along the top-left, enemies as red-tinted boxes along the bottom-left,
## both growing rightward. Each box surfaces only HP / energy / cooldown
## — orbital metadata is intentionally hidden but still reachable on the
## Satellite for future on-demand drill-downs.
##
## BBCode rebuilds throttle to ~10 Hz; per-frame allocations are avoided
## by reusing PanelContainer children across ticks (we only add/remove
## when the per-team count changes).

const Satellite = preload("res://scripts/satellite.gd")
const LosCheck = preload("res://scripts/los_check.gd")

const HUD_UPDATE_INTERVAL: float = 0.1  # seconds

const PLAYER_BG := Color(0.06, 0.25, 0.10, 0.65)
const PLAYER_BG_SEL := Color(0.20, 0.65, 0.25, 0.90)
const ENEMY_BG := Color(0.30, 0.06, 0.06, 0.65)
const ENEMY_BG_SEL := Color(0.85, 0.20, 0.20, 0.90)
# Roster box flash on hit. Red — a damage indicator, distinct from the
# orange used on the 3D marker / line so the two surfaces don't blur
# into the same visual signal.
const BOX_HIT_FLASH := Color(0.95, 0.15, 0.15, 0.95)
const BOX_MIN_SIZE := Vector2(96, 60)

const LOS_CLEAR := Color(1.0, 0.95, 0.2)        # yellow
const LOS_BLOCKED := Color(1.0, 0.55, 0.55)     # light red
const HIT_LINE := Color(1.0, 0.55, 0.0)         # orange
const HIT_LINE_WIDTH: float = 2.5

# Wall-clock duration of the hit pulse. Wall-clock (not sim-seconds) so
# the visual feedback survives compression at high time_factor — at
# time_factor=5000 a sim-second is 0.2 ms, which would be invisible.
# 0.25 s is long enough to register, short enough to feel like a hit.
const HIT_DURATION: float = 0.25

@onready var info_label: RichTextLabel = $InfoLabel as RichTextLabel
@onready var player_roster: HBoxContainer = $PlayerRoster as HBoxContainer
@onready var enemy_roster: HBoxContainer = $EnemyRoster as HBoxContainer
@onready var target_container: Control = $TargetContainer as Control

var _camera: Camera3D
var _system: Node = null
var _last_text_update: float = 0.0

# Active weapon-hit pulses. Each entry: {attacker, target, expires_at}
# where expires_at is wall-clock seconds. Pruned lazily during render.
var _hits: Array[Dictionary] = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Called by the combat loop when a weapon successfully fires. The HUD
## records the (attacker, target) pair for HIT_DURATION wall-clock
## seconds so it can paint a hit pulse in the next frame's _draw, and
## tells the target to flash its 3D marker orange.
func register_hit(attacker: Satellite, target: Satellite) -> void:
	if attacker == null or target == null:
		return
	_hits.append({
		"attacker": attacker,
		"target": target,
		"expires_at": _now() + HIT_DURATION,
	})
	target.flash_hit(HIT_DURATION)


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


# Drop expired hits and any whose attacker/target has been freed (a
# satellite can die between a fire() and the next render tick).
#
# Important: we DON'T pull h["attacker"] / h["target"] into a typed
# `Satellite` local until after is_instance_valid passes. Godot 4
# rejects the assignment of a freed Object to a typed variable with
# "Trying to assign invalid previously freed instance" — the check
# fires before any user-level guard could run. Passing the dict
# expression straight into is_instance_valid sidesteps that.
func _prune_hits() -> void:
	var now := _now()
	var live: Array[Dictionary] = []
	for h in _hits:
		var expires: float = h["expires_at"]
		if expires <= now:
			continue
		if not is_instance_valid(h["attacker"]):
			continue
		if not is_instance_valid(h["target"]):
			continue
		live.append(h)
	_hits = live


func _is_hit_target(sat: Satellite) -> bool:
	for h in _hits:
		if not is_instance_valid(h["target"]):
			continue
		if h["target"] == sat:
			return true
	return false


func update_hud(orbital_set: Node, planning_mode: bool, time_factor: int, dt: int) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now - _last_text_update < HUD_UPDATE_INTERVAL:
		return
	_last_text_update = now

	_update_info_label(planning_mode, time_factor, dt)
	_update_rosters(orbital_set, planning_mode)


func _update_info_label(planning_mode: bool, time_factor: int, dt: int) -> void:
	if info_label == null:
		return
	var lines := PackedStringArray()
	lines.append("[font_size=14]")
	if planning_mode:
		lines.append("[color=yellow]PLANNING MODE[/color]")
	lines.append("Time Factor: %d" % time_factor)
	if planning_mode:
		lines.append("Planning dt: %d" % dt)
	lines.append("[/font_size]")
	info_label.text = "\n".join(lines)


func _update_rosters(orbital_set: Node, planning_mode: bool) -> void:
	if player_roster == null or enemy_roster == null:
		return
	var satellites: Array = orbital_set.satellites
	var selected_idx: int = (
		orbital_set.planning_selected if planning_mode
		else orbital_set.selected_ship
	)

	var players: Array[Satellite] = []
	var enemies: Array[Satellite] = []
	var player_selected_in_roster: int = -1
	var enemy_selected_in_roster: int = -1

	for i in range(satellites.size()):
		var sat: Satellite = satellites[i]
		if not sat.alive:
			continue
		if sat.team == Satellite.TEAM_ENEMY:
			if i == selected_idx:
				enemy_selected_in_roster = enemies.size()
			enemies.append(sat)
		else:
			if i == selected_idx:
				player_selected_in_roster = players.size()
			players.append(sat)

	_render_roster(player_roster, players, player_selected_in_roster, false)
	_render_roster(enemy_roster, enemies, enemy_selected_in_roster, true)


func _render_roster(
	roster: HBoxContainer,
	sats: Array[Satellite],
	selected: int,
	is_enemy: bool
) -> void:
	while roster.get_child_count() < sats.size():
		roster.add_child(_make_box())
	while roster.get_child_count() > sats.size():
		var stale := roster.get_child(roster.get_child_count() - 1)
		roster.remove_child(stale)
		stale.queue_free()
	for i in range(sats.size()):
		var box := roster.get_child(i) as PanelContainer
		_update_box(box, sats[i], i == selected, is_enemy)


func _make_box() -> PanelContainer:
	var box := PanelContainer.new()
	box.custom_minimum_size = BOX_MIN_SIZE
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Per-box StyleBoxFlat so we can mutate bg_color in place rather than
	# reallocating on every selection change.
	var sb := StyleBoxFlat.new()
	sb.bg_color = PLAYER_BG
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 6
	sb.content_margin_right = 6
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	box.add_theme_stylebox_override("panel", sb)
	var label := RichTextLabel.new()
	label.bbcode_enabled = true
	label.scroll_active = false
	label.fit_content = true
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(label)
	return box


func _update_box(
	box: PanelContainer,
	sat: Satellite,
	is_selected: bool,
	is_enemy: bool
) -> void:
	var sb := box.get_theme_stylebox("panel") as StyleBoxFlat
	if sb != null:
		if _is_hit_target(sat):
			sb.bg_color = BOX_HIT_FLASH
		elif is_enemy:
			sb.bg_color = ENEMY_BG_SEL if is_selected else ENEMY_BG
		else:
			sb.bg_color = PLAYER_BG_SEL if is_selected else PLAYER_BG
	var label := box.get_child(0) as RichTextLabel
	if label == null:
		return
	var lines := PackedStringArray()
	lines.append("[font_size=11]")
	lines.append("HP %d/%d" % [int(sat.hp), int(Satellite.MAX_HP)])
	if sat.weapon != null:
		lines.append("E %d%%" % int(sat.weapon.energy * 100.0))
		if sat.weapon.cooldown_remaining > 0.0:
			lines.append(
				"[color=orange]CD %ds[/color]"
				% int(ceil(sat.weapon.cooldown_remaining))
			)
	lines.append("[/font_size]")
	label.text = "\n".join(lines)


func draw_target_lines(orbital_set: Node, cam: Camera3D) -> void:
	_camera = cam
	_system = orbital_set
	queue_redraw()


func _draw() -> void:
	if _system == null or _camera == null:
		return
	_prune_hits()
	_draw_selected_los_lines()
	# Hit lines are drawn last so they overwrite any selection line that
	# happens to share the same endpoints.
	_draw_hit_lines()


# From the selected satellite, draw a line to every opposing-team unit:
# yellow when LOS is clear, light red when blocked. Same-team pairs get
# no line — that was clutter and conflicted with the new combat focus.
func _draw_selected_los_lines() -> void:
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
		if other.team == selected.team:
			continue
		var other_scene := other.orbit.r * Satellite.SCENE_SCALE
		if _camera.is_position_behind(main_scene) and _camera.is_position_behind(other_scene):
			continue
		var screen_a := _camera.unproject_position(main_scene)
		var screen_b := _camera.unproject_position(other_scene)
		var blocked := LosCheck.is_blocked(main_eci, other.orbit.r)
		var line_color := LOS_BLOCKED if blocked else LOS_CLEAR
		draw_line(screen_a, screen_b, line_color, 1.0)


func _draw_hit_lines() -> void:
	for h in _hits:
		# Same freed-instance trap as _prune_hits — validate before
		# pulling the dict values into typed locals.
		if not is_instance_valid(h["attacker"]):
			continue
		if not is_instance_valid(h["target"]):
			continue
		var attacker: Satellite = h["attacker"]
		var target: Satellite = h["target"]
		if not attacker.alive or not target.alive:
			continue
		if not attacker.orbit_alive or not target.orbit_alive:
			continue
		var a_scene := attacker.orbit.r * Satellite.SCENE_SCALE
		var b_scene := target.orbit.r * Satellite.SCENE_SCALE
		if _camera.is_position_behind(a_scene) and _camera.is_position_behind(b_scene):
			continue
		var screen_a := _camera.unproject_position(a_scene)
		var screen_b := _camera.unproject_position(b_scene)
		draw_line(screen_a, screen_b, HIT_LINE, HIT_LINE_WIDTH)
