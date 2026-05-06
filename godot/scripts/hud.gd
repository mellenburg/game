class_name HUD
extends Control
## Roster + targeting overlay. Player units render as green-tinted
## panels along the top-left and surface HP / energy / cooldown rows.
## The bottom-left slot that previously hosted enemy status boxes is
## now driven by TessellationGrid (a separate node) — the HUD no
## longer renders per-enemy panels.
##
## BBCode / panel rebuilds throttle to ~10 Hz; per-frame allocations
## are avoided by reusing children across ticks (we only add/remove
## when the per-team / per-row count changes).

const Satellite = preload("res://scripts/satellite.gd")
const LosCheck = preload("res://scripts/los_check.gd")
const Weapon = preload("res://scripts/weapons/weapon.gd")
const LaserWeapon = preload("res://scripts/weapons/laser_weapon.gd")
const RailgunWeapon = preload("res://scripts/weapons/railgun_weapon.gd")
const SimClock = preload("res://scripts/sim_clock.gd")
const AsteroidPhysics = preload("res://scripts/asteroid_physics.gd")
const EarthOrbit = preload("res://scripts/earth_orbit.gd")
const HPBar = preload("res://scripts/hp_bar.gd")

const HUD_UPDATE_INTERVAL: float = 0.1  # seconds

const PLAYER_BG := Color(0.06, 0.25, 0.10, 0.65)
const PLAYER_BG_SEL := Color(0.20, 0.65, 0.25, 0.90)
# Roster box flash on hit. Red — a damage indicator, distinct from the
# orange used on the 3D marker and BeamRenderer beam so the two
# surfaces don't blur into the same visual signal.
const BOX_HIT_FLASH := Color(0.95, 0.15, 0.15, 0.95)
# Player roster width is fixed so the boxes line up evenly along the
# top strip. Height auto-sizes from the contained HP / energy /
# weapon rows. Enemy boxes don't share this — they're area-scaled.
const BOX_MIN_SIZE := Vector2(105, 0)

# Bar row colors. The energy reservoir is blue; weapon recovery starts
# orange ("recharging") and snaps to green when ready, so a glance
# tells the player which lasers can fire.
const BAR_BG := Color(0.04, 0.04, 0.06, 0.85)
const BAR_ENERGY := Color(0.20, 0.50, 0.95, 0.90)
const BAR_COOLDOWN := Color(0.95, 0.55, 0.10, 0.90)
const BAR_READY := Color(0.25, 0.80, 0.30, 0.90)
# Propellant — purple/magenta, distinct from the cyan engagement-range
# tint and the blue energy fill so the operator can read remaining
# delta-v at a glance without confusing it with the weapon pool. The
# overlay text reports m/s so the number maps directly onto the
# delta-v budget the menu enforces pre-game.
const BAR_PROPELLANT := Color(0.65, 0.35, 0.85, 0.90)
const BAR_ROW_HEIGHT: float = 13.0
const BAR_FONT_SIZE: int = 9

# Fire-control readout — green to match the on-orbit range circle so
# the two surfaces read as the same control surfaced twice. Sized
# slightly smaller than the bar text since it's a single line of meta
# rather than a per-tick gauge.
const FC_TEXT_COLOR := Color(0.55, 0.95, 0.65, 1.0)
const FC_FONT_SIZE: int = 10
const FC_NODE_NAME: String = "FCStatus"

# Targeting-mode readout. Always present on armed player ships (unlike
# the FC line which only shows when fire control is on) — it's a
# persistent gameplay setting, not a toggle-into-an-overlay state. Cyan
# tint is distinct from the FC green so the two single-line meta
# readouts don't blend visually.
const TGT_TEXT_COLOR := Color(0.55, 0.85, 0.95, 1.0)
const TGT_FONT_SIZE: int = 10
const TGT_NODE_NAME: String = "TargetingStatus"

# Railgun readout — orange-tinted to distinguish from the FC green and
# TGT cyan, since this line carries two pieces of state (on/off + max
# orbital radius cap). Only present on armed player ships that carry
# at least one railgun; unarmed bodies and laser-only loadouts skip it.
const RG_TEXT_COLOR := Color(0.95, 0.65, 0.30, 1.0)
const RG_FONT_SIZE: int = 10
const RG_NODE_NAME: String = "RailgunStatus"

