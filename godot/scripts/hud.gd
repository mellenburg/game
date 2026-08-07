class_name HUD
extends Control
## Roster + targeting overlay. Player units render as small clickable
## tiles along the top strip (orbital row above, surface row below);
## each tile shows just the operator-set name and a row of small
## weapon icons. Detailed state (HP, energy, propellant, weapon
## readiness, FC / TGT / RG) lives in the upper-right detail panel and
## tracks the currently selected unit. The bottom-left slot is driven
## by TessellationGrid (a separate node) — the HUD no longer renders
## per-enemy panels. The bottom-right slot cycles through the surface
## impact map, wave radar, and asteroid inspector.
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
const MassCenterOrbit = preload("res://scripts/mass_center_orbit.gd")
const HPBar = preload("res://scripts/hp_bar.gd")

## Emitted when the operator clicks a friendly roster tile. MassCenterSystem
## owns the selection index and resolves the satellite ref against the
## active (real or planning) array.
signal friendly_clicked(sat: Satellite)

const HUD_UPDATE_INTERVAL: float = 0.1  # seconds

const PLAYER_BG := Color(0.06, 0.25, 0.10, 0.65)
const PLAYER_BG_SEL := Color(0.20, 0.65, 0.25, 0.90)
# Roster box flash on hit. Red — a damage indicator, distinct from the
# orange used on the 3D marker and BeamRenderer beam so the two
# surfaces don't blur into the same visual signal.
const BOX_HIT_FLASH := Color(0.95, 0.15, 0.15, 0.95)
# Square tiles — name on top, weapon icons below. Detailed state
# (HP, energy, weapon readiness, FC / TGT / RG) has moved to the
# upper-right detail panel, so the per-tile footprint shrank to fit
# more units along the strip without wrapping.
const BOX_MIN_SIZE := Vector2(78, 60)

# Detail-panel bar / status colors. Reused by the upper-right unit
# detail block: blue energy reservoir, purple/magenta propellant, and
# the orange/green weapon-readiness states. Bar visuals are inline in
# the detail BBCode now — the per-tile bars are gone — but the palette
# stayed where the rest of the HUD already references it.
const BAR_ENERGY := Color(0.20, 0.50, 0.95, 0.90)
const BAR_COOLDOWN := Color(0.95, 0.55, 0.10, 0.90)
const BAR_READY := Color(0.25, 0.80, 0.30, 0.90)
const BAR_PROPELLANT := Color(0.65, 0.35, 0.85, 0.90)

# Detail-panel meta colours. Match the legacy per-tile FC / TGT / RG
# tints so the operator's color memory carries over from the old box
# layout: green for fire control, cyan for targeting, orange for the
# railgun gate.
const FC_TEXT_COLOR := Color(0.55, 0.95, 0.65, 1.0)
const TGT_TEXT_COLOR := Color(0.55, 0.85, 0.95, 1.0)
const RG_TEXT_COLOR := Color(0.95, 0.65, 0.30, 1.0)

# Unit name header — the operator-facing string set in the Hangar
# editor (e.g. "T-01", "ARTEMIS"). Drawn at the top of every player
# roster tile so a glance maps an in-game unit back to the row the
# operator built.
const NAME_NODE_NAME: String = "UnitName"
const ICONS_NODE_NAME: String = "WeaponIcons"
const NAME_TEXT_COLOR := Color(1.0, 0.706, 0.329, 1.0)  # accent
const NAME_FONT_SIZE: int = 11

# Weapon icon palette. Each tile draws one small square per equipped
# weapon, tinted by the weapon's class — blue for lasers, orange for
# railguns. The single-character glyph centred inside is redundant
# with the colour but reads clearly even at a glance under heavy
# combat clutter.
const WEAPON_ICON_SIZE := Vector2(15.0, 15.0)
const WEAPON_ICON_LASER := Color(0.20, 0.50, 0.95, 0.95)
const WEAPON_ICON_RAILGUN := Color(0.95, 0.55, 0.10, 0.95)
const WEAPON_ICON_FONT_SIZE: int = 10
const WEAPON_ICON_TEXT_COLOR := Color(1.0, 1.0, 1.0, 1.0)

