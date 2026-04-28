# Repository guide for Claude

Two-player orbital-mechanics game prototype in C++. One human, one (currently
stub) AI; each manages one or more satellites in Earth orbit.

## Build / run / test

```bash
make             # full GL build, output: ./test
make check       # build + run sim unit tests, output: ./run_tests
make tests       # build tests only
make clean       # remove ./test and ./run_tests
```

`./test` requires a display. CI only runs the GL-free `make check`.

`setup.sh` bootstraps source builds of GLEW/GLFW/GLM. On Ubuntu the apt
packages in `.github/workflows/ci.yml` are sufficient — prefer those.

## Layered architecture

The codebase is split into three layers under `src/`. **Direction of
dependencies is one-way: app -> render -> sim.** Sim never includes
anything from render or app. Render never includes anything from app.

```
src/sim/      Pure simulation. No OpenGL. Only glm (header-only).
src/render/   All OpenGL. Wraps sim objects in views that own GL state.
src/app/      GLFW glue + input routing + main loop.
```

Why this matters: when porting to Godot/Unity/web/etc., `src/sim/` is
expected to move verbatim. Anything that drags GL into `src/sim/` is a bug.

### sim layer

- `orbit.{h,cpp}` — `EarthOrbit`, the universal-variable Kepler propagator.
  `vec3D` / `vec4D` are sim's native vector types (separate from glm so
  orbit math doesn't tangle with rendering math). Pure functions, const-correct.
- `satellite.{h,cpp}` + `satellite_spec.h` — `sim::Satellite` owns one
  `EarthOrbit` + a maneuver intent for the next tick. `SatelliteSpec` is the
  launch-time attribute bundle (name, mass, fuel, max thrust, dV per press,
  initial r/v). Add new satellite attributes here, not on `Satellite`.
- `player.{h,cpp}` — `sim::Player` owns satellites via
  `std::vector<std::unique_ptr<Satellite>>` so satellite addresses stay
  stable across `AddSatellite` / `RemoveSelected`. Holds selection,
  team color, and (for humans) the requested time-dilation factor.
- `world.{h,cpp}` — `sim::World` owns players. `EffectiveDilation()` returns
  the min over human players' requested rates (1.0 floor = real time;
  ignores AI). `CloneStateFrom` produces a deep-copy snapshot used by
  the planning-mode shadow.
- `controller.h` + `human_controller.{h,cpp}` + `ai_controller.{h,cpp}` —
  `Controller` is the seam between input/AI policy and the sim.
  `HumanController` carries a per-tick input snapshot (filled by `app/`)
  and is `Tick`'d once per frame. `AiController` is currently a no-op
  scaffold; plug real policy in here.

### render layer

- `satellite_view.{h,cpp}` — owns the cube + ellipse GL buffers for one
  satellite slot. Constructed once, reused across satellites in a pool.
- `world_view.{h,cpp}` — pool of `SatelliteView`s sized to match
  `World::total_satellite_count()` each frame.
- `hud.{h,cpp}` — reads `const sim::World&`. Targeting lines, distance /
  delta-V annotations, controls overlay, time/planning status.
- `cube`, `ellipse_3d`, `line`, `model`, `mesh`, `shader`, `writer`,
  `camera` — generic GL primitives.

### app layer

- `earth.{h,cpp}` — `EarthSystem` is the wiring. Owns a live `sim::World`,
  a `planning_world_` shadow, controllers, the `WorldView` pool, and the
  HUD. Translates GLFW key/mouse events into `HumanController` flags.
- `main.cpp` — GLFW init, the 30 FPS frame loop, calls
  `EarthSystem::processKeys` and `EarthSystem::step(deltaTime)`.

## Decision tree: where does new code go?

- "I need a new orbital quantity / propagation tweak" -> `src/sim/orbit.*`
- "I need a new per-satellite attribute (fuel, sensors, weapon)" ->
  `SatelliteSpec` + `Satellite`. Don't add it to the view.
- "I need a new way the human triggers something" -> add a flag on
  `HumanController`, fill it in `EarthSystem::processKeys`, consume it in
  `HumanController::Tick`. Don't read keys from the sim.
