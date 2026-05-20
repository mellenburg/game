# Missile system reference

Operator-fired guided-intercept missiles. This doc covers the
architecture, the physics calibration, the design tradeoffs, and a
refactor playbook for the next agent or contributor.

The companion source files are listed below — each has a docstring
header but cross-cutting decisions (why manual-fire, why deferred
damage, why two reservation maps) only make sense in this document.

| File                                          | Role                                                       |
| --------------------------------------------- | ---------------------------------------------------------- |
| `scripts/lambert_solver.gd`                   | Pure-math universal-variable Lambert solver                |
| `scripts/weapons/missile_weapon.gd`           | `Weapon` strategy: envelope, target pick, prepare shot     |
| `scripts/missile.gd`                          | In-flight entity: orbit propagation, proximity, detonation |
| `scripts/missile_spawner.gd`                  | Lifecycle: active list, reservation map, detonation VFX    |
| `scripts/combat_controller.gd`                | Manual-fire entry point + non-mutating target query        |
| `scripts/mass_center_system.gd`               | Z-key handler + HUD signal hookup                          |
| `scripts/hud.gd`                              | FIRE MISSILE button + state-machine label / red tint       |
| `scripts/satellite.gd`                        | `has_missile()`, `first_missile_weapon()`, ammo accounting |
| `scripts/unit_part.gd`                        | Catalog: `missile_default / advanced / elite`              |
| `scripts/research.gd`                         | Missiles research chain (tier 0 cost = 0)                  |
| `scripts/player_loadout.gd`                   | Default-fleet seed (1 missile launcher per starting roster)|
| `scripts/spawn_director.gd`                   | Build branch in `_build_weapons`                           |
| `scripts/unit_config.gd`                      | Damage-summary keys + magazine mass                        |
| `scenes/main.tscn`                            | `MissileSpawner` scene node                                |
| `project.godot`                               | `fire_missile` input action mapped to Z                    |
| `tests/test_lambert_solver.gd`                | Lambert math invariants                                    |
| `tests/test_missile_weapon.gd`                | Weapon-class behaviour                                     |
| `tests/test_missile.gd`                       | Entity tick / detonation paths                             |
| `tests/test_missile_spawner.gd`               | Reservation lifecycle                                      |
| `tests/test_combat_controller.gd`             | Manual-fire integration                                    |

The game is **not** a simulator — the physics below are deliberately
simple. Numbers are tuned to be within an order of magnitude of real
physics while staying readable on a single dial.


## Gameplay framing

Missiles are the **high-cost, high-impact, operator-driven** weapon
in the fleet's loadout:

  * **One-shot kill on most LEO satellites** within a 50 km lethal
    envelope (damage 500 HP vs default 100 HP target).
  * **Slow** — flight time 30 s to 30 min depending on geometry.
  * **Small magazine** — 8 missiles per launcher, can't be refilled
    mid-mission.
  * **Manual fire only** — the combat controller's auto-fire loop
    explicitly skips MissileWeapons. Every shot is a deliberate
    operator decision (button click or Z key).
  * **Auto-targeted** — once fired, the missile picks the lowest-dv
    reachable enemy itself. The operator picks *when* to spend the
    warhead; the physics picks *who* receives it.

This shape exists because in 2-body Keplerian mechanics, an "auto-fire
when reachable" rule produces frequent, often-wasteful shots — every
slow orbital window looks reachable. Manual fire is the lever that
makes each warhead matter.


## Physics calibration

### The Lambert problem

In space a missile cannot fly straight at its target. To reach a
target at a future time `TOF`, the missile must launch with a velocity
`v1` such that the conic arc through `(launch_r, v1)` arrives at the
target's predicted position `r2(TOF)` exactly at time `TOF`. Given
`r1`, `r2`, and `TOF`, solving for `v1` is **Lambert's problem**.

We use the **universal-variable** formulation (Vallado, *Fundamentals
of Astrodynamics and Applications*, 4th ed., Algorithm 5.2). The
universal variable `psi = xi² / alpha` lets a single bisection loop
cover elliptic, parabolic, and hyperbolic transfers without branching.
The Stumpff `c2` and `c3` functions are reused from
`MassCenterOrbit` — the same propagator runs the rest of the game's
orbital state, so missile transfers and live orbits stay numerically
consistent.