const LOS_CLEAR := Color(1.0, 0.95, 0.2)        # yellow
const LOS_BLOCKED := Color(1.0, 0.55, 0.55)     # light red

# Group bucketing. The assignment from satellite → group is arbitrary
# placeholder logic (laser / railgun / surface), centralised in
# `_group_for()` so customisation later swaps one helper without
# touching the render flow.
const GROUP_LASER: int = 1
const GROUP_RAILGUN: int = 2
const GROUP_SURFACE: int = 3
const GROUP_NAMES: Dictionary = {
	GROUP_LASER: "Group 1",
	GROUP_RAILGUN: "Group 2",
	GROUP_SURFACE: "Group 3",
}
# Render order top-to-bottom. Groups not in this list won't appear
# even if `_group_for()` returns them, so the list is the source of
# truth for "which groups exist".
const GROUP_ORDER: Array[int] = [GROUP_LASER, GROUP_RAILGUN, GROUP_SURFACE]
const GROUP_HEADER_BG := Color(0.10, 0.30, 0.45, 0.80)
const GROUP_HEADER_BG_EXPANDED := Color(0.20, 0.55, 0.80, 0.90)
const GROUP_HEADER_FONT_SIZE: int = 12
const GROUP_HEADER_MIN_SIZE := Vector2(160.0, 28.0)
const GROUP_HEADER_NAME: String = "GroupHeader"
const GROUP_UNITS_NAME: String = "GroupUnits"
const GROUP_LABEL_NAME: String = "HeaderLabel"

# Wall-clock duration of the hit pulse on the marker / roster box.
# Wall-clock so the visual feedback survives compression at high
# time_factor — at time_factor=5000 a sim-second is 0.2 ms, which
# would be invisible. The actual beam is drawn by BeamRenderer in 3D;
# this constant only governs how long the box / marker stays tinted.
const HIT_DURATION: float = 0.25

@onready var info_label: RichTextLabel = $InfoLabel as RichTextLabel
# Top-left strip host: VBoxContainer populated at runtime with one
# GroupBlock per non-empty group (header tile + unit row). Each group
# is independently collapsed / expanded by clicking its header.
@onready var groups_host: VBoxContainer = (
	$PlayerRosters as VBoxContainer
)
@onready var target_container: Control = $TargetContainer as Control
@onready var kill_stats: RichTextLabel = $KillStats as RichTextLabel
# Asteroid inspector — moved from the upper-right slot into the lower-
# right map cycle. MassCenterSystem flips visibility on the panel via
# `asteroid_panel`; this script just renders into the contained label
# / HP bar each tick so the readout stays fresh whether or not the
# panel is currently showing.
@onready var asteroid_panel: PanelContainer = (
	$AsteroidPanel as PanelContainer
)
@onready var asteroid_status: RichTextLabel = (
	$AsteroidPanel/VBox/HelpLabel as RichTextLabel
)
@onready var asteroid_hp_bar: HPBar = (
	$AsteroidPanel/VBox/HPBar as HPBar
)
# Upper-right unit inspector. Tracks the currently selected friendly
# satellite (Tab cycles, click on a tile selects directly). Hidden
# whenever the selection isn't a player unit so an empty box never
# steals visual real estate from the map cycle below.
@onready var unit_detail_panel: PanelContainer = (
	$UnitDetailPanel as PanelContainer
)
@onready var unit_detail_label: RichTextLabel = (
	$UnitDetailPanel/VBox/DetailLabel as RichTextLabel
)
# Bottom-left enemy grid, resolved once — update_hud runs at 10 Hz and
# MassCenterSystem polls every frame, so the repeated string-path
# get_node lookups were pure overhead. Kept loosely typed (Control +
# has_method guards) so the HUD still boots in scenes without the grid.
@onready var tess_grid: Control = (
	get_node_or_null("TessellationGrid") as Control
)

var _camera: Camera3D
var _system: Node = null
var _last_text_update: float = 0.0

