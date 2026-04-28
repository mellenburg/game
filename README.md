# Orbital Mechanics Game

A real-time Keplerian orbit simulator. The original implementation under `src/`
is C++ + OpenGL; the cross-platform target lives under `godot/` (Godot 4) and is
the path forward for Chromebook / Android / iOS.

## Godot project (`godot/`)

Targets desktop, web, Android, and iOS. Uses the GL Compatibility renderer so
it runs on Chromebook (Crostini / llvmpipe) and mobile GPUs without Vulkan.

Run with the editor or:

    make godot-run               # opens the project window
    make godot-test              # headless unit tests
    GODOT=~/godot/godot make godot-test    # if Godot isn't on PATH

CI runs `godot --headless --quit --script res://tests/run_tests.gd` on every
push and PR — see `.github/workflows/godot-ci.yml`.

### Layout

    godot/
      project.godot         # GL Compatibility, input map, scene config
      scenes/main.tscn      # Root scene
      scripts/              # All gameplay logic (each script has a class_name
                            # and uses preload() for cross-script references)
      shaders/planet.gdshader
      resources/            # Textures, models, fonts (with .import sidecars)
      tests/                # Headless GDScript test suite
        test_framework.gd   # Tiny RefCounted assertion harness
        run_tests.gd        # SceneTree entry — discovers test_*.gd
        test_*.gd

### Why this port shape

Earlier attempt (PR #1, branch `claude/enhance-orbit-simulator-9zgDD`) crashed
after ~1 minute. Lessons baked into this port:

1. **Cache meshes & materials** — the previous orbit renderer allocated a
   fresh `ImmediateMesh` and `StandardMaterial3D` every frame per satellite.
   `OrbitalPath` now builds a single `ArrayMesh` once and rewrites its vertex
   buffer in place only when the orbital elements actually change.
2. **Bound the simulation time factor** and rate-scale by frame delta. The
   previous controller incremented `time_factor` per frame while a key was
   held, eventually driving universal-variable Newton-Raphson into NaN.
3. **`is_state_valid()` guards on every propagate** with NaN-detection on
   inputs and outputs; satellites whose orbit goes pathological are flagged
   `orbit_alive = false` rather than feeding NaN vertices to the renderer.
4. **Use Godot's import pipeline for textures** instead of
   `Image.load_from_file()` — that pattern decoded ~200 MB of 4K JPEG into
   uncompressed VRAM at runtime.
5. **Simulation runs in `_physics_process`** at a fixed tick rate. The
   previous port ran in `_process` with a hardcoded `1/30` step.
6. **`class_name` + `preload()` everywhere** for cross-script references, and
   strongly-typed `@onready` vars / parameters — the patterns required by the
   commits on the previous branch (1b530d0, 07f8385).

# Legacy C++ build (`src/`)

Requirements: OpenGL, GLFW, GLEW, Assimp, SOIL, GLM, FreeType. `make` builds
`./test`. Kept around for reference; not the active target.

# Goals
* DONE: Make a basic orbital physics simlutation in 3D
* DONE: Refactor src/ with classes such that an arbitrary number of orbits may be added by user
* DONE: Figure out how to do transparent textures of assimp imported models
* Ship spites - sprites are harder than models... I'll just stick with cubes for simplicity for now
* DONE: allow selection of a single ship, selection will cause the orbit and cube marker to change color. All other orbits will be colored homogeneously
* Fix infinite loop hang in tgammma function during orbit calculation
* add handler for press and release keys
* once an oribt is selected, draw a line from the ship to every other ship and color that line one color if the line intersects Earth or another color if it does not
* DONE: for each of the other ("targeted") ships, display distance from selected ship and relative velocity beteen the two
* DONE: Consistently tick time. E.G. if a ship moves in a time period, don't propogate it
* create interface for calculated application of thrust. I.E. 0: display pitch, yaw, DV, DT 1: define unit vector of thrust 2: define delta V of thrust 3. define duration 4. execute
* Refactor orbit.cpp such that every orbital param is only derived once per R-V. Then an arbitrary number of calls will not repeat calculations
* Create object for the orbital system such that I can clone the current set of orbits and selectively display elements of that set propogated at the same time as "reality"
* create a planning mode where I can queue up a number of orbital maneuvers and see what their affect would be from the current orbital position
* refactor camera to snap to locations
* refactor camera to provide only pitch/yaw in a view
* add galactic plane mapped to sphere for background
* different color/style for projection data
* make time resolution a part of orbit.cpp so that way predicted orbits are not glaringly inaccurate

# Gameplay Ideas
* Model gamplay on [Ogre](http://www.sjgames.com/ogre/). E.G. Asymmetrical unit distribution pitting dozens of smaller, more nimble units vs one giant behemoth.
* Use kinetic weapons:
1. By radically adjusting your foes momentum, you will force them to expend fuel to make up the delta V and rectify their flight path
2. By using the weapon offensively, your own unit will have it's momentum changed an equal amount, so depending on the direction of the target and the position of your ship in orbit, firing can be potentially disasterous or advantageous.
