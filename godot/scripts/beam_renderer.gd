class_name BeamRenderer
extends Node3D
## 3D laser-beam visuals.
##
## CombatController.process_combat calls register_fire() on every successful
## weapon hit. The renderer pools one MeshInstance3D per
## (attacker, weapon_index); endpoints are recomputed every _process
## frame from current orbital positions, so the beam start anchors to
## the live emitter — a continuous burst no longer smears stale
## snapshots behind a moving satellite.
##
## Lifecycle:
##   - register_fire spawns or refreshes a beam.
##   - Beams not refreshed within HOLD+FADE wall-clock seconds despawn.
##   - Attacker dying despawns its beams immediately (no emitter).
##   - Target dying freezes the target endpoint at its last known
##     position so the kill-shot still reads as a clean line.
##
## A single CylinderMesh is shared across every beam; per-beam
## StandardMaterial3D is allocated once at spawn so _process only
## mutates transform + alpha (see CLAUDE.md "cache meshes and
## materials").

const Satellite = preload("res://scripts/satellite.gd")

# Wall-clock — high time_factor must not compress these away. HOLD
# matches the slowest expected register_fire cadence (a 60 Hz physics
# tick is ~16 ms, well under 40 ms); FADE is short enough that the
# trailing edge of a burst snaps off rather than smearing.
const HOLD_SECONDS: float = 0.04
const FADE_SECONDS: float = 0.10

# Style identifiers. Callers pass STYLE_LASER for energy beams and
# STYLE_KINETIC for beam-mode railguns; each maps to its own core
# radius / halo radius / colors below.
const STYLE_LASER: String = "laser"
const STYLE_KINETIC: String = "kinetic"

# Laser: thin neon-green core with a small, dim emission halo. Core
# is a hairline (0.035 unit radius) so the beam reads as a precise
# weapon trace; halo is ~1.7x core with low alpha so the glow stays
# subtle. Pulses at LASER_PULSE_HZ to make the beam pop against the
# starfield — at 12 Hz the modulation reads as a rapid throb rather
# than a strobe.
const LASER_CORE_RADIUS: float = 0.035
const LASER_HALO_RADIUS: float = 0.06
const LASER_CORE_COLOR := Color(0.55, 1.0, 0.35)
const LASER_HALO_COLOR := Color(0.35, 1.0, 0.30, 0.18)
const LASER_PULSE_HZ: float = 12.0
# Alpha at the trough of the pulse, as a fraction of the un-pulsed
# alpha. 0.25 keeps the beam visible at the dimmest point while
# leaving plenty of contrast against the peak.
const LASER_PULSE_FLOOR: float = 0.25

# Kinetic (beam-mode railgun): the original warm orange profile so
# operators can still tell the two weapon classes apart at a glance.
# Scene units (1 unit = 1000 km). The camera orbits at ~38 units; at
# 45° fov on a 1200-wide viewport, a 1 px line spans ~0.026 units in
# world space, so the cylinder needs a radius on that order to read
# as more than a hairline.
const KINETIC_CORE_RADIUS: float = 0.15
const KINETIC_HALO_RADIUS: float = 0.45
const KINETIC_CORE_COLOR := Color(1.0, 0.85, 0.55)
const KINETIC_HALO_COLOR := Color(1.0, 0.40, 0.12, 0.45)

var _shared_mesh: CylinderMesh
# key "<attacker_iid>:<weapon_index>" → _Beam.
var _beams: Dictionary = {}


class _Beam:
	var attacker: Satellite = null
	var target: Satellite = null
	var attacker_pos: Vector3 = Vector3.ZERO
	var target_pos: Vector3 = Vector3.ZERO
	var last_fired_at: float = 0.0
	var core_inst: MeshInstance3D = null
	var halo_inst: MeshInstance3D = null
	var core_mat: StandardMaterial3D = null
	var halo_mat: StandardMaterial3D = null
	var core_radius: float = 0.0
	var halo_radius: float = 0.0
	var core_base_color: Color = Color.WHITE
	var halo_base_color: Color = Color.WHITE
	# Hz of the rapid alpha pulse. 0 disables (kinetic style stays solid).
	var pulse_hz: float = 0.0