# Expansion state per group index (group_id → bool). Absent / false
# means collapsed (only the header tile renders); true means the unit
# row is visible below the header. State is operator-driven via the
# header click handler.
var _expanded_groups: Dictionary = {}

# Active hit pulses. Drives the roster box red flash and (via
# Satellite.flash_hit) the 3D marker tint. The actual beam visual
# lives in BeamRenderer; this list is just timed metadata for the
# box / marker feedback so it outlives the firing tick.
var _hits: Array[Dictionary] = []
# Driven by MassCenterSystem from the "toggle_los" input action — true only
# while the V key is held. The yellow / pink LOS lines from the
# selected satellite to opposing units render only during that window;
# hit pulses remain visible regardless.
var los_visible: bool = false
# Whether the previous frame painted LOS lines. One extra redraw after
# the operator releases V clears the last set of lines off the canvas.
var _los_drawn_prev: bool = false


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

	# Expire hit pulses at the same cadence the roster boxes that read
	# them are refreshed — pruning used to ride the per-frame _draw,
	# but nothing samples _hits more often than this rebuild.
	_prune_hits()
	_update_info_label(planning_mode, time_factor, dt, sim_time)
	_update_groups(orbital_set, planning_mode)
	_update_kill_stats(orbital_set)
	_update_unit_detail(orbital_set, planning_mode)
	if tess_grid != null and tess_grid.has_method("update_enemies"):
		tess_grid.update_enemies(orbital_set.satellites, sim_time)
	_update_asteroid_status(tess_grid, sim_time)


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
	if sat.is_deflected:
		kind = "deflecting fragment"
	elif sat.is_stable_orbit:
		kind = "stable-orbit fragment"
	elif sat.is_decaying:
		kind = "decaying-orbit threat"
	elif sat.is_asteroid:
		kind = "sub-orbital asteroid"
	lines.append("[color=#5a6470]type[/color]    %s" % kind)
	# Numeric HP alongside the bar visual below — the bar conveys a
	# ratio, but the operator needs the digit count to read whether
	# their fire is actively chipping HP off rather than just nicking
	# it. Format the same way the friendly detail panel reports
	# damage tallies.
	lines.append(
		"[color=#5a6470]hp[/color]      %s / %s" % [
			_format_scientific(maxf(sat.hp, 0.0)),
			_format_scientific(maxf(sat.max_hp, 0.0)),
		]
	)
	lines.append("[color=#5a6470]mass[/color]    %s kg" % _format_scientific(sat.mass))
	lines.append("[color=#5a6470]density[/color] %.2f g/cm³" % sat.density_g_cm3)
	if sat.composition >= 0:
		lines.append(
			"[color=#5a6470]comp[/color]    %s"
			% AsteroidPhysics.composition_name(sat.composition)
		)
	if not sat.is_deflected and not sat.is_stable_orbit:
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
	var eta_str: String = "escaping" if sat.is_deflected else "stable"
	var eta := sat.predict_impact_sim_time(sim_time) - sim_time
	if is_finite(eta) and eta > 0.0:
		eta_str = _format_eta(eta)
	lines.append("[color=#5a6470]eta[/color]     %s" % eta_str)
	var alt_km: float = sat.orbit.r.length() - MassCenterOrbit.BODY_RADIUS_KM
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
		# Projected UTC = paused-clock + scrub window. Lets the operator
		# read the planning preview's time directly instead of mentally
		# summing sim_time and planning_dt.
		lines.append(
			"[color=#f5b455]→ %s[/color]"
			% SimClock.format_utc(sim_time + float(dt))
		)
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


