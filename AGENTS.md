# AGENTS.md

Operating instructions for any agent working in this repo.
Read this first; it captures decisions that aren't obvious from a fresh
read of the code, and gotchas that have already cost time once.

## Project at a glance

- **Stack**: Godot 4.3, GDScript only. No C#, no native modules.
- **Renderer**: GL Compatibility (set in `project.godot`). Targets
  Chromebook (Crostini / llvmpipe), Android, iOS, and desktop. **Don't
  switch to Forward+/Mobile** without explicit user approval — the
  Chromebook constraint is the reason Compatibility was chosen.
- **Coordinate convention**: **Z-up** world (orbital-mechanics
  convention). The MassCenter `SphereMesh` is rotated once at `_ready` so
  its texture poles align with world Z, then composed with axial tilt
  and the daily spin.
- **Units**: simulation is in km and km/s; scene units are
  `1 unit = 1000 km` (`Satellite.SCENE_SCALE`).

Run / test:

    make run     # launch the main scene
    make edit    # open the editor
    make test    # headless unit tests (CI runs this)
    make clean   # drop .godot/ import cache

## Where things live

    godot/
      project.godot         # GL Compatibility, input map, strict warnings
      scenes/main.tscn      # Root scene
      scripts/
        earth_orbit.gd      # Pure RefCounted Keplerian propagator
        earth_system.gd     # Top-level controller, planning mode
        satellite.gd        # Unit instance: state + marker + path
        orbital_path.gd     # Cached ArrayMesh orbit visualiser
        mass_center.gd            # Procedural MassCenter, day/night/clouds shader
        orbit_camera.gd     # Free-look Z-up camera
        hud.gd              # Throttled BBCode info + targeting lines
        los_check.gd        # Pure RefCounted ray-vs-sphere
      shaders/planet.gdshader
      resources/3D/mass_center/   # Day/night/normal/clouds JPEGs + .import
      tests/
        framework.gd        # Tiny RefCounted assertion harness
        run_tests.gd        # SceneTree entry — discovers test_*.gd
        test_*.gd

## Gameplay vision (read README.md for full text)

The product is **RTS + tower defense, physics-driven**. The MVP is
**autonomous tower defense** — units auto-fire when targets are in
range, players just launch and lightly position. Manual maneuvers and
fire control come later. PvP is a long-term goal but **deferred** until
the prototype is fun.

When implementing new gameplay, ask: *does this assume player
micromanagement?* If yes, gate it behind a feature flag or a separate
input mode — don't make the MVP depend on it.

## Architectural rules

These were learned the hard way; please respect them.

1. **`class_name` + `preload()` for cross-script references.** Type
   resolution via `class_name` alone fails when the editor's `.godot/`
   cache isn't warm. Every cross-file reference uses a top-of-file
   `const Foo = preload("res://scripts/foo.gd")`. Strongly type
   `@onready` vars and parameters too.
2. **Cache meshes and materials.** `OrbitalPath` builds one
   `ArrayMesh` + one `StandardMaterial3D` and rewrites the vertex
   buffer in place when elements drift past tolerance. **Never**
   allocate `ImmediateMesh` or `StandardMaterial3D` per frame — that
   pattern crashed an earlier port within a minute.
3. **Sim runs in `_physics_process`** at a fixed tick. `_process` is
   for camera + HUD only. HUD BBCode rebuilds throttled to ~10 Hz.
4. **Defensive orbit propagation.** `EarthOrbit.propagate()` subdivides
   large `tof`, validates `is_finite` on every step, and returns
   `false` rather than emitting NaN. Satellites flag `orbit_alive =
   false` on a failure so the renderer never sees NaN.
5. **Time factor is clamped and rate-scaled by `delta`** so holding
   speed-up doesn't blow up the propagator.
6. **Use Godot's import pipeline for textures** (`load(...) as
   Texture2D`). Do not `Image.load_from_file()` at runtime — it bypasses
   compression and produces uncompressed VRAM textures.

## GDScript conventions

- **Strict warnings**: `gdscript/warnings/inference_on_variant=2`
  (error). The classic footgun is `var x := typed_array.pop_back()` —
  `pop_back()` returns Variant even on `Array[T]`. Annotate the type:
  `var x: T = arr.pop_back()`.
- **`project.godot` comments use `;`**, not `#`. The ConfigFile parser
  rejects `#`.
- **String formatting**: GDScript's `%` operator supports
  `%s %c %d %o %x %X %f %v` — **no `%g`**. Use `%f` or `%.10f`.
- **Two-form clone for satellites**: `clone_from(other)` copies
  everything (use on planning-mode entry); `clone_orbit_from(other)`
  copies only orbital state and preserves operator-queued thrust (use
  every physics tick during planning).

## Test discipline

- Headless unit tests live in `godot/tests/test_*.gd` and run via
  `make test`. CI gates merges on it.
- Pure-math classes (`EarthOrbit`, `LosCheck`) extend `RefCounted` so
  they're testable without a SceneTree. **Keep them that way** — when
  adding new pure-math primitives (e.g. weapon trajectory solvers,
  Hohmann transfer calculators), make them RefCounted and write the
  tests alongside.
- Rendering / scene logic is harder to unit-test; CI does **not** boot
  the main scene today. If you add scene smoke tests, use Xvfb.
- Floating-point tolerances: orbit math passes at ~1e-6 because
  `Vector3` components are 32-bit even though GDScript `float` is
  64-bit. Don't write tests at 1e-9.

## Forward-looking modularisation

When in doubt, prefer code shapes that will survive these planned
expansions without rewriting orbital math:

- **Multi-map support**. `MU`, planet radius, surface-launch
  availability, and texture set are all map parameters — *not*
  constants in `EarthOrbit` or `MassCenter`. When you touch
  `EarthOrbit.MU`, push back: it should become a constructor / scope
  parameter, not a constant.
- **Server authority later**. Keep simulation, player intent, and
  rendering separable. A "satellite" today owns its propagation; long
  term it should be possible to make propagation server-authoritative
  and the local instance a thin viewer. Don't bake input handling into
  `Satellite`; route through `EarthSystem` (or eventually a network
  client).
- **Data-driven unit costs**. Resource ratios for unit production must
  be exposed as Godot Resources / dictionaries, not hardcoded — balance
  work will dominate later development.
- **Weapon types as a strategy interface**. Energy / kinetic / missile
  share "is this target valid right now?" logic. A small base class
  with an `is_target_in_engagement_envelope(self, other) -> bool` and
  `fire(self, target)` method is the right shape — adding a new weapon
  type should be one new file, not a `match` cascade across the
  codebase.

## What to deprioritise

- PvP / networking. Don't build a server yet. Do keep the seams clean.
- Unit micromanagement UX. The MVP's success criterion is "novice
  player launches units and has fun". Maneuver coordination, fire
  control, and per-unit selection panels come after that.
- Visual polish on legacy assets. The repo has been pruned —
  unreferenced models / fonts / images were removed. Don't restore
  them; build new assets when needed.

## Recurring gotchas

- `Array.pop_back()` returns Variant on a typed array → use explicit
  type annotation.
- `SphereMesh` poles are local Y; the world is Z-up — don't spin MassCenter
  about Z without first applying `POLE_ALIGN`.
- The C++ tradition was `4096_bump.jpg` for height; we use the normal
  map only. Don't try to wire bump and normal together — pick one.
- `.import` sidecars must be committed; the compiled `.ctex` files
  must not (they live under `.godot/imported/` and are gitignored).
- Make targets depend on `import` so first-run users don't see "Failed
  loading resource" — Godot's import is idempotent and fast.
