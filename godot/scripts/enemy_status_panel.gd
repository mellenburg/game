class_name EnemyStatusPanel
extends RichTextLabel
## Upper-right inspector panel shown when the operator clicks a tile
## in the bottom-left enemy tessellation. Replaces the static controls
## help text that used to live there — that text has migrated into a
## permanently-available cheat sheet on the pause menu.
##
## The panel is BBCode-formatted and updated by HUD on the same ~10 Hz
## tick the rest of the roster uses, so HP / ETA readouts track the
## sim without per-frame work. Self-hides when the HUD has no
## inspected enemy or the inspected unit dies.

const Satellite = preload("res://scripts/satellite.gd")
const MeteorPhysics = preload("res://scripts/meteor_physics.gd")


func _ready() -> void:
	bbcode_enabled = true
	scroll_active = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false


## Update the panel from the inspected enemy. `sat` may be null —
## that hides the panel.
func show_enemy(sat: Satellite, current_sim_time: float) -> void:
	if sat == null or not is_instance_valid(sat) or not sat.alive:
		visible = false
		return
	visible = true
	var lines := PackedStringArray()
	lines.append("[font_size=13][color=#f5b455]ENEMY DETAIL[/color][/font_size]")
	lines.append("[font_size=12][color=gray]Class[/color] %s" % MeteorPhysics.mass_class_name(
		MeteorPhysics.mass_class_for(sat.mass)
	))
	# Composition is meaningful only for meteorite / decaying-orbit
	# bodies — those carry a sampled comp index from the asteroid
	# table. -1 (uncategorised) is hidden so the panel doesn't carry
	# a misleading "unknown" line on plain enemy satellites.
	if sat.composition >= 0:
		lines.append("[color=gray]Comp[/color] %s" % MeteorPhysics.composition_name(sat.composition))
	lines.append("[color=gray]Mass[/color] %s" % _format_mass(sat.mass))
	lines.append("[color=gray]HP[/color] %s / %s" % [
		_format_hp(sat.hp), _format_hp(sat.max_hp),
	])
	# ETA — the same predicted-impact time the tile order is sorted by.
	# INF means the body's current trajectory does not intersect the
	# surface: a regular orbital enemy. Shown as "stable orbit" in that
	# case rather than "INF s".
	var impact_t: float = sat.predict_impact_sim_time(current_sim_time)
	if is_finite(impact_t):
		var eta := maxf(impact_t - current_sim_time, 0.0)
		lines.append("[color=gray]ETA[/color] %s" % _format_duration(eta))
	else:
		lines.append("[color=gray]ETA[/color] stable orbit")
	if sat.unit_name != "":
		lines.append("[color=gray]Tag[/color] %s" % sat.unit_name)
	lines.append("[/font_size]")
	text = "\n".join(lines)


# Mass formatting — kg up to 1e3, then Mg / Gg / Tg / Pg in scientific
# steps. Matches the spawn director's mass-band terminology so the
# panel's readout maps directly back to the menu / docs.
func _format_mass(kg: float) -> String:
	if kg >= 1.0e15:
		return "%.2f Pg" % (kg * 1.0e-15)
	if kg >= 1.0e12:
		return "%.2f Tg" % (kg * 1.0e-12)
	if kg >= 1.0e9:
		return "%.2f Gg" % (kg * 1.0e-9)
	if kg >= 1.0e6:
		return "%.2f Mg" % (kg * 1.0e-6)
	if kg >= 1.0e3:
		return "%.1f t" % (kg * 1.0e-3)
	return "%.0f kg" % kg


func _format_hp(hp: float) -> String:
	if hp >= 1.0e6:
		return "%.1fM" % (hp * 1.0e-6)
	if hp >= 1.0e3:
		return "%.1fk" % (hp * 1.0e-3)
	return "%.0f" % hp


# Sim-second duration as h:mm:ss / m:ss / s. Sticks to seconds at
# small values so the live ETA countdown stays readable as it ticks
# down.
func _format_duration(seconds: float) -> String:
	var s := int(round(seconds))
	if s < 60:
		return "%d s" % s
	if s < 3600:
		return "%d:%02d" % [s / 60, s % 60]
	return "%d:%02d:%02d" % [s / 3600, (s / 60) % 60, s % 60]