func _update_groups(orbital_set: Node, planning_mode: bool) -> void:
	if groups_host == null:
		return
	var satellites: Array = orbital_set.satellites
	var selected_idx: int = (
		orbital_set.planning_selected if planning_mode
		else orbital_set.selected_ship
	)
	# Live selection ref. Selection tint follows the satellite into
	# whichever group bucket holds it; comparing refs instead of indices
	# avoids tracking per-group local offsets.
	var selected_sat: Satellite = null
	if selected_idx >= 0 and selected_idx < satellites.size():
		var maybe: Satellite = satellites[selected_idx]
		if (
			maybe != null
			and maybe.alive
			and maybe.team == Satellite.TEAM_PLAYER
		):
			selected_sat = maybe

	# Bucket friendlies by group_id. Empty groups simply don't get
	# a header so the strip never reserves dead space for them
	# (matches the prior surface-row visibility behaviour).
	var buckets: Dictionary = {}
	for g_id_init: int in GROUP_ORDER:
		var empty: Array[Satellite] = []
		buckets[g_id_init] = empty
	for i in range(satellites.size()):
		var sat: Satellite = satellites[i]
		if not sat.alive:
			continue
		if sat.team == Satellite.TEAM_ENEMY:
			continue
		var g := _group_for(sat)
		if not buckets.has(g):
			continue
		var lst: Array[Satellite] = buckets[g]
		lst.append(sat)

	var visible_groups: Array[int] = []
	for g_id: int in GROUP_ORDER:
		var bucket: Array[Satellite] = buckets[g_id]
		if not bucket.is_empty():
			visible_groups.append(g_id)

	# Flat layout: each group occupies two adjacent children of the
	# host VBox — a clickable header followed by an HFlow of unit
	# tiles. Earlier revisions wrapped each pair in an extra
	# VBoxContainer, which made the inner HFlow over-report its
	# min height; subsequent groups then rendered overlapping the
	# wrong hit rects and tile clicks fell through to the previous
	# group. With HFlow as a direct VBox child the wrap calc matches
	# the original (working) single-row layout.
	var target_count: int = visible_groups.size() * 2
	while groups_host.get_child_count() < target_count:
		groups_host.add_child(_make_group_header())
		groups_host.add_child(_make_group_units())
	while groups_host.get_child_count() > target_count:
		# Remove in pairs so child_count stays even and the
		# (header, units) interleaving holds.
		for _step in range(2):
			if groups_host.get_child_count() == 0:
				break
			var stale := groups_host.get_child(groups_host.get_child_count() - 1)
			groups_host.remove_child(stale)
			stale.queue_free()

	for i in range(visible_groups.size()):
		var g_id: int = visible_groups[i]
		var header := groups_host.get_child(i * 2) as PanelContainer
		var units := groups_host.get_child(i * 2 + 1) as HFlowContainer
		if header == null or units == null:
			continue
		var members: Array[Satellite] = buckets[g_id]
		_update_group_header(header, g_id, members.size())
		_update_group_units(units, g_id, members, selected_sat)


# Single source of truth for "which group does this satellite belong
# to?". The current rules are arbitrary placeholders until per-unit
# customisation lands: surface → 3, otherwise laser → 1, railgun → 2,
# anything else falls back to Group 1. Replace this body when groups
# become operator-customisable.
func _group_for(sat: Satellite) -> int:
	if sat.is_surface:
		return GROUP_SURFACE
	if sat.has_laser():
		return GROUP_LASER
	if sat.has_railgun():
		return GROUP_RAILGUN
	return GROUP_LASER


# Build an empty group header tile. Clickable PanelContainer with a
# centred label; the actual text and tint are written by
# _update_group_header. Stays narrow (SHRINK_BEGIN horizontally) so
# the strip reads as a compact stack of group chips, not full-width
# bands.
func _make_group_header() -> PanelContainer:
	var header := PanelContainer.new()
	header.name = GROUP_HEADER_NAME
	header.custom_minimum_size = GROUP_HEADER_MIN_SIZE
	header.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	header.mouse_filter = Control.MOUSE_FILTER_STOP
	var sb := StyleBoxFlat.new()
	sb.bg_color = GROUP_HEADER_BG
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	header.add_theme_stylebox_override("panel", sb)

	var label := Label.new()
	label.name = GROUP_LABEL_NAME
	label.add_theme_font_size_override("font_size", GROUP_HEADER_FONT_SIZE)
	label.add_theme_color_override("font_color", NAME_TEXT_COLOR)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(label)

	header.gui_input.connect(_on_group_header_input.bind(header))
	return header


