# Agentic Development Evaluation

## Why Claude Code Adds Tests but Antigravity Does Not
The repository currently contains agentic guidance in a file named `CLAUDE.md`. Claude Code is hardcoded to automatically read and follow instructions found in `CLAUDE.md` files. This file contains a specific and detailed "Test discipline" section that dictates how to write unit tests for the project (e.g., extending `RefCounted` for pure-math classes, adding headless unit tests in `godot/tests/test_*.gd`).

However, other agentic platforms like Antigravity generally look for standard generic agent-instruction files such as `AGENTS.md`. Since there is no `AGENTS.md` (and Antigravity does not automatically ingest `CLAUDE.md` by default), Antigravity operates without the specific project guidance that mandates updating and adding new unit tests for any codebase changes.

To fix this, you should either rename `CLAUDE.md` to `AGENTS.md` or create a symlink / duplicate of the file named `AGENTS.md` so that all agent frameworks will ingest and adhere to these project-specific rules.

## Lingo Inconsistencies
The codebase has ambiguous and inconsistent terms that can confuse agents when describing features:

1. **Ship vs. Satellite vs. Unit vs. Enemy**
   - The game's entities are variously referred to as `Ship`, `Satellite`, and `Unit` (and sometimes `Enemy` for hostile ones).
   - `README.md` mentions: "Satellites are the units", "Ship N seconds", "enemy satellites", etc.
   - The code has scripts like `satellite.gd`, `unit_chassis.gd`, `unit_config.gd`, `spawn_director.gd` (spawn enemies), and `wave_unit_class.gd`. Unifying these terms (or strictly defining the ontology) will help agents navigate the codebase better.

2. **Earth vs. Celestial Body / Planet**
   - `README.md` mentions "EarthOrbit" and "Earth textures", and there are files `earth.gd`, `earth_orbit.gd`, `earth_system.gd`.
   - However, the game allows for multi-map support ("Maps" section in `README.md`) mentioning that "gravity is not constant between maps" and "central body is not fixed to Earth".
   - Files like `celestial_body.gd` correctly generalize this, but core controllers and propagators still use "Earth" (e.g., `earth_orbit.gd` instead of `orbit_propagator.gd` or `body_orbit.gd`).

3. **Gravity**
   - Mentions in README / code of "Anti-gravity" versus "Gravity well".

Standardizing this vocabulary will help an agent more quickly figure out where to make changes when given a feature request.