**Why bisection, not Newton?** Bisection's convergence is guaranteed
given a valid bracket; Newton is faster (≈3× in Izzo's algorithm) but
needs a careful initial guess to avoid divergence on edge geometries.
At ~1 ms per solve in GDScript and event-driven invocation (not
per-tick), the extra speed wasn't worth the implementation risk.

**Edge cases the solver rejects** (returns `ok = false`):

  * `r1` and `r2` antipodal (cos Δν = -1 to within `COLLINEAR_EPS`).
    The transfer plane is undefined. Search wrappers sample multiple
    TOFs so a single degenerate sample is invisible.
  * TOF too short to be physically reachable. Detected as
    bracket-collapse during bisection.
  * Non-finite inputs (NaN, infinity).
  * Convergence failure within `MAX_ITER = 100` bisection steps.

### 100 MT thermonuclear warhead

The MVP warhead is calibrated as **100 megatons TNT equivalent**:

  * Yield: 4.184 × 10¹⁷ J ≈ 420 PJ.
  * Energy partition in vacuum (Teller-Ulam, rough):
      * Soft X-rays: ~75 % of yield, propagates at c.
      * Neutron flux: ~5–15 %.
      * Vaporised casing / plasma: ~10–15 % (stays near source).
      * Gamma + visible: < 2 %.

In space, **soft X-rays dominate the kill mechanism** — there's no
atmosphere to transmit a shock wave. The "thermal radiation pulse"
familiar from atmospheric tests doesn't exist in vacuum (it's actually
a re-emitted optical pulse from atmosphere-absorbed X-rays).

### Lethal radius derivation

X-ray fluence falls as inverse-square:

```
F(R) = E_x / (4π R²)
```

with `E_x = 0.75 × 4.184e17 = 3.14 × 10¹⁷ J`.

Damage thresholds, by target hardening:

| Target class                                  | Fluence threshold      | Lethal radius |
| --------------------------------------------- | ---------------------- | ------------- |
| Soft sensor platform (exposed optics, panels) | ~100 J/cm² = 10⁶ J/m²  | ~160 km       |
| Typical unhardened satellite                  | ~1 kJ/cm²  = 10⁷ J/m²  | **~50 km**    |
| Hardened military comsat (shielded)           | ~10 kJ/cm² = 10⁸ J/m²  | ~16 km        |

The MVP calibrates to the middle row (`BLAST_RADIUS_KM = 50`). Future
tier-3 hardened enemies would survive a near miss without retuning;
softer sensor classes would be vulnerable at extreme range.

### Damage scaling

`MissileWeapon.DAMAGE_HP = 500` is chosen so a default 100 HP target
dies with 5× margin. The HP currency (5 MJ per HP, defined in
`Weapon.J_PER_HP`) is shared across all weapons, so a missile inside
the blast radius dumps as much damage as ~5 railgun slugs. The
fuze-to-damage relationship is binary inside the radius; from 1× to
2× the radius, damage scales linearly down to zero (handled in
`Missile.tick`'s "closest approach passed within near-miss range"
branch).

### Why these specific numbers?

  * **MAGAZINE_SIZE = 8** — small enough that the operator weighs
    each shot; large enough that one launcher can engage a wave.
  * **PROPELLANT_PER_MISSILE_KG = 150 / MISSILE_DRY_MASS_KG = 100 /
    MISSILE_ISP_S = 450** — Tsiolkovsky gives Δv ≈ 4 km/s, enough to
    reach most LEO-band targets in a 30-minute TOF window but not
    enough to escape Earth or chase a high-energy target.
  * **MIN_TOF_SEC = 30, MAX_TOF_SEC = 1800** — search bracket. 30 s
    excludes degenerate near-collision geometries; 1800 s is half a
    typical LEO period, beyond which the energy cost grows fast.
  * **ENERGY_PER_LAUNCH_J = 10 GJ** — fire-control / IMU spin-up
    pulse. ~1 sim-second of default reactor output per shot.


## Architecture and data flow

