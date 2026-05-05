extends "res://tests/framework.gd"
## Coverage for the per-unit damage / kill bookkeeping the end-of-run
## summary hangs off. The accountant lives on `Satellite.take_damage`
## (it accepts an optional attacker and credits it on hit / kill); we
## drive it directly here so the contract is locked independently of
## any specific weapon's wiring.
##
## Satellite extends Node3D, but its `take_damage` is independent of
## the SceneTree, so we instantiate the class without parenting and
## queue_free at end-of-test to keep the headless run clean.

const Satellite = preload("res://scripts/satellite.gd")


func _make() -> Satellite:
	var s: Satellite = Satellite.new()
	# take_damage refuses to mutate hp on a body that isn't alive, and
	# Satellite._init sets alive = true by default — explicit here so
	# the test asserts the flag rather than relying on a default it
	# doesn't see.
	s.alive = true
	s.hp = 100.0
	s.max_hp = 100.0
	return s


func test_take_damage_credits_attacker() -> void:
	# Hit a 100-HP target for 30 with a known attacker; both the
	# target's hp and the attacker's damage_dealt should reflect the
	# applied amount. No kill ⇒ kills counter stays put.
	var attacker := _make()
	var target := _make()
	target.take_damage(30.0, attacker)
	assert_close(target.hp, 70.0)
	assert_close(attacker.damage_dealt, 30.0)
	assert_eq(attacker.kills, 0)
	attacker.queue_free()
	target.queue_free()


func test_take_damage_caps_credit_at_overkill() -> void:
	# Overkill (200 dmg on 100 HP) should still leave hp at 0 and only
	# credit the attacker for the 100 they actually applied — not the
	# raw amount. Otherwise long-lived units rack up phantom DPS.
	var attacker := _make()
	var target := _make()
	target.take_damage(200.0, attacker)
	assert_close(target.hp, 0.0)
	assert_close(attacker.damage_dealt, 100.0)
	assert_eq(attacker.kills, 1)
	assert_false(target.alive)
	attacker.queue_free()
	target.queue_free()


func test_take_damage_kill_increments_attacker_kills() -> void:
	# Two hits, second one finishing the target. The killing-blow
	# attacker's kills counter ticks; the earlier attacker's stays at
	# 0 (only the finishing blow counts as a "kill"). Both attackers
	# get damage credit for what they applied.
	var first := _make()
	var second := _make()
	var target := _make()
	target.take_damage(40.0, first)
	target.take_damage(80.0, second)
	assert_close(first.damage_dealt, 40.0)
	assert_eq(first.kills, 0)
	assert_close(second.damage_dealt, 60.0)  # capped at remaining 60 HP
	assert_eq(second.kills, 1)
	assert_false(target.alive)
	first.queue_free()
	second.queue_free()
	target.queue_free()


func test_take_damage_without_attacker_still_applies() -> void:
	# attacker omitted (e.g. environmental damage in the future) ⇒
	# target still loses HP, no crediting happens. Verifies the
	# attacker arg is genuinely optional.
	var target := _make()
	target.take_damage(25.0)
	assert_close(target.hp, 75.0)
	target.queue_free()


func test_asteroid_mass_couples_to_hp() -> void:
	# A asteroid under fire should physically erode: damage represents
	# fragmentation, so HP loss drops mass proportionally. The mass-HP
	# coupling is what feeds back into both impact damage radius
	# (smaller mass → smaller blast) and railgun deflection (smaller
	# mass → bigger Δv per slug).
	var attacker := _make()
	var target := Satellite.new()
	target.alive = true
	target.is_asteroid = true
	target.density_g_cm3 = 3.4
	target.mass = 1.0e6  # 1 Gg, well above the burn-up threshold
	target.max_hp = 0.003 * target.mass * target.density_g_cm3
	target.hp = target.max_hp
	# Halve the HP, expect mass to halve too.
	target.take_damage(target.max_hp * 0.5, attacker)
	assert_close(target.hp, target.max_hp * 0.5, 1.0e-3)
	assert_close(target.mass, 5.0e5, 5.0e5 * 1.0e-3)
	# Reduce HP to a sliver — mass should track all the way down to
	# (very nearly) zero without going negative.
	target.take_damage(target.hp - 1.0, attacker)
	assert_close(target.hp, 1.0, 1.0e-6)
	assert_true(target.mass > 0.0 and target.mass < 1.0e3)
	attacker.queue_free()
	target.queue_free()


func test_non_asteroid_mass_unchanged_by_damage() -> void:
	# Player ships and unarmed orbital enemies don't track mass loss
	# under fire — damage represents subsystem destruction, not
	# fragmentation. The mass field stays at its spawn-time wet-mass
	# value so railgun recoil and propellant math don't drift.
	var attacker := _make()
	var target := _make()
	var spawn_mass: float = target.mass
	target.take_damage(50.0, attacker)
	assert_close(target.mass, spawn_mass, 1.0e-6)
	attacker.queue_free()
	target.queue_free()


func test_eroded_asteroid_is_inert() -> void:
	# A asteroid chipped down to below the atmospheric burn-up
	# threshold reports `is_inert_asteroid` so weapons can disengage.
	# A regular orbital enemy at the same low mass does NOT — the
	# burn-up flag only applies to sub-orbital asteroids and
	# decaying-orbit threats.
	var rock := Satellite.new()
	rock.alive = true
	rock.is_asteroid = true
	rock.density_g_cm3 = 3.4
	rock.mass = 1.0e3  # well below the 1e4 burn-up threshold
	assert_true(rock.is_inert_asteroid())
	rock.mass = 1.0e6
	assert_false(rock.is_inert_asteroid())
	# Non-asteroid at sub-threshold mass: not inert (regular enemies
	# still get engaged regardless of their default 1000 kg mass).
	var enemy := Satellite.new()
	enemy.alive = true
	enemy.mass = 500.0
	assert_false(enemy.is_inert_asteroid())
	rock.queue_free()
	enemy.queue_free()


func test_dead_target_take_damage_is_a_no_op() -> void:
	# Repeated hits on a dead body shouldn't double-count kills or
	# pump up damage_dealt past the kill blow. Two attackers fire on
	# an already-dead target — both should bounce off cleanly.
	var attacker := _make()
	var target := _make()
	target.alive = false
	target.hp = 0.0
	target.take_damage(50.0, attacker)
	assert_close(attacker.damage_dealt, 0.0)
	assert_eq(attacker.kills, 0)
	attacker.queue_free()
	target.queue_free()