# Unit name header — the operator-facing string set in the Hangar
# editor (e.g. "T-01", "ARTEMIS"). Drawn at the top of every player
# roster box so a glance maps an in-game unit back to the row the
# operator built.
const NAME_NODE_NAME: String = "UnitName"
const NAME_TEXT_COLOR := Color(1.0, 0.706, 0.329, 1.0)  # accent
const NAME_FONT_SIZE: int = 11

const LOS_CLEAR := Color(1.0, 0.95, 0.2)        # yellow
const LOS_BLOCKED := Color(1.0, 0.55, 0.55)     # light red

# Wall-clock duration of the hit pulse on the marker / roster box.
# Wall-clock so the visual feedback survives compression at high
# time_factor — at time_factor=5000 a sim-second is 0.2 ms, which
# would be invisible. The actual beam is drawn by BeamRenderer in 3D;
# this constant only governs how long the box / marker stays tinted.
const HIT_DURATION: float = 0.25

@onready var info_label: RichTextLabel = $InfoLabel as RichTextLabel
@onready var player_roster: HBoxContainer = (
	$PlayerRosters/PlayerRoster as HBoxContainer
)
@onready var surface_player_roster: HBoxContainer = (
	$PlayerRosters/SurfacePlayerRoster as HBoxContainer
)
@onready var target_container: Control = $TargetContainer as Control
@onready var kill_stats: RichTextLabel = $KillStats as RichTextLabel
# Top-right RichTextLabel — used to host the static controls cheatsheet,
# now repurposed as a live status panel for the asteroid the operator
# clicks in the bottom-left tessellation grid. Renders a "no selection"
# placeholder when nothing is highlighted.
@onready var asteroid_status: RichTextLabel = (
	$AsteroidPanel/VBox/HelpLabel as RichTextLabel
)
@onready var asteroid_hp_bar: HPBar = (
	$AsteroidPanel/VBox/HPBar as HPBar
)

var _camera: Camera3D
var _system: Node = null
var _last_text_update: float = 0.0

# Active hit pulses. Drives the roster box red flash and (via
# Satellite.flash_hit) the 3D marker tint. The actual beam visual
# lives in BeamRenderer; this list is just timed metadata for the
# box / marker feedback so it outlives the firing tick.
var _hits: Array[Dictionary] = []
# Driven by EarthSystem from the "toggle_los" input action — true only
# while the V key is held. The yellow / pink LOS lines from the
# selected satellite to opposing units render only during that window;
# hit pulses remain visible regardless.
var los_visible: bool = false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Called by the combat loop when a weapon successfully fires. The HUD
## records the target ref for HIT_DURATION wall-clock seconds so it
## can flash the roster box red, and tells the target to tint its 3D
## marker orange. The 3D beam itself is drawn by BeamRenderer.
func register_hit(_attacker: Satellite, target: Satellite) -> void:
	if target == null:
		return
	_hits.append({
		"target": target,
		"expires_at": _now() + HIT_DURATION,
	})
	target.flash_hit(HIT_DURATION)


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


# Drop hits whose pulse window has expired. Freed targets stay until
# their window elapses — _is_hit_target guards the dereference.
func _prune_hits() -> void:
	var now := _now()
	var live: Array[Dictionary] = []
	for h in _hits:
		var expires: float = h["expires_at"]
		if expires <= now:
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


func update_hud(
	orbital_set: Node,
	planning_mode: bool,
	time_factor: int,
	dt: int,
	sim_time: float,
) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now - _last_text_update < HUD_UPDATE_INTERVAL:
		return
	_last_text_update = now

	_update_info_label(planning_mode, time_factor, dt, sim_time)
	_update_rosters(orbital_set, planning_mode)
	_update_kill_stats(orbital_set)
	var grid_node: Node = null
	if has_node("TessellationGrid"):
		grid_node = get_node("TessellationGrid")
		if grid_node.has_method("update_enemies"):
			grid_node.update_enemies(orbital_set.satellites, sim_time)
	_update_asteroid_status(grid_node, sim_time)