# Build an empty units row. HFlow so a long group wraps to a second
# row instead of running into the upper-right detail panel. Direct
# child of the host VBox (no intermediate container) so the wrap
# height matches the original working layout.
func _make_group_units() -> HFlowContainer:
	var units := HFlowContainer.new()
	units.name = GROUP_UNITS_NAME
	units.mouse_filter = Control.MOUSE_FILTER_IGNORE
	units.size_flags_horizontal = Control.SIZE_FILL
	units.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	units.add_theme_constant_override("h_separation", 6)
	units.add_theme_constant_override("v_separation", 6)
	return units


func _update_group_header(
	header: PanelContainer, group_id: int, count: int
) -> void:
	header.set_meta("group", group_id)
	var expanded: bool = bool(_expanded_groups.get(group_id, false))
	var sb := header.get_theme_stylebox("panel") as StyleBoxFlat
	if sb != null:
		sb.bg_color = GROUP_HEADER_BG_EXPANDED if expanded else GROUP_HEADER_BG
	var label := header.get_node_or_null(GROUP_LABEL_NAME) as Label
	if label != null:
		var arrow := "v" if expanded else ">"
		var gname: String = GROUP_NAMES.get(group_id, "Group ?")
		label.text = "%s  %s  (%d)" % [arrow, gname, count]


func _update_group_units(
	units: HFlowContainer,
	group_id: int,
	sats: Array[Satellite],
	selected_sat: Satellite,
) -> void:
	units.set_meta("group", group_id)
	var expanded: bool = bool(_expanded_groups.get(group_id, false))
	# Match the HFlow's child count to the group's expansion state
	# (0 when collapsed, sats.size() when expanded). Toggling
	# `visible` instead leaves stale children that bake their wrap
	# height into the parent VBox layout — subsequent rows then
	# render at the wrong y and tile clicks miss.
	var target_count: int = sats.size() if expanded else 0
	while units.get_child_count() < target_count:
		units.add_child(_make_box())
	while units.get_child_count() > target_count:
		var stale := units.get_child(units.get_child_count() - 1)
		units.remove_child(stale)
		stale.queue_free()
	if not expanded:
		return
	for i in range(sats.size()):
		var box := units.get_child(i) as PanelContainer
		_update_box(box, sats[i], sats[i] == selected_sat)


# Header click: toggle the group's expansion state, then refresh
# immediately so the change feels responsive rather than waiting up
# to ~100 ms for the next HUD throttle tick. _system is cached every
# frame by draw_target_lines; planning_mode lives on it.
func _on_group_header_input(event: InputEvent, header: PanelContainer) -> void:
	if not (event is InputEventMouseButton):
		return
	var mb: InputEventMouseButton = event
	if not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	if not header.has_meta("group"):
		return
	var group_id: int = header.get_meta("group") as int
	_expanded_groups[group_id] = not bool(_expanded_groups.get(group_id, false))
	print(
		"[HUD] header click g=%d expanded=%s" % [
			group_id, bool(_expanded_groups.get(group_id, false))
		]
	)
	if _system != null and is_instance_valid(_system):
		_update_groups(_system, _system.planning_mode)
	# After the layout settles, log every tile's global rect so we can
	# compare it against the cursor position reported in
	# _on_box_gui_input. Deferred so the queue_sort triggered by
	# child mutations runs first.
	call_deferred("_debug_log_tile_rects")


func _debug_log_tile_rects() -> void:
	if groups_host == null:
		return
	for i in range(groups_host.get_child_count()):
		var child := groups_host.get_child(i)
		if child is HFlowContainer:
			var units := child as HFlowContainer
			var g_meta: int = units.get_meta("group", -1) as int
			print(
				"[HUD] units g=%d rect=%s child_count=%d" % [
					g_meta, units.get_global_rect(), units.get_child_count()
				]
			)
			for j in range(units.get_child_count()):
				var tile := units.get_child(j) as Control
				if tile != null:
					print(
						"[HUD]   tile[%d] rect=%s filter=%d" % [
							j, tile.get_global_rect(), tile.mouse_filter
						]
					)