func _ready() -> void:
	_shared_mesh = CylinderMesh.new()
	# Unit cylinder: height 1, radius 1. The per-beam transform scales
	# Y by length and X/Z by core or halo radius — this lets one mesh
	# back every beam at any thickness.
	_shared_mesh.height = 1.0
	_shared_mesh.top_radius = 1.0
	_shared_mesh.bottom_radius = 1.0
	# Beam is thin and visually soft — eight sides is plenty.
	_shared_mesh.radial_segments = 8
	_shared_mesh.rings = 1


## Called by MassCenterSystem each physics tick a weapon successfully fires.
## Spawns a beam for this (attacker, weapon_index) if absent, otherwise
## refreshes target ref + last-fired timestamp. `style` selects the
## visual preset (STYLE_LASER vs STYLE_KINETIC) — only honored on first
## spawn for a given (attacker, weapon_index); subsequent calls reuse
## the existing beam's preset.
func register_fire(
	attacker: Satellite,
	weapon_index: int,
	target: Satellite,
	style: String = STYLE_KINETIC,
) -> void:
	if attacker == null or target == null:
		return
	var key := "%d:%d" % [attacker.get_instance_id(), weapon_index]
	var beam: _Beam = _beams.get(key)
	if beam == null:
		beam = _spawn_beam(style)
		beam.attacker = attacker
		_beams[key] = beam
	beam.target = target
	beam.last_fired_at = _wall_now()
	# Seed endpoints so the first frame after spawn already orients
	# correctly instead of flashing through the origin.
	beam.attacker_pos = attacker.orbit.r
	beam.target_pos = target.orbit.r


func _spawn_beam(style: String) -> _Beam:
	var beam := _Beam.new()
	if style == STYLE_LASER:
		beam.core_radius = LASER_CORE_RADIUS
		beam.halo_radius = LASER_HALO_RADIUS
		beam.core_base_color = LASER_CORE_COLOR
		beam.halo_base_color = LASER_HALO_COLOR
		beam.pulse_hz = LASER_PULSE_HZ
	else:
		beam.core_radius = KINETIC_CORE_RADIUS
		beam.halo_radius = KINETIC_HALO_RADIUS
		beam.core_base_color = KINETIC_CORE_COLOR
		beam.halo_base_color = KINETIC_HALO_COLOR
	# Core: bright inner cylinder, standard alpha-blend so it always
	# reads as a clearly visible line on GL Compatibility (where
	# additive-only beams without a glow post-process can wash out).
	beam.core_mat = _make_material(beam.core_base_color, BaseMaterial3D.BLEND_MODE_MIX)
	beam.core_inst = _make_instance(beam.core_mat)
	# Halo: wider, additive, semi-transparent — gives the beam its
	# energy-glow read against dark space without depending on glow.
	beam.halo_mat = _make_material(beam.halo_base_color, BaseMaterial3D.BLEND_MODE_ADD)
	beam.halo_inst = _make_instance(beam.halo_mat)
	return beam


func _make_material(color: Color, blend_mode: int) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = blend_mode
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	# Don't write depth — overlapping beams (or core+halo on one beam)
	# would otherwise occlude one another in a brittle order-dependent
	# way. Depth-test still applies, so Earth still occludes.
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	return mat


func _make_instance(mat: StandardMaterial3D) -> MeshInstance3D:
	var inst := MeshInstance3D.new()
	inst.mesh = _shared_mesh
	inst.material_override = mat
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(inst)
	return inst


