# Orbital Mechanics Game

A real-time Keplerian orbit simulator built in Godot 4. Targets desktop, web,
Android, and iOS. Uses the GL Compatibility renderer so it runs on Chromebook
(Crostini / llvmpipe) and mobile GPUs without requiring Vulkan.

## Quick start

Requires Godot 4.3 on `PATH` (override with `GODOT=/path/to/godot`).

    make run     # launch the main scene
    make edit    # open the editor
    make test    # headless unit tests
    make clean   # drop the import cache

CI runs `make test` on every push and PR — see `.github/workflows/godot-ci.yml`.

## Layout

    godot/
      project.godot         # GL Compatibility, input map, strict warnings
      scenes/main.tscn      # Root scene
      scripts/              # All gameplay logic
      shaders/planet.gdshader
      resources/            # MassCenter textures (with .import sidecars)
      tests/
        framework.gd        # RefCounted assertion harness
        run_tests.gd        # SceneTree entry — discovers test_*.gd
        test_*.gd

## Architecture notes

- **Coordinate convention**: Z-up world (orbital-mechanics convention). The
  MassCenter `SphereMesh` is rotated once at `_ready` so its texture poles align
  with world Z, then composed with a 23.5° axial tilt and the daily spin.
- **`class_name` + `preload()` for cross-script references** so type
  resolution doesn't depend on the editor's `.godot/` cache being warm.
  `@onready` vars and parameters are strongly typed.
- **Sim runs in `_physics_process`** at a fixed tick rate; `_process` is
  reserved for camera + HUD. HUD BBCode rebuilds throttled to ~10 Hz.
- **Cached meshes & materials**. `OrbitalPath` builds a single `ArrayMesh`
  + `StandardMaterial3D` once and rewrites the vertex buffer in place only
  when orbital elements drift past tolerance. The marker mesh + material
  on each `Satellite` is built once in `_ready` and reused.
- **Defensive orbit propagation**. `EarthOrbit.propagate()` subdivides
  large `tof` values, validates `is_finite` on every step's inputs and
  outputs, and returns `false` rather than escaping NaN. Satellites flag
  `orbit_alive = false` on a failure so the renderer never sees NaN.
- **Time factor is clamped and rate-scaled by frame delta** so holding
  speed-up doesn't blow up the propagator.
- **Strict GDScript warnings**. `inference_on_variant` is promoted to
  error in `project.godot` so `var x := typed_array.pop_back()` (which
  silently returns Variant in 4.3) fails at parse time.

## Goals

- [x] Basic orbital physics simulation in 3D
- [x] Refactor with classes so an arbitrary number of orbits may be added
- [x] Per-unit selection — selected unit and orbit colored differently
- [x] LOS line from selected unit to every other unit, colored by whether
  it intersects MassCenter
- [x] Distance and relative velocity readout for every targeted unit
- [x] Consistent time ticking — propagation does not accumulate drift
- [x] One derivation of orbital elements per R-V update
- [x] Planning mode — clone orbital state, scrub through "what if I'm
  here in N seconds"
- [x] Tilt MassCenter's axis 23.5° (obliquity of the ecliptic)
- [ ] Calculated thrust UI: display pitch/yaw/ΔV/ΔT, queue maneuvers
- [ ] Camera snap-to-target locations and pitch/yaw-only orbital view
- [ ] Galactic background sphere
- [ ] Distinct color/style for projection (planning) data

### Performance & mobile readiness backlog

Deferred but blocking on a real mobile build; track here so they don't get
lost in the issue queue.

- [ ] **Mobile texture variants for the MassCenter shader.** The four 4096²
  JPEGs (`albedo`, `night`, `normal`, `clouds`) total ~80 MB of VRAM
  after compression — fine on desktop, OOM on a 2 GB Android device.
  Ship 1024²/2048² ETC2/ASTC variants selected at startup via
  `OS.has_feature("mobile")`, wired through the existing `*_path`
  exports on `mass_center.gd`. Same change should drop the persistent
  `_albedo_image` in `earth_system.gd` (a fully-decompressed 4096²
  Image kept in RAM just to read one pixel per impact) — replace with
  a small landmask texture or load-then-free at impact time.