```
                   ┌───────────────────────────────┐
                   │   project.godot               │
                   │   action: fire_missile → Z    │
                   └──────────────┬────────────────┘
                                  │ Input.action_just_pressed
┌────────────────────┐            ▼
│ HUD                │   ┌─────────────────────────┐
│ FIRE MISSILE btn   │   │ MassCenterSystem        │
│ click → signal     │──►│ _try_fire_missile_from  │
│                    │   │   _selected()           │
│ _missile_button_   │   └──────────────┬──────────┘
│   state(...)       │                  │
│                    │                  ▼
└──────┬─────────────┘   ┌─────────────────────────┐
       │                 │ CombatController        │
       │ orbital_set.    │  try_fire_missile_for() │
       │   combat_       │  has_missile_target_for │◄──┐
       │   controller    │                         │   │
       └─────────────────►│                         │   │
                          └──────────────┬──────────┘   │
                                         │              │
                                         ▼              │
                          ┌─────────────────────────┐   │
                          │ MissileWeapon           │   │
                          │  pick_target() ──┐      │   │ HUD red-tint
                          │  prepare_shot()  │      │   │ query (10 Hz)
                          │                  ▼      │   │
                          │ ┌──────────────────────┐│   │
                          │ │ LambertSolver        ││───┘
                          │ │  find_best_intercept ││
                          │ └──────────────────────┘│
                          └──────────────┬──────────┘
                                         │ pending Dict
                                         ▼
                          ┌─────────────────────────┐
                          │ MissileSpawner          │
                          │  spawn() ─────► Missile │
                          │  tick() each            │   ─┐
                          │    physics tick         │    │ propagate
                          │  _reserved_target_iids  │    │ + proximity
                          │  _missiles[]            │    │ check
                          │                         │   ◄┘
                          │  on detonation:         │
                          │   ImpactExplosion       │
                          │   ↓ in-tree, 0.5s VFX   │
                          └─────────────────────────┘
```

### Manual fire sequence (end-to-end)

  1. Operator presses Z **or** clicks FIRE MISSILE button.
  2. Both paths invoke `MassCenterSystem._try_fire_missile_from_
     selected()` (HUD button via `fire_missile_requested` signal,
     Z key via `Input.is_action_just_pressed` in `_input`).
  3. MCS resolves the currently selected satellite, checks
     `planning_mode` (no firing during planning-pause), and calls
     `combat_controller.try_fire_missile_for(sat, real_satellites,
     sim_time, tick_delta)`.
  4. CombatController iterates the attacker's weapons. For each
     `MissileWeapon` that `can_fire()` (energy + ammo + not
     overheated + not surface):
     a. Filters out targets reserved by other inbound missiles.
     b. Calls `MissileWeapon.pick_target(attacker, candidates,
        sim_time)`.
  5. `MissileWeapon.pick_target` iterates candidates:
     a. Evicts expired cache entries (TTL = 5 sim-sec).
     b. Per candidate, applies cheap envelope filter (team, alive,
        max-reach distance) then either reads the cache or runs
        `LambertSolver.find_best_intercept()` (12 coarse + 6 fine
        TOF samples) and caches the result.
     c. Returns the candidate with the lowest `dv_mag` within the
        4 km/s per-shot budget.
  6. If a target was picked, `CombatController._fire_missile()`
     calls `MissileWeapon.prepare_shot()`:
     a. Re-solves Lambert against the attacker's *current* orbit
        state (the cache may be a few sim-sec stale).
     b. Decrements ammo, drains energy, fills heat capacity (one-shot
        overheat latch — single shot then cool).
     c. Calls `attacker.recompute_mass()` so the launcher's wet mass
        drops by one missile's worth.
     d. Returns a `pending` Dict carrying launch state.
  7. `MissileSpawner.spawn(attacker, target, pending, sim_time)`:
     a. Constructs a `MassCenterOrbit` from `(launch_r, launch_v)`.
     b. Instantiates a `Missile` Node3D, calls `configure(...)`.
     c. Records the target iid in `_reserved_target_iids`.
     d. Wires an `on_terminate` closure to erase the reservation.
     e. Adds the missile as a scene child — `Missile._ready()` fires
        and the visual cube + predicted-path arc render.

### Per-tick flight

