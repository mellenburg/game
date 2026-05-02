class_name HUD
extends Control
## Roster + targeting overlay. Player units render as green-tinted
## panels along the top-left and surface HP / energy / cooldown rows.
## Enemies render along the bottom-left as area-proportional squares —
## edge length scales with sqrt(max_hp) so a meteorite (25 HP) is small,
## a sat (100 HP) is medium, a decaying body (200 HP) is large. The
## solid fill shrinks bottom-up as HP drops, revealing a translucent
## red layer that marks the original footprint. Rows wrap upward once
## adding the next box would push them past half the viewport width.
##
## BBCode / panel rebuilds throttle to ~10 Hz; per-frame allocations
## are avoided by reusing children across ticks (we only add/remove
## when the per-team / per-row count changes).

const Satellite = preload("res://scripts/satellite.gd")
const LosCheck = preload("res://scripts/los_check.gd")
const Weapon = preload("res://scripts/weapons/weapon.gd")
const UIStyle = preload("res://scripts/ui/ui_style.gd")

const HUD_UPDATE_INTERVAL: float = 0.1  # seconds

# Roster box flash on hit. Bad-status red from the shared palette so
# the HUD's "you took damage" signal speaks the same colour vocabulary
# as the rest of the UI's negative states.
const BOX_HIT_FLASH := UIStyle.BAD
# Player roster width is fixed so the boxes line up evenly along the
# top strip. Height auto-sizes from the contained HP / energy /
# weapon rows. Enemy boxes don't share this — they're area-scaled.
const BOX_MIN_SIZE := Vector2(112, 0)

# Bar row colors. Energy is amber (the brand accent) so the player's
# main reservoir reads as "their" resource; weapon recovery is the
# warn / good split — orange while charging, green at READY.
const BAR_BG := UIStyle.BAR_TRACK
const BAR_ENERGY := UIStyle.ACCENT
const BAR_COOLDOWN := UIStyle.WARN
const BAR_READY := UIStyle.GOOD
const BAR_ROW_HEIGHT: float = 14.0
const BAR_FONT_SIZE: int = UIStyle.FONT_LABEL_XS

# Fire-control readout — info cyan from the shared palette, distinct
# from the GOOD/WARN bar fills below it so the meta line doesn't
# collide visually with the per-weapon bars.
const FC_TEXT_COLOR := UIStyle.INFO
const FC_FONT_SIZE: int = UIStyle.FONT_BODY_SM
const FC_NODE_NAME: String = "FCStatus"

# Targeting-mode readout. Always present on armed player ships (unlike
# the FC line which only shows when fire control is on) — it's a
# persistent gameplay setting, not a toggle-into-an-overlay state. Uses
# the warm accent so it reads as "your active mode setting".
const TGT_TEXT_COLOR := UIStyle.ACCENT
const TGT_FONT_SIZE: int = UIStyle.FONT_BODY_SM
const TGT_NODE_NAME: String = "TargetingStatus"

# HP label colour for the player roster — bright fg_0 on the
# selected/normal card, switching to a muted fg_2 wouldn't read at the
# bar-row sizes we're using.
const HP_TEXT_COLOR := UIStyle.FG_0
const HP_FONT_SIZE: int = UIStyle.FONT_BODY

const LOS_CLEAR := UIStyle.WARN                 # yellow-amber
const LOS_BLOCKED := UIStyle.BAD                # red

# Wall-clock duration of the hit pulse on the marker / roster box.
# Wall-clock so the visual feedback survives compression at high
# time_factor — at time_factor=5000 a sim-second is 0.2 ms, which
# would be invisible. The actual beam is drawn by BeamRenderer in 3D;
# this constant only governs how long the box / marker stays tinted.
const HIT_DURATION: float = 0.25

@onready var info_label: RichTextLabel = $InfoLabel as RichTextLabel
@onready var player_roster: HBoxContainer = $PlayerRoster as HBoxContainer
@onready var enemy_roster: VBoxContainer = $EnemyRoster as VBoxContainer
@onready var target_container: Control = $TargetContainer as Control
@onready var kill_stats: RichTextLabel = $KillStats as RichTextLabel

var _camera: Camera3D
var _system: Node = null
var _last_text_update: float = 0.0

