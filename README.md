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
      resources/            # Earth textures (with .import sidecars)
      tests/
        framework.gd        # RefCounted assertion harness
        run_tests.gd        # SceneTree entry — discovers test_*.gd
        test_*.gd

## Architecture notes

- **Coordinate convention**: Z-up world (orbital-mechanics convention). The
  Earth `SphereMesh` is rotated once at `_ready` so its texture poles align
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
- [x] Per-ship selection — selected ship and orbit colored differently
- [x] LOS line from selected ship to every other ship, colored by whether
  it intersects Earth
- [x] Distance and relative velocity readout for every targeted ship
- [x] Consistent time ticking — propagation does not accumulate drift
- [x] One derivation of orbital elements per R-V update
- [x] Planning mode — clone orbital state, scrub through "what if I'm
  here in N seconds"
- [x] Tilt Earth's axis 23.5° (obliquity of the ecliptic)
- [ ] Calculated thrust UI: display pitch/yaw/ΔV/ΔT, queue maneuvers
- [ ] Camera snap-to-target locations and pitch/yaw-only orbital view
- [ ] Galactic background sphere
- [ ] Distinct color/style for projection (planning) data

## Gameplay ideas

- Model gameplay on [Ogre](http://www.sjgames.com/ogre/) — asymmetric
  unit distribution: dozens of small nimble units vs. one behemoth.
- Kinetic weapons:
  1. Radically adjust the foe's momentum → forces them to spend fuel to
     restore their flight path.
  2. Firing changes your own ship's momentum equally; depending on
     target geometry and orbital position, firing can be disastrous or
     advantageous.