# Render the currently grid-highlighted asteroid into the top-right
# panel. The grid (TessellationGrid in the bottom-left) tracks the
# operator's pick and keeps a Satellite ref alive in `highlighted_sat`;
# we read that here and format mass / density / composition / HP / ETA.
# Falls back to a "click an asteroid" prompt when nothing is selected.
func _update_asteroid_status(grid_node: Node, sim_time: float) -> void:
	if asteroid_status == null:
		return
	var sat: Satellite = null
	if grid_node != null and "highlighted_sat" in grid_node:
		sat = grid_node.highlighted_sat
	if sat == null or not is_instance_valid(sat) or not sat.alive:
		asteroid_status.text = (
			"[font_size=10][color=#5a6470]"
			+ "Asteroid inspector\n"
			+ "Click a tile in the lower-left grid."
			+ "[/color][/font_size]"
		)
		if asteroid_hp_bar != null:
			asteroid_hp_bar.visible = false
		return
	asteroid_status.text = _format_asteroid_status(sat, sim_time)
	if asteroid_hp_bar != null:
		asteroid_hp_bar.visible = true
		asteroid_hp_bar.hp_ratio = (
			sat.hp / sat.max_hp if sat.max_hp > 0.0 else 0.0
		)


# BBCode card for the upper-right asteroid inspector panel. Kept small
# and dim — the panel sits above the orbital sim-info readout, so the
# typography here uses a quieter palette and a smaller body font so the
# operator's eye still lands on the live orbital details first.
func _format_asteroid_status(sat: Satellite, sim_time: float) -> String:
	var lines := PackedStringArray()
	lines.append(
		"[font_size=11][color=#c8b478]◆ ASTEROID[/color][/font_size]"
	)
	lines.append("[font_size=10][color=#7c8896]")
	var kind := "enemy body"
	if sat.is_decaying:
		kind = "decaying-orbit threat"
	elif sat.is_asteroid:
		kind = "sub-orbital asteroid"
	lines.append("[color=#5a6470]type[/color]    %s" % kind)
	lines.append("[color=#5a6470]mass[/color]    %s kg" % _format_scientific(sat.mass))
	lines.append("[color=#5a6470]density[/color] %.2f g/cm³" % sat.density_g_cm3)
	if sat.composition >= 0:
		lines.append(
			"[color=#5a6470]comp[/color]    %s"
			% AsteroidPhysics.composition_name(sat.composition)
		)
	if AsteroidPhysics.is_burn_up(sat.mass):
		lines.append("[color=#6fa07f]burn-up on entry[/color]")
	else:
		var radii: Dictionary = AsteroidPhysics.damage_radii_km(sat.mass)
		lines.append(
			"[color=#5a6470]radii[/color]   H %.0f · M %.0f · L %.0f km" % [
				float(radii["heavy"]),
				float(radii["moderate"]),
				float(radii["light"]),
			]
		)
	var eta := sat.predict_impact_sim_time(sim_time) - sim_time
	var eta_str := "stable"
	if is_finite(eta) and eta > 0.0:
		eta_str = _format_eta(eta)
	lines.append("[color=#5a6470]eta[/color]     %s" % eta_str)
	var alt_km: float = sat.orbit.r.length() - EarthOrbit.EARTH_RADIUS_KM
	lines.append("[color=#5a6470]alt[/color]     %s km" % _format_scientific(alt_km))
	lines.append("[/color][/font_size]")
	return "\n".join(lines)


# Compact mantissa-and-exponent formatter for HUD readouts. Asteroid
# masses span ~8 decades; a fixed-decimals %.0f either wraps lines or
# loses precision on the small end.
func _format_scientific(value: float) -> String:
	if not is_finite(value):
		return "—"
	if absf(value) < 1.0e3:
		return "%.1f" % value
	var sign_str := "" if value >= 0.0 else "-"
	var v := absf(value)
	var exponent: int = int(floor(log(v) / log(10.0)))
	var mantissa: float = v / pow(10.0, exponent)
	return "%s%.2fe%d" % [sign_str, mantissa, exponent]


func _format_eta(seconds: float) -> String:
	# Seconds → h:mm:ss for short windows, days+hours for longer ones,
	# so a 30-second imminent impact and a 12-hour stable approach are
	# both readable at a glance.
	var s: int = int(round(seconds))
	if s < 3600:
		return "%d:%02d" % [s / 60, s % 60]
	if s < 86400:
		var h: int = s / 3600
		var m: int = (s % 3600) / 60
		return "%dh %02dm" % [h, m]
	var d: int = s / 86400
	var hh: int = (s % 86400) / 3600
	return "%dd %02dh" % [d, hh]