# Active hit pulses. Drives the roster box red flash and (via
# Satellite.flash_hit) the 3D marker tint. The actual beam visual
# lives in BeamRenderer; this list is just timed metadata for the
# box / marker feedback so it outlives the firing tick.
var _hits: Array[Dictionary] = []
# Toggled by EarthSystem on the "toggle_los" input action. When false,
# the yellow / pink LOS lines from the selected satellite to opposing
# units are suppressed; hit pulses remain visible regardless.
var los_visible: bool = true


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


func update_hud(orbital_set: Node, planning_mode: bool, time_factor: int, dt: int) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now - _last_text_update < HUD_UPDATE_INTERVAL:
		return
	_last_text_update = now

	_update_info_label(planning_mode, time_factor, dt)
	_update_rosters(orbital_set, planning_mode)
	_update_kill_stats(orbital_set)


func _update_info_label(planning_mode: bool, time_factor: int, dt: int) -> void:
	if info_label == null:
		return
	var fg2 := UIStyle.FG_2.to_html(false)
	var fg0 := UIStyle.FG_0.to_html(false)
	var accent := UIStyle.ACCENT.to_html(false)
	var lines := PackedStringArray()
	lines.append("[font_size=%d]" % UIStyle.FONT_BODY)
	if planning_mode:
		lines.append("[color=#%s]PLANNING MODE[/color]" % accent)
	lines.append(
		"[color=#%s]TIME FACTOR[/color]  [color=#%s]%d[/color]" % [fg2, fg0, time_factor]
	)
	if planning_mode:
		lines.append(
			"[color=#%s]PLANNING DT[/color]  [color=#%s]%d[/color]" % [fg2, fg0, dt]
		)
	lines.append("[/font_size]")
	info_label.text = "\n".join(lines)


func _update_kill_stats(orbital_set: Node) -> void:
	if kill_stats == null:
		return
	# Read tallies straight off the controller — no signal plumbing
	# needed; the HUD already polls orbital_set every tick anyway.
	var shot: int = orbital_set.enemies_shot_down
	var hit: int = orbital_set.meteorites_impacted
	var fg2 := UIStyle.FG_2.to_html(false)
	var fg0 := UIStyle.FG_0.to_html(false)
	var good := UIStyle.GOOD.to_html(false)
	var bad := UIStyle.BAD.to_html(false)
	kill_stats.text = (
		"[font_size=%d][color=#%s]ENEMIES ELIMINATED[/color][/font_size]\n" % [UIStyle.FONT_LABEL_XS, fg2]
		+ "[font_size=%d]" % UIStyle.FONT_BODY
		+ "[color=#%s]SHOT DOWN[/color]  [color=#%s]%d[/color]\n" % [fg2, good, shot]
		+ "[color=#%s]IMPACTED[/color]  [color=#%s]%d[/color]" % [fg2, bad, hit]
		+ "[/font_size]"
	)


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
	var selected_enemy: Satellite = null

	for i in range(satellites.size()):
		var sat: Satellite = satellites[i]
		if not sat.alive:
			continue
		if sat.team == Satellite.TEAM_ENEMY:
			if i == selected_idx:
				selected_enemy = sat
			enemies.append(sat)
		else:
			if i == selected_idx:
				player_selected_in_roster = players.size()
			players.append(sat)

	var current_sim_time: float = orbital_set.sim_time
	enemies = _sort_enemies_by_impact_urgency(enemies, current_sim_time)
	# Recompute the selected-enemy index after the sort so the green
	# selection tint follows the satellite, not its old slot.
	var enemy_selected_in_roster: int = -1
	if selected_enemy != null:
		enemy_selected_in_roster = enemies.find(selected_enemy)

	_render_player_roster(players, player_selected_in_roster)
	_render_enemy_roster(enemies, enemy_selected_in_roster)