func _process(_delta: float) -> void:
	if _beams.is_empty():
		return
	var now := _wall_now()
	var stale: Array[String] = []
	for key: String in _beams.keys():
		var beam: _Beam = _beams[key]
		# Attacker gone? The beam has no emitter — drop it immediately.
		if not is_instance_valid(beam.attacker) or not beam.attacker.alive:
			stale.append(key)
			continue
		var since := now - beam.last_fired_at
		if since > HOLD_SECONDS + FADE_SECONDS:
			stale.append(key)
			continue
		# Endpoints: always live for the attacker, live-or-snapshot for
		# the target so kill-shot beams still resolve to the last known
		# enemy position.
		beam.attacker_pos = beam.attacker.orbit.r
		if (
			is_instance_valid(beam.target)
			and beam.target.alive
			and beam.target.orbit_alive
		):
			beam.target_pos = beam.target.orbit.r
		var alpha: float
		if since <= HOLD_SECONDS:
			alpha = 1.0
		else:
			alpha = clampf(1.0 - (since - HOLD_SECONDS) / FADE_SECONDS, 0.0, 1.0)
		# Rapid alpha pulse for laser beams. Wall-clock driven so the
		# pulse rate stays the same regardless of time_factor; sine
		# remapped to [LASER_PULSE_FLOOR, 1.0] so the beam never fully
		# disappears between pulses.
		if beam.pulse_hz > 0.0:
			var phase: float = TAU * beam.pulse_hz * now
			var s: float = 0.5 + 0.5 * sin(phase)
			alpha *= LASER_PULSE_FLOOR + (1.0 - LASER_PULSE_FLOOR) * s
		_orient_beam(beam, alpha)
	for key: String in stale:
		_despawn(key)


func _orient_beam(beam: _Beam, alpha: float) -> void:
	var a := beam.attacker_pos * Satellite.SCENE_SCALE
	var b := beam.target_pos * Satellite.SCENE_SCALE
	var dir := b - a
	var length := dir.length()
	if length < 1.0e-4:
		beam.core_inst.visible = false
		beam.halo_inst.visible = false
		return
	beam.core_inst.visible = true
	beam.halo_inst.visible = true
	# CylinderMesh is local-Y aligned; build a basis whose Y column is
	# the beam direction, then stretch Y to the beam length and X/Z to
	# the desired radius. Basis.scaled() multiplies each column by the
	# corresponding scale component.
	var y_axis := dir / length
	var ref_axis: Vector3 = (
		Vector3.UP if absf(y_axis.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
	)
	var x_axis := ref_axis.cross(y_axis).normalized()
	var z_axis := x_axis.cross(y_axis).normalized()
	var origin := (a + b) * 0.5
	# Construct columns directly. Note: Basis.scaled() applies the
	# scale along WORLD axes (it's from_scale * basis), so it mangles a
	# rotated basis — multiplying each column by its own scalar is the
	# right way to stretch along the basis's local axes.
	beam.core_inst.transform = Transform3D(
		Basis(
			x_axis * beam.core_radius,
			y_axis * length,
			z_axis * beam.core_radius,
		),
		origin,
	)
	beam.halo_inst.transform = Transform3D(
		Basis(
			x_axis * beam.halo_radius,
			y_axis * length,
			z_axis * beam.halo_radius,
		),
		origin,
	)
	# Fade by mutating each cached material's alpha in place. Halo
	# alpha is the per-style base * fade so it never overpowers the core.
	var core_color := beam.core_base_color
	core_color.a = alpha
	beam.core_mat.albedo_color = core_color
	var halo_color := beam.halo_base_color
	halo_color.a = beam.halo_base_color.a * alpha
	beam.halo_mat.albedo_color = halo_color


func _despawn(key: String) -> void:
	var beam: _Beam = _beams.get(key)
	if beam == null:
		return
	if beam.core_inst != null:
		beam.core_inst.queue_free()
	if beam.halo_inst != null:
		beam.halo_inst.queue_free()
	_beams.erase(key)


func _wall_now() -> float:
	return Time.get_ticks_msec() / 1000.0
