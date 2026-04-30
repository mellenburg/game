class_name BeamRenderer
extends Node3D
## 3D laser-beam visuals.
##
## EarthSystem._process_combat calls register_fire() on every successful
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

# Scene units (1 unit = 1000 km). 0.04 → ~40 km radius — visible at
# typical camera distances without dominating the frame.
const BEAM_RADIUS: float = 0.04
const BEAM_COLOR := Color(1.0, 0.35, 0.10)
const BEAM_EMISSION_ENERGY: float = 4.0

var _shared_mesh: CylinderMesh
# key "<attacker_iid>:<weapon_index>" → _Beam.
var _beams: Dictionary = {}


class _Beam:
	var attacker: Satellite = null
	var target: Satellite = null
	var attacker_pos: Vector3 = Vector3.ZERO
	var target_pos: Vector3 = Vector3.ZERO
	var last_fired_at: float = 0.0
	var instance: MeshInstance3D = null
	var material: StandardMaterial3D = null


func _ready() -> void:
	_shared_mesh = CylinderMesh.new()
	# Unit height; transform Y-scale stretches it to the beam length.
	_shared_mesh.height = 1.0
	_shared_mesh.top_radius = BEAM_RADIUS
	_shared_mesh.bottom_radius = BEAM_RADIUS
	# Beam is thin, emissive, additive — no one is counting facets.
	_shared_mesh.radial_segments = 8
	_shared_mesh.rings = 1


## Called by EarthSystem each physics tick a weapon successfully fires.
## Spawns a beam for this (attacker, weapon_index) if absent, otherwise
## refreshes target ref + last-fired timestamp.
func register_fire(attacker: Satellite, weapon_index: int, target: Satellite) -> void:
	if attacker == null or target == null:
		return
	var key := "%d:%d" % [attacker.get_instance_id(), weapon_index]
	var beam: _Beam = _beams.get(key)
	if beam == null:
		beam = _spawn_beam()
		beam.attacker = attacker
		_beams[key] = beam
	beam.target = target
	beam.last_fired_at = _wall_now()
	# Seed endpoints so the first frame after spawn already orients
	# correctly instead of flashing through the origin.
	beam.attacker_pos = attacker.orbit.r
	beam.target_pos = target.orbit.r


func _spawn_beam() -> _Beam:
	var beam := _Beam.new()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = BEAM_COLOR
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.emission_enabled = true
	mat.emission = BEAM_COLOR
	mat.emission_energy_multiplier = BEAM_EMISSION_ENERGY
	# Additive overlapping beams would otherwise occlude each other.
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	beam.material = mat

	var inst := MeshInstance3D.new()
	inst.mesh = _shared_mesh
	inst.material_override = mat
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(inst)
	beam.instance = inst
	return beam


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
		_orient_beam(beam, alpha)
	for key: String in stale:
		_despawn(key)


func _orient_beam(beam: _Beam, alpha: float) -> void:
	var a := beam.attacker_pos * Satellite.SCENE_SCALE
	var b := beam.target_pos * Satellite.SCENE_SCALE
	var dir := b - a
	var length := dir.length()
	if length < 1.0e-4:
		beam.instance.visible = false
		return
	beam.instance.visible = true
	# CylinderMesh is local-Y aligned; build a basis whose Y column is
	# the beam direction, then stretch only Y to the beam length.
	var y_axis := dir / length
	var ref_axis: Vector3 = (
		Vector3.UP if absf(y_axis.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
	)
	var x_axis := ref_axis.cross(y_axis).normalized()
	var z_axis := x_axis.cross(y_axis).normalized()
	var basis := Basis(x_axis, y_axis, z_axis).scaled(Vector3(1.0, length, 1.0))
	beam.instance.transform = Transform3D(basis, (a + b) * 0.5)
	var c := BEAM_COLOR
	c.a = alpha
	beam.material.albedo_color = c
	beam.material.emission_energy_multiplier = BEAM_EMISSION_ENERGY * alpha


func _despawn(key: String) -> void:
	var beam: _Beam = _beams.get(key)
	if beam == null:
		return
	if beam.instance != null:
		beam.instance.queue_free()
	_beams.erase(key)


func _wall_now() -> float:
	return Time.get_ticks_msec() / 1000.0