# True if `sat` belongs to a currently-expanded group. Tab / Shift+Tab
# cycling consults this so the operator only lands on units that are
# actually visible in the roster — cycling into a collapsed group
# would land on a unit the operator can't see.
func is_in_expanded_group(sat: Satellite) -> bool:
	if sat == null:
		return false
	var g_id := _group_for(sat)
	return bool(_expanded_groups.get(g_id, false))


func _make_box() -> PanelContainer:
	var box := PanelContainer.new()
	box.custom_minimum_size = BOX_MIN_SIZE
	# Tiles are click targets — STOP so the InputEvent reaches gui_input
	# rather than passing through to whatever sits behind the HUD.
	box.mouse_filter = Control.MOUSE_FILTER_STOP
	box.gui_input.connect(_on_box_gui_input.bind(box))
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
	rows.alignment = BoxContainer.ALIGNMENT_CENTER
	rows.add_theme_constant_override("separation", 4)
	box.add_child(rows)

	var name_label := Label.new()
	name_label.name = NAME_NODE_NAME
	name_label.add_theme_font_size_override("font_size", NAME_FONT_SIZE)
	name_label.add_theme_color_override("font_color", NAME_TEXT_COLOR)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rows.add_child(name_label)

	# Weapon-icon strip. One small panel per equipped weapon, tinted by
	# weapon class. Children are added on demand in _update_box so the
	# tile auto-shrinks for unarmed satellites.
	var icons := HBoxContainer.new()
	icons.name = ICONS_NODE_NAME
	icons.alignment = BoxContainer.ALIGNMENT_CENTER
	icons.add_theme_constant_override("separation", 3)
	icons.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rows.add_child(icons)

	return box


# Click handler bound at make-time. The current Satellite ref is stashed
# on the box via set_meta so the closure captures only `box` — that way
# we don't need to rebind on every selection change.
func _on_box_gui_input(event: InputEvent, box: PanelContainer) -> void:
	if not (event is InputEventMouseButton):
		return
	var mb: InputEventMouseButton = event
	if not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	var sat_name: String = "<no-meta>"
	if box.has_meta("sat"):
		var meta_sat := box.get_meta("sat") as Satellite
		if meta_sat != null and is_instance_valid(meta_sat):
			sat_name = meta_sat.unit_name if meta_sat.unit_name != "" else "<unnamed>"
	var box_global := box.get_global_rect()
	print(
		"[HUD] tile click event sat=%s rect=%s cursor=%s" % [
			sat_name, box_global, mb.global_position
		]
	)
	if not box.has_meta("sat"):
		return
	var sat: Satellite = box.get_meta("sat") as Satellite
	if sat == null or not is_instance_valid(sat):
		return
	friendly_clicked.emit(sat)


# Single weapon icon: a small color-tinted Panel with a centred glyph
# overlay. Mutated in place by _update_weapon_icon so the per-tile
# allocation cost stays at one Panel + one Label per weapon.
func _make_weapon_icon() -> Panel:
	var p := Panel.new()
	p.custom_minimum_size = WEAPON_ICON_SIZE
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = WEAPON_ICON_LASER
	sb.set_corner_radius_all(2)
	p.add_theme_stylebox_override("panel", sb)

	var glyph := Label.new()
	glyph.set_anchors_preset(Control.PRESET_FULL_RECT)
	glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	glyph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	glyph.add_theme_font_size_override("font_size", WEAPON_ICON_FONT_SIZE)
	glyph.add_theme_color_override("font_color", WEAPON_ICON_TEXT_COLOR)
	glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(glyph)
	return p


func _update_weapon_icon(icon: Panel, weapon: Weapon) -> void:
	var sb := icon.get_theme_stylebox("panel") as StyleBoxFlat
	var glyph := icon.get_child(0) as Label
	if weapon is RailgunWeapon:
		if sb != null:
			sb.bg_color = WEAPON_ICON_RAILGUN
		if glyph != null:
			glyph.text = "R"
	else:
		if sb != null:
			sb.bg_color = WEAPON_ICON_LASER
		if glyph != null:
			glyph.text = "L"