# Sort enemies so the body with the smallest predicted impact time on
# Earth lands in the top-left slot of the bottom-strip roster, with
# the rest descending by urgency. Bodies whose current trajectory does
# not intersect the surface (regular orbital enemies) all share INF
# and fall to the tail; the instance-id tiebreaker keeps their
# relative order stable across HUD refreshes so they don't shuffle
# visually.
#
# Reads the cached absolute impact sim-time via predict_impact_sim_time
# — for an unforced body that's a single field read, computed once at
# spawn and never updated thereafter. Ordering by absolute time gives
# the same ranking as ordering by relative ETA without the per-tick
# bookkeeping. The sort is O(n log n) field reads with at most one
# fresh propagation per newly-spawned enemy.
func _sort_enemies_by_impact_urgency(
	enemies: Array[Satellite], current_sim_time: float
) -> Array[Satellite]:
	if enemies.size() <= 1:
		return enemies
	var pairs: Array[Dictionary] = []
	for sat in enemies:
		pairs.append({
			"sat": sat,
			"tti": sat.predict_impact_sim_time(current_sim_time),
			"id": sat.get_instance_id(),
		})
	pairs.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["tti"] != b["tti"]:
			return a["tti"] < b["tti"]
		return a["id"] < b["id"]
	)
	var sorted: Array[Satellite] = []
	for pair: Dictionary in pairs:
		sorted.append(pair["sat"])
	return sorted


func _render_player_roster(sats: Array[Satellite], selected: int) -> void:
	while player_roster.get_child_count() < sats.size():
		player_roster.add_child(_make_box())
	while player_roster.get_child_count() > sats.size():
		var stale := player_roster.get_child(player_roster.get_child_count() - 1)
		player_roster.remove_child(stale)
		stale.queue_free()
	for i in range(sats.size()):
		var box := player_roster.get_child(i) as PanelContainer
		_update_box(box, sats[i], i == selected)


# Square area encodes max HP (px² per HP point). Tuned so a 25 HP
# meteorite is a 20 px square, a 100 HP enemy sat is 40 px, and a
# 200 HP decaying body is ~57 px — visually distinct without any
# single body dominating the strip at typical viewport widths.
const ENEMY_HP_AREA_PER_PX: float = 16.0
const ENEMY_BOX_SEPARATION: int = 6
# Drawn behind the solid fill at full box dimensions, so any area the
# fill no longer covers reads as "lost HP". A muted bad-status track —
# translucent enough not to fight the overlapping LOS lines or the
# radar / impact map below. Same hue as UIStyle.BAD at 30% alpha.
const ENEMY_LOST_HP_COLOR := Color(1.0, 0.36, 0.36, 0.30)
# Subtype-tinted solid fill mapped onto the shared status palette: hostile
# satellites get BAD red, meteorites get WARN amber, decaying bodies get
# INFO cyan. Selection borrows the brand ACCENT so picking a target reads
# the same way it does on a player roster card.
const ENEMY_FILL_SAT := UIStyle.BAD
const ENEMY_FILL_METEORITE := UIStyle.WARN
const ENEMY_FILL_DECAYING := UIStyle.INFO
const ENEMY_FILL_SELECTED := UIStyle.ACCENT


# Multi-row, area-proportional enemy strip. Boxes flow left-to-right
# along the bottom and wrap into a new row above once the next box
# would push the row past half the viewport width — the rest of the
# screen is reserved for the impact map and orbital view.
func _render_enemy_roster(sats: Array[Satellite], selected: int) -> void:
	if enemy_roster == null:
		return
	var max_row_w: float = get_viewport_rect().size.x * 0.5
	var sep: float = float(ENEMY_BOX_SEPARATION)

	# Partition sats into rows under the half-viewport cap. A row never
	# wraps on its first box — a single oversize box on its own line is
	# still less surprising than dropping it entirely.
	var rows: Array = []
	var current: Array = []
	var current_w: float = 0.0
	for i in range(sats.size()):
		var side := _enemy_box_side(sats[i])
		var span := side + (sep if not current.is_empty() else 0.0)
		if not current.is_empty() and current_w + span > max_row_w:
			rows.append(current)
			current = [i]
			current_w = side
		else:
			current.append(i)
			current_w += span
	if not current.is_empty():
		rows.append(current)

	# Reuse row containers across ticks; only resize the pool when the
	# row count changes (matches the player-roster idiom).
	while enemy_roster.get_child_count() < rows.size():
		enemy_roster.add_child(_make_enemy_row())
	while enemy_roster.get_child_count() > rows.size():
		var stale := enemy_roster.get_child(enemy_roster.get_child_count() - 1)
		enemy_roster.remove_child(stale)
		stale.queue_free()

	for r in range(rows.size()):
		var row := enemy_roster.get_child(r) as HBoxContainer
		var indices: Array = rows[r]
		while row.get_child_count() < indices.size():
			row.add_child(_make_enemy_box())
		while row.get_child_count() > indices.size():
			var stale_box := row.get_child(row.get_child_count() - 1)
			row.remove_child(stale_box)
			stale_box.queue_free()
		for c in range(indices.size()):
			var sat_i: int = indices[c]
			_update_enemy_box(
				row.get_child(c) as Control,
				sats[sat_i],
				sat_i == selected,
			)