func _update_info_label(
	planning_mode: bool, time_factor: int, dt: int, sim_time: float
) -> void:
	if info_label == null:
		return
	var lines := PackedStringArray()
	lines.append("[font_size=14]")
	# UTC clock above the time factor — operator's anchor for "when is
	# the next wave?". Mission schedule and wave timers all run on this
	# clock, so the displayed UTC time is the canonical timestamp.
	lines.append("[color=#9aa9b8]%s[/color]" % SimClock.format_utc(sim_time))
	if planning_mode:
		lines.append("[color=yellow]PLANNING MODE[/color]")
	lines.append("Time Factor: %d" % time_factor)
	if planning_mode:
		lines.append("Planning dt: %d" % dt)
	lines.append("[/font_size]")
	info_label.text = "\n".join(lines)


func _update_kill_stats(orbital_set: Node) -> void:
	if kill_stats == null:
		return
	# Read tallies straight off the controller — no signal plumbing
	# needed; the HUD already polls orbital_set every tick anyway.
	var shot: int = orbital_set.enemies_shot_down
	var hit: int = orbital_set.asteroids_impacted
	# Wave tracker prepended above the eliminated stats. Hidden when
	# the controller has no live mission scheduler (direct main.tscn
	# boot, debug sandbox) — the readout would always read "0/0" in
	# that mode and give the operator nothing to act on.
	var wave_block := ""
	if orbital_set.mission != null and orbital_set.mission.total_waves() > 0:
		var current: int = orbital_set.mission.current_wave_number()
		var total: int = orbital_set.mission.total_waves()
		wave_block = (
			"[font_size=13][color=gray]Current wave[/color] "
			+ "[color=#f5b455]%d/%d[/color][/font_size]\n" % [current, total]
		)
	kill_stats.text = (
		wave_block
		+ "[font_size=13][color=gray]Enemies eliminated[/color]\n"
		+ "[color=#7fcf7f]Shot down:[/color] %d\n" % shot
		+ "[color=#ff8c5a]Impacted:[/color] %d[/font_size]" % hit
	)


func _update_rosters(orbital_set: Node, planning_mode: bool) -> void:
	if player_roster == null:
		return
	var satellites: Array = orbital_set.satellites
	var selected_idx: int = (
		orbital_set.planning_selected if planning_mode
		else orbital_set.selected_ship
	)

	# Player units are partitioned into orbital and surface so the two
	# rosters render as separate rows in the top-left strip — orbital
	# ships above, ground installations below. The selection index
	# tracks separately for each subset so the green tint follows the
	# satellite into whichever row holds it.
	var orbital_players: Array[Satellite] = []
	var surface_players: Array[Satellite] = []
	var orbital_selected_in_roster: int = -1
	var surface_selected_in_roster: int = -1

	for i in range(satellites.size()):
		var sat: Satellite = satellites[i]
		if not sat.alive:
			continue
		if sat.team == Satellite.TEAM_ENEMY:
			continue
		if sat.is_surface:
			if i == selected_idx:
				surface_selected_in_roster = surface_players.size()
			surface_players.append(sat)
		else:
			if i == selected_idx:
				orbital_selected_in_roster = orbital_players.size()
			orbital_players.append(sat)

	_render_player_roster_into(
		player_roster, orbital_players, orbital_selected_in_roster
	)
	if surface_player_roster != null:
		_render_player_roster_into(
			surface_player_roster, surface_players, surface_selected_in_roster
		)
		# Hide the surface row entirely when nothing's placed so the HUD
		# doesn't reserve dead space for an empty container.
		surface_player_roster.visible = not surface_players.is_empty()