`MassCenterSystem._physics_process` calls
`missile_spawner.tick(sim_delta, sim_time)` once per physics tick.
The spawner iterates active missiles; each missile's `tick()`:

  1. Propagates its own orbit by `sim_delta` via the universal-
     variable propagator.
  2. Checks for sub-surface (`norm_r < BODY_RADIUS_KM`) → terminate
     `TERM_SUBSURFACE`, no damage.
  3. Checks expiry (`sim_time >= expiry_sim_time`) → terminate
     `TERM_EXPIRED`, no damage.
  4. Resolves the target via `instance_from_id(target_iid)`; if
     freed / dead / orbit-dead → terminate `TERM_TARGET_LOST`.
  5. Computes current distance `d` to target.
  6. **Primary detonation**: `d < blast_radius_km` →
     `target.take_damage(damage_hp, attacker)`, terminate
     `TERM_DETONATED`. Spawner spawns an `ImpactExplosion` at the
     missile's position.
  7. **Secondary detonation**: `d > prev_distance` (closest approach
     passed) AND `prev_distance < blast_radius` → delayed detonation
     (rare; the proximity fuze fired between physics ticks).
  8. **Miss**: `d > prev_distance` AND `prev_distance >= blast_radius`
     → terminate `TERM_MISSED`, no damage.

### Termination reason taxonomy

| Code                       | Meaning                          | Damage applied? | VFX? |
| -------------------------- | -------------------------------- | --------------- | ---- |
| `TERM_DETONATED`           | Inside blast radius              | ✓               | ✓    |
| `TERM_MISSED`              | Closest approach > blast radius  | ✗               | ✗    |
| `TERM_EXPIRED`             | TOF + 30 s slack elapsed         | ✗               | ✗    |
| `TERM_SUBSURFACE`          | Orbit decayed into body          | ✗               | ✗    |
| `TERM_TARGET_LOST`         | Target killed / freed in flight  | ✗               | ✗    |
| `TERM_PROPAGATION_FAILED`  | Numerical death in propagator    | ✗               | ✗    |


## Reservation map

`MissileSpawner._reserved_target_iids` is a `Dictionary<int, true>`
recording every target currently being engaged by an in-flight
missile. Combat controller consults it before picking a target
(`_exclude_missile_reserved` in `process_combat` and
`try_fire_missile_for`), so two launchers never spawn missiles at the
same enemy in the same tick.

The reservation is released by the `on_terminate` closure attached
to each missile at spawn time. The closure runs on every termination
cause (detonate / miss / expire / subsurface / target lost), so the
slot opens whether or not the missile actually killed its target.

**Design note**: this is the second reservation map in the codebase
(railgun-slug has its own at `CombatController._reserved_target_iids`).
They're independent — a railgun can fire on a target already targeted
by a missile, which is intentional (different weapons, different
purposes). If you ever add a third slow-projectile weapon, factor the
pattern into a shared service.


## HUD button state machine

`HUD._missile_button_state(sat, orbital_set, planning_mode)` returns
one of eight states; only `READY` enables the button and tints it red.
States are evaluated cheapest-gate-first so the Lambert query (the
only expensive check) runs only when everything else passes:

  1. `PAUSED` — planning mode active.
  2. `GROUND_UNIT` — attacker is surface-anchored.
  3. `EMPTY` — `ammo_count <= 0`.
  4. `OVERHEATED` — overheat latch tripped.
  5. `COOLING` — heat > 0 but not latched (residual cooldown).
  6. `CHARGING` — `energy < ENERGY_PER_LAUNCH_J`.
  7. `NO_TARGET` — local gates clear but
     `CombatController.has_missile_target_for()` returned null.
  8. `READY` — all gates clear, target reachable. Red tint applied
     (`Color(1.0, 0.30, 0.30)`).