func _update_box(
	box: PanelContainer,
	sat: Satellite,
	is_selected: bool,
) -> void:
	# Stash the Satellite ref so the click handler can recover it
	# without a back-reference into the HUD's state. Kept fresh every
	# tick so a roster shuffle (death, planning swap) lands the click
	# on the right satellite.
	box.set_meta("sat", sat)

	var sb := box.get_theme_stylebox("panel") as StyleBoxFlat
	if sb != null:
		if _is_hit_target(sat):
			sb.bg_color = BOX_HIT_FLASH
		else:
			sb.bg_color = PLAYER_BG_SEL if is_selected else PLAYER_BG

	var rows := box.get_child(0) as VBoxContainer
	if rows == null:
		return

	var name_label := rows.get_node_or_null(NAME_NODE_NAME) as Label
	if name_label != null:
		# Empty unit_name (legacy / unnamed) collapses the row by hiding
		# the label so the box doesn't carry a blank line.
		var has_name := sat.unit_name != ""
		name_label.visible = has_name
		if has_name:
			name_label.text = sat.unit_name

	var icons := rows.get_node_or_null(ICONS_NODE_NAME) as HBoxContainer
	if icons == null:
		return
	while icons.get_child_count() < sat.weapons.size():
		icons.add_child(_make_weapon_icon())
	while icons.get_child_count() > sat.weapons.size():
		var stale := icons.get_child(icons.get_child_count() - 1)
		icons.remove_child(stale)
		stale.queue_free()
	for i in range(sat.weapons.size()):
		var icon := icons.get_child(i) as Panel
		if icon != null:
			_update_weapon_icon(icon, sat.weapons[i])
	icons.visible = not sat.weapons.is_empty()


# Upper-right detail panel. Tracks the currently selected friendly unit
# and renders the rich state that used to live in the per-tile box:
# HP, energy, propellant Δv, per-weapon readiness (with railgun ammo),
# fire control, targeting mode, railgun gate. Hidden whenever the
# selection isn't a player unit so the slot doesn't carry an empty
# panel.
func _update_unit_detail(orbital_set: Node, planning_mode: bool) -> void:
	if unit_detail_panel == null or unit_detail_label == null:
		return
	var sats: Array = orbital_set.satellites
	var idx: int = (
		orbital_set.planning_selected if planning_mode
		else orbital_set.selected_ship
	)
	if idx < 0 or idx >= sats.size():
		unit_detail_panel.visible = false
		return
	var sat: Satellite = sats[idx]
	if sat == null or not sat.alive or sat.team != Satellite.TEAM_PLAYER:
		unit_detail_panel.visible = false
		return
	unit_detail_panel.visible = true
	unit_detail_label.text = _format_unit_detail(sat)