# Generic renderer that fills any HBoxContainer with one player-style
# box per sat. Both the orbital and surface rosters share this idiom so
# the per-row UI (selection tint, weapon bars, FC / TGT / RG meta lines)
# stays consistent across both strips.
func _render_player_roster_into(
	host: HBoxContainer, sats: Array[Satellite], selected: int
) -> void:
	while host.get_child_count() < sats.size():
		host.add_child(_make_box())
	while host.get_child_count() > sats.size():
		var stale := host.get_child(host.get_child_count() - 1)
		host.remove_child(stale)
		stale.queue_free()
	for i in range(sats.size()):
		var box := host.get_child(i) as PanelContainer
		_update_box(box, sats[i], i == selected)


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

	var rows := VBoxContainer.new()
	rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rows.add_theme_constant_override("separation", 2)
	box.add_child(rows)

	# Index 0 is the unit-name header (operator-set string from the
	# Hangar editor) and index 1 is the plain HP label. Bar rows for
	# energy + each weapon are added on demand by _update_box so the
	# per-team child count matches the actual satellite (an unarmed
	# enemy gets just name + HP).
	var name_label := Label.new()
	name_label.name = NAME_NODE_NAME
	name_label.add_theme_font_size_override("font_size", NAME_FONT_SIZE)
	name_label.add_theme_color_override("font_color", NAME_TEXT_COLOR)
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rows.add_child(name_label)

	var hp := Label.new()
	hp.add_theme_font_size_override("font_size", 11)
	hp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rows.add_child(hp)

	return box


# A bar row: dark background, color-tinted fill that grows left→right
# with `fraction`, and a centered text overlay that shows the readout
# (e.g. "Energy 25%" or "Laser 1 50%" or "Laser 2 READY").
func _make_bar_row() -> Control:
	var row := Control.new()
	row.custom_minimum_size = Vector2(0, BAR_ROW_HEIGHT)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.clip_contents = true

	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = BAR_BG
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(bg)

	# Anchor-driven fill: anchor_right is the fraction we want filled,
	# so we never need to know the row's pixel width to scale it.
	var fill := ColorRect.new()
	fill.anchor_left = 0.0
	fill.anchor_top = 0.0
	fill.anchor_right = 0.0
	fill.anchor_bottom = 1.0
	fill.color = BAR_ENERGY
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(fill)

	var overlay := Label.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	overlay.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	overlay.add_theme_font_size_override("font_size", BAR_FONT_SIZE)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(overlay)

	return row


func _make_fc_label() -> Label:
	var l := Label.new()
	l.name = FC_NODE_NAME
	l.add_theme_font_size_override("font_size", FC_FONT_SIZE)
	l.add_theme_color_override("font_color", FC_TEXT_COLOR)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _make_targeting_label() -> Label:
	var l := Label.new()
	l.name = TGT_NODE_NAME
	l.add_theme_font_size_override("font_size", TGT_FONT_SIZE)
	l.add_theme_color_override("font_color", TGT_TEXT_COLOR)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _make_railgun_label() -> Label:
	var l := Label.new()
	l.name = RG_NODE_NAME
	l.add_theme_font_size_override("font_size", RG_FONT_SIZE)
	l.add_theme_color_override("font_color", RG_TEXT_COLOR)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _update_bar_row(row: Control, fill_color: Color, text: String, fraction: float) -> void:
	var fill := row.get_child(1) as ColorRect
	if fill != null:
		fill.color = fill_color
		fill.anchor_right = clampf(fraction, 0.0, 1.0)
	var overlay := row.get_child(2) as Label
	if overlay != null:
		overlay.text = text