- [ ] **Extract `SpawnDirector` and `CombatController` from
  `earth_system.gd`.** The controller is ~1000 lines mixing input,
  spawning, combat scheduling, planning mode, and HUD plumbing.
  Splitting the spawn paths (starting fleet, enemies, asteroids,
  asteroid waves, decaying-orbit body) and the combat loop
  (`_process_combat`, `_pick_target_for_weapon`) into focused nodes
  makes the hot loop profileable in isolation and gives the eventual
  network refactor a clean seam for moving spawn/combat authority to
  a server. Pure refactor — no behaviour change.

## Gameplay

The game is **RTS + tower defense, with orbital physics as the core
mechanic**. The marketing surface and GUI should feel like tower defense
— mass-market appeal, low entry barrier — while the underlying mechanics
are RTS-flavored and physics-driven. The MVP is autonomous tower defense
(units fire on their own); manual orbital maneuvers and fire control are
follow-on capabilities.

### Units and weapons

Satellites are the units. Every unit fires automatically when a valid
target is in range; players intervene to launch new units, position
them, and (later) coordinate maneuvers or fire control.

- **Energy weapons** — strict line-of-sight only in normal gravity.
  Photons go straight; if the planet, another body, or terrain occludes
  the target, no shot.
- **Kinetic weapons (railguns)** — LOS at close range; at long range the
  projectile follows a noticeable parabolic / orbital arc and can hit
  beyond a strict-LOS check. The transition from "treat as straight" to
  "must integrate trajectory" is a tuning knob.
- **Missiles** — full satellites in their own right. They're kamikaze
  units that deal damage when they get within a kill radius of the
  target. Their orbital state is simulated like any other satellite.

### Economy

Players generate resources (**metals**, **rare metals**, **chemicals**,
**exotics**) at a fixed rate during prototyping. Resource competition
mechanics come later. Players have:

- A **production capacity** — consumes resources to build queued units.
- A **launch capacity** — places built units as satellites in orbit.

Both capacities are fixed at prototype; later they become upgradable /
contested. Unit cost is a per-resource ratio determined by the unit's
weaponry, thrust capability, and health. **These ratios must be
data-driven and easy to tune** — balance work will dominate later.

### PvE (the prototype's primary gameplay)

Enemy satellites populate the arena via these spawn behaviors:

1. Appear in orbit and stay in orbit.
2. Enter from outside the arena, slingshot around the gravitational
   centre, and exit the arena.
3. Enter from outside and decelerate into a captured orbit.
4. Launch from the planet's surface into orbit.
5. After entering or appearing, stay in orbit for a limited time, then
   change velocity enough to escape.

### PvP (deferred)

PvP is a major element of the final product but is **deprioritized for
prototyping** because it requires a game server. The intended design:
each player chooses a maximum time-dilation factor; the server
propagates the world at the minimum of the two. Each client is a viewer
of server-authoritative orbits.

We aren't building the server yet, but **code separation must respect
that future**: keep simulation, intent, and rendering distinct so
authority can later move to a server with no rewrite of the orbital
math.

### Maps

The central body is **not** fixed to MassCenter. Future maps include black
holes, neutron stars, red giants, gas giants (some with rings), smaller
rocky planets, etc. Implications:

- **Gravity is not constant between maps.** `MU` and the planet's
  visual/collision radius must be map parameters, not constants buried
  in `EarthOrbit`.
- Some maps have no surface to launch from — production / launch
  capacity rules need a "supports surface launch?" flag per map.
- Renderer should pick body appearance (texture set, ring system,
  accretion disc shader for black holes) by map descriptor.

### Difficulty curve

- **Novice play (MVP)** — launch units, watch them auto-engage, earn
  points. No required micromanagement.
- **Intermediate** — light positional adjustments to optimise coverage
  or extend engagement windows.
- **Advanced** — coordinated orbital maneuvers, deliberate fire control,
  resource-aware build orders.

These mechanics inform architecture even where they aren't yet
implemented; reserve seams now so each layer can drop in cleanly.