func _enemy_box_side(sat: Satellite) -> float:
	# sqrt because area (not edge length) tracks HP; a 4× HP target is
	# a 2× wider square, which reads as "much bigger" without any one
	# threat type dwarfing the row.
	return sqrt(maxf(sat.max_hp, 1.0) * ENEMY_HP_AREA_PER_PX)


func _make_enemy_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", ENEMY_BOX_SEPARATION)
	# SHRINK_END so a row with mixed-size boxes plants every box on a
	# common bottom line — the smaller meteorite squares hug the same
	# baseline as the bigger decaying bodies.
	row.size_flags_vertical = Control.SIZE_SHRINK_END
	return row


func _make_enemy_box() -> Control:
	var box := Control.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.size_flags_vertical = Control.SIZE_SHRINK_END
	box.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN

	# Layer 0: full-size translucent red — the "original size" footprint.
	var lost := ColorRect.new()
	lost.set_anchors_preset(Control.PRESET_FULL_RECT)
	lost.color = ENEMY_LOST_HP_COLOR
	lost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(lost)

	# Layer 1: solid fill, anchor-driven so we never measure pixels —
	# anchor_top = 1 - hp/max yields a bottom-aligned column whose area
	# tracks current HP linearly.
	var fill := ColorRect.new()
	fill.anchor_left = 0.0
	fill.anchor_right = 1.0
	fill.anchor_top = 0.0
	fill.anchor_bottom = 1.0
	fill.color = ENEMY_FILL_SAT
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(fill)

	return box


func _update_enemy_box(box: Control, sat: Satellite, is_selected: bool) -> void:
	var side := _enemy_box_side(sat)
	box.custom_minimum_size = Vector2(side, side)

	var fill := box.get_child(1) as ColorRect
	if fill == null:
		return
	if _is_hit_target(sat):
		fill.color = BOX_HIT_FLASH
	elif is_selected:
		fill.color = ENEMY_FILL_SELECTED
	else:
		fill.color = _enemy_fill_color(sat)

	var max_hp := maxf(sat.max_hp, 1.0)
	var frac := clampf(sat.hp / max_hp, 0.0, 1.0)
	fill.anchor_top = 1.0 - frac


func _enemy_fill_color(sat: Satellite) -> Color:
	if sat.is_meteorite:
		return ENEMY_FILL_METEORITE
	if sat.is_decaying:
		return ENEMY_FILL_DECAYING
	return ENEMY_FILL_SAT