func _update_box(
	box: PanelContainer,
	sat: Satellite,
	is_selected: bool,
) -> void:
	var sb := box.get_theme_stylebox("panel") as StyleBoxFlat
	if sb != null:
		if _is_hit_target(sat):
			sb.bg_color = BOX_HIT_FLASH
		else:
			sb.bg_color = PLAYER_BG_SEL if is_selected else PLAYER_BG

	var rows := box.get_child(0) as VBoxContainer
	if rows == null:
		return

	# Index 0 is the unit-name header, index 1 the HP label; bar rows
	# follow; an optional FC status label and targeting-mode label tail
	# the box. Detach all three meta labels first so the bar-resize
	# loop's child-count math stays clean — we re-append (or drop)
	# them after the bars settle.
	var name_label := rows.get_node_or_null(NAME_NODE_NAME) as Label
	if name_label != null:
		# Empty unit_name (legacy / unnamed) collapses the row by hiding
		# the label so the box doesn't carry a blank line.
		var has_name := sat.unit_name != ""
		name_label.visible = has_name
		if has_name:
			name_label.text = sat.unit_name
	var hp_label := rows.get_child(1) as Label
	if hp_label != null:
		hp_label.text = "HP %d/%d" % [int(sat.hp), int(sat.max_hp)]

	var fc_label := rows.get_node_or_null(FC_NODE_NAME) as Label
	if fc_label != null:
		rows.remove_child(fc_label)
	var tgt_label := rows.get_node_or_null(TGT_NODE_NAME) as Label
	if tgt_label != null:
		rows.remove_child(tgt_label)
	var rg_label := rows.get_node_or_null(RG_NODE_NAME) as Label
	if rg_label != null:
		rows.remove_child(rg_label)

	# Bars below the name + HP rows, in display order:
	#   [energy] [propellant] [weapon 0..N]
	# Energy is gated on the unit being armed; propellant on the unit
	# being a player orbital ship with a non-zero tank (surface
	# installations and enemies skip it — they don't burn propellant
	# in the maneuver branch). Each gate maps to a flag so the
	# rendering loop below can compute its slot index without a tangle
	# of conditional offsets.
	var has_energy_bar := not sat.weapons.is_empty()
	var has_propellant_bar := (
		sat.team == Satellite.TEAM_PLAYER
		and not sat.is_surface
		and sat.max_propellant_kg > 0.0
	)
	var desired_bars := sat.weapons.size()
	if has_energy_bar:
		desired_bars += 1
	if has_propellant_bar:
		desired_bars += 1
	# Two fixed rows above the bars (name + HP) — subtract both from
	# the current child count so the bar-resize loop targets only the
	# bar rows.
	var current_bars := rows.get_child_count() - 2
	while current_bars < desired_bars:
		rows.add_child(_make_bar_row())
		current_bars += 1
	while current_bars > desired_bars:
		var stale := rows.get_child(rows.get_child_count() - 1)
		rows.remove_child(stale)
		stale.queue_free()
		current_bars -= 1

	# Reattach (or drop) the FC label after the bars are in their
	# final shape. Fire control adjusts engagement_range_km, which is
	# read only by the laser, so the line is gated on the satellite
	# carrying at least one laser — railgun-only ships don't render
	# it even if some upstream code flipped fire_control_active.
	var has_laser := sat.has_laser()
	var want_fc := sat.fire_control_active and has_laser
	if want_fc:
		if fc_label == null:
			fc_label = _make_fc_label()
		fc_label.text = "FC ON  %d km" % int(round(sat.engagement_range_km))
		rows.add_child(fc_label)
	elif fc_label != null:
		fc_label.queue_free()

	# Targeting mode (MAX DAMAGE / MAX DANGER) is a laser-only setting
	# — the railgun ignores attacker.targeting_mode and picks randomly
	# from in-envelope LOS targets. Show the line only on satellites
	# that actually carry a laser; railgun-only ships skip it.
	if has_laser:
		if tgt_label == null:
			tgt_label = _make_targeting_label()
		tgt_label.text = (
			"TGT MAX DANGER" if sat.targeting_mode == LaserWeapon.TARGETING_MAX_DANGER
			else "TGT MAX DAMAGE"
		)
		rows.add_child(tgt_label)
	elif tgt_label != null:
		tgt_label.queue_free()

	# Railgun status — only on satellites that carry at least one
	# railgun. Two readouts on one line: ON/OFF gate (X) and the
	# operator-set max orbital radius cap (Shift+Left/Right). Players
	# without a railgun never see this row.
	if sat.has_railgun():
		if rg_label == null:
			rg_label = _make_railgun_label()
		var on_text: String = "ON" if sat.railgun_enabled else "OFF"
		rg_label.text = "RG %s  MAX R %d km" % [
			on_text, int(round(sat.max_orbital_radius_km))
		]
		rows.add_child(rg_label)
	elif rg_label != null:
		rg_label.queue_free()

	if desired_bars == 0:
		return

	# Bar rows live at index 2..; the slot order matches the flags
	# set above (energy → propellant → weapons). Track a running
	# index so any combination of present/absent bars indexes
	# correctly without a tangle of conditional offsets.
	var bar_idx := 2
	if has_energy_bar:
		var energy_row := rows.get_child(bar_idx) as Control
		if energy_row != null:
			var frac: float = (
				sat.energy / sat.energy_max if sat.energy_max > 0.0 else 0.0
			)
			_update_bar_row(
				energy_row,
				BAR_ENERGY,
				"Energy  %s / %s" % [
					_format_joules(sat.energy),
					_format_joules(sat.energy_max),
				],
				frac,
			)
		bar_idx += 1
	if has_propellant_bar:
		var prop_row := rows.get_child(bar_idx) as Control
		if prop_row != null:
			var dv_ms: float = sat.delta_v_remaining_ms()
			# Fraction is propellant remaining vs. tank capacity — the
			# bar drains as the unit burns, even though the m/s
			# readout overlaid on it is non-linear in propellant (the
			# rocket equation's logarithm). Players see "tank empties"
			# and "delta-v shrinks" simultaneously, which is the
			# correct shared mental model.
			var frac: float = (
				sat.propellant_kg / sat.max_propellant_kg
				if sat.max_propellant_kg > 0.0 else 0.0
			)
			_update_bar_row(
				prop_row, BAR_PROPELLANT,
				"Δv  %d m/s" % int(round(dv_ms)), frac,
			)
		bar_idx += 1

	# Per-type counter so multiple lasers number 1, 2, 3 while a single
	# railgun reads as just "Railgun" (no index). Keeps the bar text
	# sensible regardless of how the weapon array is composed.
	var per_type_idx: Dictionary = {}
	var per_type_total: Dictionary = {}
	for w_count: Weapon in sat.weapons:
		var n := w_count.display_name()
		per_type_total[n] = int(per_type_total.get(n, 0)) + 1
	for i in range(sat.weapons.size()):
		var w: Weapon = sat.weapons[i]
		var row := rows.get_child(bar_idx + i) as Control
		if row == null:
			continue
		var prog := w.ready_progress()
		var pct := int(round(prog * 100.0))
		var name := w.display_name()
		var idx := int(per_type_idx.get(name, 0)) + 1
		per_type_idx[name] = idx
		var label := name
		if int(per_type_total[name]) > 1:
			label = "%s %d" % [name, idx]
		# Railgun rows append the magazine count so the operator sees
		# both readiness and ammo remaining on a single line. Lasers
		# don't carry ammo, so the suffix is railgun-only.
		var ammo_suffix: String = ""
		if w is RailgunWeapon:
			var rg: RailgunWeapon = w
			ammo_suffix = "  %d/%d" % [rg.ammo_count, RailgunWeapon.MAGAZINE_SIZE]
		# Three states: OVERHEAT (locked, cooling back to 100%), READY
		# (full and unlocked), or partial (firing or recovering toward
		# READY without having tripped the lockout). The railgun's
		# single-shot semantics use the same overheated latch as the
		# laser, so this branch handles both weapon types cleanly.
		# Empty magazine overrides the cooldown label — a cool railgun
		# with no rounds reads as EMPTY, not READY.
		var text: String
		var fill_color: Color
		if w is RailgunWeapon and (w as RailgunWeapon).ammo_count <= 0:
			text = "%s  EMPTY%s" % [label, ammo_suffix]
			fill_color = BAR_COOLDOWN
		elif w.overheated:
			text = "%s  COOLDOWN %d%%%s" % [label, pct, ammo_suffix]
			fill_color = BAR_COOLDOWN
		elif prog >= 1.0:
			text = "%s  READY%s" % [label, ammo_suffix]
			fill_color = BAR_READY
		else:
			text = "%s  %d%%%s" % [label, pct, ammo_suffix]
			fill_color = BAR_COOLDOWN
		_update_bar_row(row, fill_color, text, prog)


func draw_target_lines(orbital_set: Node, cam: Camera3D) -> void:
	_camera = cam
	_system = orbital_set
	queue_redraw()


func _draw() -> void:
	if _system == null or _camera == null:
		return
	_prune_hits()
	if los_visible:
		_draw_selected_los_lines()


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


# Joules → human-readable energy. Uses GJ above 10^9 J, MJ above
# 10^6 J, kJ above 10^3 J, otherwise raw J. Mirrors menu.gd's
# _format_joules so the in-game HUD and the pre-game Hangar summary
# read the same units.
func _format_joules(joules: float) -> String:
	if joules >= 1.0e9:
		return "%.1f GJ" % (joules * 1.0e-9)
	if joules >= 1.0e6:
		return "%.1f MJ" % (joules * 1.0e-6)
	if joules >= 1.0e3:
		return "%.1f kJ" % (joules * 1.0e-3)
	return "%.0f J" % joules