# BBCode card for the upper-right unit inspector. Mirrors the legacy
# per-tile readout — header / HP / energy / Δv / per-weapon line /
# FC + TGT + RG — but reformatted as a column with subdued labels and
# colour-coded state values so the operator's eye lands on the live
# numbers rather than the field titles.
func _format_unit_detail(sat: Satellite) -> String:
	var lines := PackedStringArray()
	var header := sat.unit_name if sat.unit_name != "" else "Unit"
	lines.append(
		"[font_size=12][color=#f5b455]◆ %s[/color][/font_size]" % header
	)
	lines.append("[font_size=10][color=#9aa9b8]")
	lines.append(
		"[color=#5a6470]HP[/color]      %d / %d" % [int(sat.hp), int(sat.max_hp)]
	)
	if not sat.weapons.is_empty():
		lines.append(
			"[color=#5a6470]Energy[/color]  %s / %s" % [
				_format_joules(sat.energy), _format_joules(sat.energy_max),
			]
		)
	if (
		sat.team == Satellite.TEAM_PLAYER
		and not sat.is_surface
		and sat.max_propellant_kg > 0.0
	):
		lines.append(
			"[color=#5a6470]Δv[/color]      %d m/s" % int(round(sat.delta_v_remaining_ms()))
		)
	# Per-type counter so multiple lasers number 1, 2, 3 while a single
	# railgun reads as just "Railgun" (no index). Keeps the readout
	# sensible regardless of how the weapon array is composed.
	var per_type_idx: Dictionary = {}
	var per_type_total: Dictionary = {}
	for w_count: Weapon in sat.weapons:
		var n := w_count.display_name()
		per_type_total[n] = int(per_type_total.get(n, 0)) + 1
	for w: Weapon in sat.weapons:
		var name := w.display_name()
		var idx := int(per_type_idx.get(name, 0)) + 1
		per_type_idx[name] = idx
		var label := name
		if int(per_type_total[name]) > 1:
			label = "%s %d" % [name, idx]
		lines.append("[color=#5a6470]%s[/color]  %s" % [label, _weapon_status_bbcode(w)])
	if sat.has_laser():
		var fc_text: String = (
			"[color=#%s]FC ON %d km[/color]" % [
				_color_hex(FC_TEXT_COLOR), int(round(sat.engagement_range_km))
			]
			if sat.fire_control_active
			else "[color=#5a6470]FC OFF[/color]"
		)
		var tgt_text := (
			"[color=#%s]TGT %s[/color]" % [
				_color_hex(TGT_TEXT_COLOR),
				"MAX DANGER" if sat.targeting_mode == LaserWeapon.TARGETING_MAX_DANGER
				else "MAX DAMAGE",
			]
		)
		lines.append("%s   %s" % [fc_text, tgt_text])
	if sat.has_railgun():
		var rg_text := (
			"[color=#%s]RG %s · max R %d km[/color]" % [
				_color_hex(RG_TEXT_COLOR),
				"ON" if sat.railgun_enabled else "OFF",
				int(round(sat.max_orbital_radius_km)),
			]
		)
		lines.append(rg_text)
	lines.append("[/color][/font_size]")
	return "\n".join(lines)


# Per-weapon status fragment for the detail panel. Mirrors the legacy
# bar text — READY / COOLDOWN / partial — and tacks a magazine count
# onto railgun lines so ammo readiness and thermal readiness both read
# off the same line.
func _weapon_status_bbcode(w: Weapon) -> String:
	var prog := w.ready_progress()
	var pct := int(round(prog * 100.0))
	var ammo_suffix: String = ""
	if w is RailgunWeapon:
		var rg: RailgunWeapon = w
		ammo_suffix = "  %d/%d" % [rg.ammo_count, RailgunWeapon.MAGAZINE_SIZE]
	if w is RailgunWeapon and (w as RailgunWeapon).ammo_count <= 0:
		return "[color=#%s]EMPTY[/color]%s" % [_color_hex(BAR_COOLDOWN), ammo_suffix]
	if w.overheated:
		return "[color=#%s]COOLDOWN %d%%[/color]%s" % [
			_color_hex(BAR_COOLDOWN), pct, ammo_suffix
		]
	if prog >= 1.0:
		return "[color=#%s]READY[/color]%s" % [_color_hex(BAR_READY), ammo_suffix]
	return "[color=#%s]%d%%[/color]%s" % [_color_hex(BAR_COOLDOWN), pct, ammo_suffix]


# Color → "rrggbb" hex without the leading '#'. BBCode color tags
# accept the bare hex form, and inlining the conversion lets us keep
# the source-of-truth tint constants at the top of the file rather
# than duplicating them as string literals.
func _color_hex(c: Color) -> String:
	return "%02x%02x%02x" % [
		int(round(c.r * 255.0)),
		int(round(c.g * 255.0)),
		int(round(c.b * 255.0)),
	]


func draw_target_lines(orbital_set: Node, cam: Camera3D) -> void:
	_camera = cam
	_system = orbital_set
	# Repaint only while LOS lines are showing (they track moving
	# satellites, so that path stays per-frame) plus one clearing frame
	# after release. Unconditional queue_redraw invalidated the whole
	# HUD canvas item every frame for an almost-always-empty _draw.
	if los_visible or _los_drawn_prev:
		queue_redraw()
	_los_drawn_prev = los_visible


func _draw() -> void:
	if _system == null or _camera == null:
		return
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