func _make_box() -> PanelContainer:
	var box := PanelContainer.new()
	box.custom_minimum_size = BOX_MIN_SIZE
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Per-box StyleBoxFlat so we can mutate bg_color / border_color in
	# place rather than reallocating on every selection change.
	box.add_theme_stylebox_override("panel", UIStyle.make_card_stylebox(false))

	var rows := VBoxContainer.new()
	rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rows.add_theme_constant_override("separation", 3)
	box.add_child(rows)

	# Index 0 is the plain HP label. Bar rows for energy + each weapon
	# are added on demand by _update_box so the per-team child count
	# matches the actual satellite (an unarmed enemy gets just HP).
	var hp := Label.new()
	hp.add_theme_font_size_override("font_size", HP_FONT_SIZE)
	hp.add_theme_color_override("font_color", HP_TEXT_COLOR)
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
			sb.bg_color = Color(UIStyle.BAD.r, UIStyle.BAD.g, UIStyle.BAD.b, 0.45)
			sb.border_color = UIStyle.BAD
		elif is_selected:
			sb.bg_color = UIStyle.ACCENT_SOFT
			sb.border_color = UIStyle.ACCENT
		else:
			sb.bg_color = UIStyle.BG_2
			sb.border_color = UIStyle.LINE

	var rows := box.get_child(0) as VBoxContainer
	if rows == null:
		return

	# Index 0 is the HP label; bar rows follow; an optional FC status
	# label and targeting-mode label tail the box. Detach both meta
	# labels first so the bar-resize loop's child-count math stays
	# unchanged — we re-append (or drop) them after the bars settle.
	var hp_label := rows.get_child(0) as Label
	if hp_label != null:
		hp_label.text = "HP  %d / %d" % [int(sat.hp), int(sat.max_hp)]
		# Tint the HP readout by remaining fraction so a glance at the
		# roster strip surfaces wounded units even before the energy bar
		# below registers a hit.
		var max_hp := maxf(sat.max_hp, 1.0)
		var frac := clampf(sat.hp / max_hp, 0.0, 1.0)
		var hp_col: Color = UIStyle.GOOD
		if frac < 0.34:
			hp_col = UIStyle.BAD
		elif frac < 0.67:
			hp_col = UIStyle.WARN
		hp_label.add_theme_color_override("font_color", hp_col)

	var fc_label := rows.get_node_or_null(FC_NODE_NAME) as Label
	if fc_label != null:
		rows.remove_child(fc_label)
	var tgt_label := rows.get_node_or_null(TGT_NODE_NAME) as Label
	if tgt_label != null:
		rows.remove_child(tgt_label)

	var desired_bars := 0
	if not sat.weapons.is_empty():
		desired_bars = 1 + sat.weapons.size()
	var current_bars := rows.get_child_count() - 1
	while current_bars < desired_bars:
		rows.add_child(_make_bar_row())
		current_bars += 1
	while current_bars > desired_bars:
		var stale := rows.get_child(rows.get_child_count() - 1)
		rows.remove_child(stale)
		stale.queue_free()
		current_bars -= 1

	# Reattach (or drop) the FC label after the bars are in their
	# final shape. Only armed satellites can have fire control on; an
	# unarmed unit shouldn't carry the label even if some upstream
	# state ever flipped the flag.
	var want_fc := sat.fire_control_active and not sat.weapons.is_empty()
	if want_fc:
		if fc_label == null:
			fc_label = _make_fc_label()
		fc_label.text = "FC ON  %d KM" % int(round(sat.engagement_range_km))
		rows.add_child(fc_label)
	elif fc_label != null:
		fc_label.queue_free()

	# Targeting mode is always shown on armed player ships — it's a
	# persistent setting, not a transient overlay, so it doesn't gate
	# on a toggle. Unarmed bodies skip it for the same reason FC does.
	var want_tgt := not sat.weapons.is_empty()
	if want_tgt:
		if tgt_label == null:
			tgt_label = _make_targeting_label()
		tgt_label.text = (
			"TGT  MAX DANGER" if sat.targeting_mode == Satellite.TARGETING_MAX_DANGER
			else "TGT  MAX DAMAGE"
		)
		rows.add_child(tgt_label)
	elif tgt_label != null:
		tgt_label.queue_free()

	if desired_bars == 0:
		return

	var energy_row := rows.get_child(1) as Control
	if energy_row != null:
		var pct := int(round(sat.energy * 100.0))
		_update_bar_row(
			energy_row, BAR_ENERGY, "ENERGY  %d%%" % pct, sat.energy
		)

	for i in range(sat.weapons.size()):
		var w: Weapon = sat.weapons[i]
		var row := rows.get_child(2 + i) as Control
		if row == null:
			continue
		var prog := w.ready_progress()
		var pct := int(round(prog * 100.0))
		# Three states: OVERHEAT (locked, cooling back to 100%), READY
		# (full and unlocked), or partial (firing or recovering toward
		# READY without having tripped the lockout).
		var text: String
		var fill_color: Color
		if w.overheated:
			text = "L%d  OVERHEAT %d%%" % [i + 1, pct]
			fill_color = BAR_COOLDOWN
		elif prog >= 1.0:
			text = "L%d  READY" % (i + 1)
			fill_color = BAR_READY
		else:
			text = "L%d  %d%%" % [i + 1, pct]
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
