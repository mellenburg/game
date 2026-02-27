# Orbit Simulator

A 3D orbital mechanics simulator featuring Keplerian physics, satellite management, and planning mode. Available in two implementations: the original C++/OpenGL prototype and a Godot 4 port.

## Quick Start (Godot 4)

The recommended way to run the project.

### Requirements

* [Godot 4.3+](https://godotengine.org/download/) (standard or .NET edition)

### Running

1. Download the Godot 4 editor for your platform
2. Open the `godot/` folder as a Godot project (Project > Import > select `godot/project.godot`)
3. Press F5 (or the Play button) to run

### Controls

| Key | Action |
|---|---|
| WASD | Move camera |
| Mouse | Look around |
| Arrow Up/Down | Thrust prograde/retrograde |
| Arrow Left/Right | Thrust lateral |
| Page Up/Down | Thrust normal (out-of-plane) |
| Q / E | Speed up / slow down time |
| Tab | Select next satellite |
| N | Add new satellite |
| R | Remove selected satellite |
| P | Toggle planning mode |
| T / G | Advance / retard planning time |
| Esc | Release/capture mouse |

### Project Layout

```
godot/
├── project.godot            # Project configuration
├── scenes/
│   └── main.tscn            # Main scene
├── scripts/
│   ├── earth_orbit.gd       # Keplerian orbital mechanics engine
│   ├── satellite.gd         # Spacecraft with orbit + visual marker
│   ├── orbital_path.gd      # 3D elliptical orbit rendering
│   ├── earth.gd             # Rotating Earth with day/night shader
│   ├── orbit_camera.gd      # Free-look camera
│   ├── earth_system.gd      # Main game controller
│   └── hud.gd               # Orbital info overlay + LOS detection
├── shaders/
│   └── planet.gdshader      # Earth shader (night lights + normal map)
└── resources/                # 4K Earth textures and models
```

### Orbital Mechanics

The simulation uses real Keplerian orbital mechanics:

* **Propagation**: Universal variable formulation with Lagrange coefficients and Newton-Raphson iteration
* **Gravitational parameter**: Earth's standard (398600.4415 km^3/s^2)
* **Maneuvers**: Delta-v applied in the local orbital frame (prograde, radial, normal)
* **Elements**: Full classical orbital elements computed from state vectors (a, e, i, RAAN, argp, nu)

### Planning Mode

Press P to enter planning mode. This clones all current orbits so you can experiment with maneuvers and see their projected effect without altering the real simulation. Use T/G to advance the planning time forward. Press P again to exit and discard the plan.

---

## Legacy Build (C++/OpenGL)

The original prototype in `src/`. Still buildable but no longer the primary target.

### Requirements

* OpenGL
* GLFW
* GLEW
* Assimp
* SOIL
* GLM
* FreeType

### Building

```bash
# Install system dependencies (Debian/Ubuntu)
sudo apt-get install build-essential libxmu-dev libxi-dev libgl-dev \
  libosmesa-dev libglu-dev xorg-dev git cmake zip wget \
  libsoil-dev libassimp-dev libfreetype6-dev

# Build vendored dependencies (GLEW, GLFW, GLM)
bash setup.sh

# Build the project
make
```

### Running

```bash
./test
```

Same keyboard controls as the Godot version.

---

# Goals

* DONE: Make a basic orbital physics simulation in 3D
* DONE: Refactor src/ with classes such that an arbitrary number of orbits may be added by user
* DONE: Figure out how to do transparent textures of assimp imported models
* DONE: Allow selection of a single ship, selection will cause the orbit and cube marker to change color
* DONE: For each of the other ("targeted") ships, display distance from selected ship and relative velocity between the two
* DONE: Consistently tick time
* DONE: Port to Godot 4 engine
* Fix infinite loop hang in tgamma function during orbit calculation
* Create interface for calculated application of thrust (pitch, yaw, DV, DT)
* Create a planning mode where you can queue up orbital maneuvers and preview their effect
* Refactor camera to snap to locations
* Add galactic plane mapped to sphere for background
* Add multiplayer support (Godot MultiplayerSpawner/Synchronizer)

# Gameplay Ideas

* Model gameplay on [Ogre](http://www.sjgames.com/ogre/). Asymmetrical unit distribution pitting dozens of smaller, more nimble units vs one giant behemoth.
* Use kinetic weapons:
  1. By radically adjusting your foe's momentum, you force them to expend fuel to make up the delta-V and rectify their flight path
  2. By using the weapon offensively, your own unit will have its momentum changed an equal amount, so depending on the direction of the target and the position of your ship in orbit, firing can be potentially disastrous or advantageous