- "I need a new HUD element" -> `render/hud.*`. Read sim state via
  `const sim::World&`; never mutate.
- "I need new AI behavior" -> `src/sim/ai_controller.*`. Mutate
  `Player& self` only.
- "I need a new visual primitive (e.g. a sprite)" -> new file in
  `src/render/`, with `~Foo()` that frees its GL handles.

## Conventions

- `sim::` namespace for all sim types. Render types are in `render::`.
  App-layer types are unscoped (just `EarthSystem`).
- Includes use full project-relative paths: `#include "sim/world.h"`.
  Same-layer includes still use the layer prefix.
- Sim files do not include `<GL/glew.h>`, `<GLFW/glfw3.h>`, or any GL
  header. CI's `test` job has no GL libraries installed; if a sim file
  starts pulling GL headers, the test job fails.
- Comments only when the *why* is non-obvious. Headers carry brief
  per-class purpose; implementation files stay terse.

## Testing

`tests/test_util.h` is a 90-line homegrown framework (no external deps).
Tests live in `tests/test_<area>.cpp`; `test_main.cpp` calls `RunAll`.
Macros: `TEST(suite, name)`, `EXPECT_TRUE/FALSE`, `EXPECT_EQ`, `EXPECT_NEAR`.

```cpp
TEST(world, effective_dilation_takes_min_over_humans) {
  sim::World w;
  w.AddPlayer("A", sim::PlayerKind::Human, glm::vec3(0)).set_requested_dilation(100);
  w.AddPlayer("B", sim::PlayerKind::Human, glm::vec3(0)).set_requested_dilation(20);
  EXPECT_NEAR(w.EffectiveDilation(), 20.0, 1e-9);
}
```

Tests link only `src/sim/*.cpp` + `tests/*.cpp`. Anything that requires GL
goes in render/app and is covered by the `build` CI job (compile only;
the runner has no display so we don't execute the game).

Add a test whenever you add or change sim-layer behavior. The bar for
sim coverage is high because that layer is the part we expect to keep
across an engine port.

## Gotchas

- **Time dilation is sim seconds per real second.** Orbit propagation
  takes seconds. The harness computes `sim_dt = deltaTime *
  EffectiveDilation()`; if you advance with `deltaTime` directly, the
  game runs at real time regardless of the player's setting.
- **Planning mode** clones `world_` into `planning_world_` *every step*
  and advances it by `planning_step_seconds_`. State changes you make to
  `planning_world_` are wiped on the next frame. Don't store ID-based
  references to it.
- **Address stability.** `Player::satellites_` is `vector<unique_ptr>`
  precisely so `Satellite*` outlives a vector resize. Don't change to
  `vector<Satellite>` — references in views/HUD/AI would dangle.
- **GL handle ownership.** `Cube` and `Ellipse3d` delete their VAO/VBO in
  their destructors and have copy/move disabled. Any new render primitive
  with `glGenBuffers` must do the same or it leaks on satellite removal.
- **Old planning bug.** Pre-refactor `OrbitalSet::Clone` did
  `satellites_ = other.satellites_`, which copied `Cube` instances and
  duplicated GL handles. The post-refactor `World::CloneStateFrom` only
  copies sim data; views are managed separately. Don't reintroduce the
  shortcut.

## Game design context (for future edits)

- Two players, asymmetric (Ogre-inspired): one big unit vs many small.
  Currently both sides have the same default spec; differentiation lives
  in `SatelliteSpec` and (eventually) controller policy.
- Kinetic weapons are planned: firing imparts dV on both target and
  shooter, so positioning matters. No weapon model exists yet.
- Real-time-floor is a hard rule from the user: time can be sped up but
  never below 1.0x. Enforced in `Player::set_requested_dilation`.

## Out of scope (for now)

- Bespoke graphics work; cubes are intentional placeholders.
- Networking; second human player is a future feature, expected to be
  modeled by a remote `HumanController` whose flags are filled by
  network input rather than GLFW.