The button text changes per state ("POWER CHARGING", "NO TARGET IN
RANGE", etc.) so the operator can read why a click would fail
without consulting documentation.


## Design decisions

These were debated; future refactors should at least understand them
before changing them:

| Decision                                                | Reason                                                                                                       | Reconsider when…                                          |
| ------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------ | --------------------------------------------------------- |
| Manual fire only (auto-fire branch skips MissileWeapon) | Auto-firing every reachable target wastes a small magazine. Operator timing IS the gameplay.                 | Adding a "rapid-fire" missile variant for swarm enemies   |
| Lowest-dv target selection (no operator pick)           | Lambert search per candidate is cheap; the operator's job is *when*, not *who*. Keeps the input model thin.  | Operators report missing strategic flexibility            |
| Single-burn intercept (no mid-course correction)        | MVP targets don't manoeuvre. Adding a 2nd burn doubles complexity and the operator wouldn't notice.          | Targets gain evasion logic                                |
| Bisection Lambert (not Newton / Izzo)                   | Guaranteed convergence on edge geometries beats 3× speedup at this call volume.                              | Lambert call rate becomes a profiler hot-spot             |
| Re-solve in `prepare_shot` (cache only for `pick_target`)| Cached `v1` is launch-position-dependent; attacker drift in a 5 sim-sec TTL is up to ~600 m at LEO speed.    | Cache TTL drops to 0 (every call is a fresh solve anyway) |
| Deferred damage application (`prepare_shot` + missile arrives)| Mirrors the railgun-slug pattern. Damage at fire-time would teleport HP changes across the screen.       | Switching to instant-effect "beam" weapons                |
| Two reservation maps (railgun + missile, independent)   | A railgun can engage a target also targeted by a missile (different weapons, different purposes).            | A third slow-projectile weapon appears                    |
| `Missile` is `Node3D`, not `RefCounted`                 | Needs scene presence for body mesh + predicted-path render. Tests instantiate without adding to tree.        | The renderer side becomes a separate service              |
| Visual blast radius (`DETONATION_RADIUS_KM = 2500`) ≠ physics blast radius (`BLAST_RADIUS_KM = 50`) | At scene scale 1 unit = 1000 km, a 50 km sphere is 5 pixels. Asteroid-impact precedent uses VISUAL_GAIN.| Yield-scaling math wants them linked                      |
| Z key for `fire_missile` (not L, M, F)                  | L = `toggle_laser_targeting`, M = `add_asteroids`, F = `freelook`. Z was free and reads as a trigger.        | Existing binds are remapped                               |


## Refactor playbook

Cost estimates from auditing the touch points. "Low" risk means the
test surface catches regressions; "Medium" / "High" means the test
suite would need extension first.

### Easy (single-file changes)

| Change                                                              | Files                                          | Risk |
| ------------------------------------------------------------------- | ---------------------------------------------- | ---- |
| Tune yield / blast radius / fuel budget                             | `weapons/missile_weapon.gd`                    | very low |
| Swap Lambert algorithm (Izzo, Gooding, etc.)                        | `lambert_solver.gd`                            | very low — API contract stable |
| Different visual cube / explosion colour / size                     | `missile.gd` and/or `missile_spawner.gd`       | very low |
| Add mid-course correction at TOF/2                                  | `missile.gd` (add a 2nd Lambert solve in tick) | low |
| Change `BLAST_RADIUS_KM` falloff shape                              | `missile.gd` (the closest-approach branch)     | low |
| Different propulsion (Isp, propellant fraction)                     | `weapons/missile_weapon.gd` (already parameterized) | very low |

### Medium (4-5 files)

| Change                                              | Files                                                                          |
| --------------------------------------------------- | ------------------------------------------------------------------------------ |
| Player-clickable target (click an enemy on the 3D scene to designate) | `hud.gd`, `mass_center_system.gd`, `combat_controller.gd`, `weapons/missile_weapon.gd` |
| Missiles become destructible by lasers / railguns   | `combat_controller.gd`, `missile.gd` (add HP, take_damage), tests              |
| Multi-stage missiles (boost + glide phases)         | `missile.gd` (new state machine), possibly subclass                            |
| Auto-fire opt-in flag (per-weapon `auto_fire: bool`)| `weapons/missile_weapon.gd`, `combat_controller.gd`, `hud.gd` (toggle)         |

### Higher-touch (refactor opportunities)

| Change                                                            | Notes |
| ----------------------------------------------------------------- | ----- |
| Continuous-burn guidance (proportional navigation, no Lambert)    | Rewrites `missile.gd` tick. `lambert_solver.gd` becomes optional / removable. Mental model shift. |
| Anti-missile defenses (point-defense)                             | Missile becomes targetable: extends `CombatController._collect_targetable`, gives missile HP, links to existing target list. ~4–5 files. |
| Yield-scaling math (BLAST_RADIUS derived from warhead mass)       | Need to link `MissileWeapon.BLAST_RADIUS_KM` and `MissileSpawner.DETONATION_RADIUS_KM` — currently independent constants. |
| Unified inbound-projectile reservation service                    | Pull `_reserved_target_iids` out of both `CombatController` and `MissileSpawner` into a shared `ProjectileReservations` autoload. |


## Known smells / refactor hooks

Places where future work would tidy the design:

  1. **`Weapon.fire()` returns `false` on `MissileWeapon`**. The base
     class assumes synchronous fire returns bool. Missiles need async
     (damage on arrival), so the override is essentially dead. A
     formal two-phase weapon API (`prepare` + `commit`) would unify
     the railgun-slug and missile paths.
  2. **Duck-typed access from HUD to MassCenterSystem**. `hud.gd`
     reads `orbital_set.combat_controller`, `orbital_set.sim_time`,
     `orbital_set.satellites` through an untyped `Node` parameter.
     If MCS renames any of those, the static checker stays silent.
     Apply `class_name`-based typing or pass the typed refs through
     `update_hud()`.
  3. **Per-class branches in `Satellite.total_ammo_mass_kg`**.
     Currently a chain of `if w is RailgunWeapon ... elif w is
     MissileWeapon ...`. Add a virtual `Weapon.ammo_mass_kg()
     -> float` method; default returns 0; subclasses override.
  4. **Default fleet composition is per-slot hardcoded** in
     `player_loadout.reset_units()`. A declarative
     `DEFAULT_FLEET_ROSTER` array of `(altitude, plane, weapon_part_id)`
     tuples would scale better.
  5. **Cache lives on `MissileWeapon` instance**. If a non-weapon
     source ever spawns a missile (cutscene, scripted event), there's
     no cache. Minor — but extracting the cache to the spawner would
     let any missile source benefit.
  6. **Visual constants split across files**. `BLAST_RADIUS_KM` lives
     in `missile_weapon.gd`; `DETONATION_RADIUS_KM` lives in
     `missile_spawner.gd`; cube size / flash period / path colour
     live in `missile.gd`. Reasonable today; if yield-scaling becomes
     a feature, centralise in a `WarheadProfile` resource.
  7. **No `MissileWeapon.fire_missile()` integration test against a
     full scene-tree boot**. Pure-data tests pass, but the HUD →
     button → signal → MCS → CC → spawner chain has no end-to-end
     coverage. Adding one with `SceneTree.process_frame.await` would
     catch regressions in the Z-key / button paths.


## Testing strategy

Each layer is unit-tested independently. The end-to-end chain
(HUD button → signal → CombatController) is not exercised by the
test suite today; see smell #7 above.

| Test file                          | What it pins                                                                                          |
| ---------------------------------- | ----------------------------------------------------------------------------------------------------- |
| `test_lambert_solver.gd`           | Self-consistency (propagate then solve), round-trip propagate, edge rejection (antipodal, zero TOF), search wrapper coverage |
| `test_missile_weapon.gd`           | Envelope filtering, can_fire gates, pick_target lowest-dv selection, cache TTL, prepare_shot bookkeeping, pending dict shape |
| `test_missile.gd`                  | All six termination reasons, on_terminate fires exactly once, attacker-death-still-damages           |
| `test_missile_spawner.gd`          | Spawn-then-tick removes terminated, reservation map lifecycle, clear_all                              |
| `test_combat_controller.gd`        | Manual-fire-only invariant (`test_process_combat_does_not_auto_fire_missiles`), try_fire_missile_for end-to-end, reservation blocks second launcher |

**Tolerances**:

  * Lambert velocity recovery: ~5 m/s (propagator drift over a
    quarter period dominates the budget).
  * Round-trip position: ~0.5 km (Vector3 float32 + bisection +
    propagator drift).
  * Missile orbit propagation: identical to `MassCenterOrbit`'s
    tolerance budget (~5 km after a full period).

Tests run via `make test` (CI-gated). The headless test runner
leaks Node3D children (Missiles, OrbitalPaths) — same pattern other
in-tree visual tests carry; harmless because the process exits
seconds later.
