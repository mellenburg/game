# Asteroid & asteroid fun facts

Reference notes for keeping the asteroid system grounded in plausible
physics. The numbers here drove the calibration of `AsteroidPhysics`
(`godot/scripts/asteroid_physics.gd`); future tuning passes should
update both this doc and the constants together so the gameplay model
and the science don't drift apart.

The game is **not** a simulator — the formulas below are deliberately
simple and stylised. They're tuned to be inside an order of magnitude
of the real physics across the size range we actually spawn, while
staying readable and tunable on a single dial.


## Atmospheric entry threshold

A meteoroid's chance of reaching the ground intact depends on its
mass, composition, and entry speed. Useful thresholds:

| What                                      | Approx. mass        |
| ----------------------------------------- | ------------------- |
| Pebble-class fragments survive            | ~1 kg (rare)        |
| Sizable asteroid makes it down           | ~100 kg (basketball)|
| Body retains cosmic velocity to surface   | ~10,000 kg (10 t)   |
| Single-rock impact, small crater          | ~10⁶ kg (1 Gg)      |

Below ~5 m diameter (~10 t at stony density) bodies almost universally
fragment and ablate in the atmosphere. The Planetary Science
Institute uses 5 m / ~10 t as the threshold for "anything reaches the
ground at all". We use **10 t = 10,000 kg = 1 × 10⁴ kg** as the game's
`BURN_UP_THRESHOLD_KG` — bodies below it are silently removed at
ground crossing without doing damage or painting an impact marker.

(Real atmosphere is path-length-dependent; a shallow entry burns up
more material than a steep one. We don't model this — the threshold
is mass-only.)


## Composition & density

Asteroids fall into a few rough taxonomic bins. The bulk densities
below come from bulk-density measurements of asteroid analogs
reported in the meteoritics literature:

| Class       | Density (g/cm³) | Notes                                 |
| ----------- | --------------- | ------------------------------------- |
| C-type      | 1.6 – 2.5       | Carbonaceous chondrite, water-rich    |
| S-type      | 3.0 – 4.0       | Stony / ordinary chondrite (most common) |
| Stony-iron  | 4.5 – 6.5       | Mixed nickel-iron / silicate          |
| M-type      | 7.0 – 8.0       | Iron / nickel, very dense and rare    |

Population weighting (rough Near-Earth Asteroid distribution):

* ~70% S-type stony
* ~15% C-type carbonaceous
* ~10% stony-iron
* ~5% iron

`AsteroidPhysics.sample_density()` rolls the class first (weighted),
then samples a uniform density inside the class band.


## HP formula

```
HP = HP_PER_KG_PER_DENSITY × mass_kg × density_g_cm3
```

with `HP_PER_KG_PER_DENSITY = 0.003`. Linear in both factors so doubling
mass or doubling density doubles HP. An iron rock soaks ~2.5× the
shots a carbonaceous rock of the same mass would.

Calibration points (stony, ρ = 3.4):

| Body                       | Mass            | HP        |
| -------------------------- | --------------- | --------- |
| Threshold (10 Mg)          | 1 × 10⁴ kg      | ~100 HP   |
| Small impactor (1 Gg)      | 1 × 10⁶ kg      | ~10,000   |
| Tunguska-class (1 Tg)      | 1 × 10⁹ kg      | ~10⁷      |
| Didymos-class (500 Tg)     | 5 × 10¹¹ kg     | ~5 × 10⁹  |

Anything Tg-class and up is effectively unkillable in flight — by
design. Players thin numbers and pick off the small end; the big
ones are existential threats best handled with redirection (future
weapon class) or by accepting the loss.


## Damage radii

Three concentric tiers, all scaling as the cube root of mass (constant-
velocity kinetic energy ∝ mass; blast volume ∝ energy):

```
heavy_km    = 0.020 × mass_kg^(1/3)   # near-instant lethality
moderate_km = 0.060 × mass_kg^(1/3)   # severe blast / structural collapse
light_km    = 0.150 × mass_kg^(1/3)   # overpressure, broken windows
```

Calibration check against the historical & near-historical record:

| Body                       | Heavy   | Moderate | Light    | Real-world reference |
| -------------------------- | ------- | -------- | -------- | -------------------- |
| Tunguska (1 Tg)            | 20 km   | 60 km    | 150 km   | ~25 km flatten radius, ~100 km felt |
| Didymos-class (500 Tg)     | 159 km  | 476 km   | 1191 km  | regional annihilation |
| Pg (1 × 10¹² kg)           | 200 km  | 600 km   | 1500 km  | country-scale destruction |
| Eg (1 × 10¹⁵ kg, Chicxulub-ish) | 2000 km | 6000 km | 15000 km | mass extinction |

Cube-root scaling under-predicts for Chicxulub-class events (real
research puts the K-Pg blast radius at 900 – 1800 km, our "moderate"
band gives 6000 km — the formula over-extrapolates) but matches
Tunguska to within a factor of two and stays well-behaved across the
range we routinely spawn.


## Mass-HP coupling under fire

An asteroid's HP and physical mass are linked: damage represents
fragmentation and spalling, so as HP drops the surviving mass drops
in lockstep. Implemented in `Satellite.take_damage` via
`AsteroidPhysics.mass_for_hp`:

```
mass_remaining_kg = HP_remaining / (HP_PER_KG_PER_DENSITY * density)
                  = (HP_remaining / max_HP) * spawn_mass_kg
```

Three knock-on effects, all derived (no extra plumbing):

* **Smaller impacts when chipped down**. Because the impact-map
  damage radii read off `sat.mass` at the moment of impact, a body
  that arrives half-eroded leaves a half-mass crater. The cube-root
  scaling means radii shrink by ~21% for a 50% mass loss — visible
  but not dramatic, which feels right.
* **Burn-up if eroded enough**. Once the mass crosses below
  `BURN_UP_THRESHOLD_KG` (10 t) the body counts as fully ablating.
  `EarthSystem._record_asteroid_impact` skips the impact entirely
  and the body's surface crossing produces no damage, no marker,
  and no impact-explosion. The "kill" is the atmosphere finishing
  what we started.
* **Railgun deflection scales up**. The railgun computes target
  Δv as `SLUG_MOMENTUM / target.mass`. As the rock loses mass each
  slug pushes it harder — the late shots in a sustained engagement
  do more orbit-bending than the first ones. This is the right
  feedback loop: a player who thins a target deserves a payoff on
  the maneuver side, not just the HP side.

To prevent overkill against bodies the atmosphere has already won,
both laser and railgun envelopes skip targets where
`Satellite.is_inert_asteroid()` is true (asteroid or decaying body
with mass at or below the burn-up threshold). Weapons disengage
automatically and re-allocate fire to remaining threats.


## Water-impact (ocean) design notes

Not implemented yet, but the impact tracker already records
`is_ocean: bool` per impact entry so the path is open. Design
intent for a future pass:

### Energy partitioning

An ocean impactor of mass `m` couples its kinetic energy into:

* **Crater / vapour plume** — significant only for very large bodies
  (Pg+) that punch through to the seafloor.
* **Tsunami waves** — the dominant land-damage mode for sub-Pg
  ocean impacts. Wave amplitude near the impact scales roughly
  as `m^(1/4)` for a deep-water airburst-style splash, with
  range-falloff `1/r` at the coastline.
* **Atmospheric shockwave** — same scale as a land impact but
  attenuated faster over open water.

For game purposes a small set of rules is enough — full
hydrodynamic modelling is deep into "not fun" territory.

### Proposed game model

When `entry["is_ocean"]` is true, replace the three concentric
circles centred on the impact point with a coastline-projected
damage map:

* **Light damage**: every coastline within `R_light_ocean` of the
  impact. Boost factor ~3-5× over the land-impact light radius
  (tsunami waves carry energy further than blast).
* **Moderate damage**: coastlines within `R_moderate_ocean`.
  Tsunami strong enough to flood and destroy port infrastructure.
* **Heavy damage**: coastlines within a smaller radius — the
  "wave actually destroys the city" zone, which only triggers
  for Tg-class and up.

Implementation seam:

* `AsteroidPhysics.ocean_damage_radii_km(mass_kg)` would mirror
  `damage_radii_km` but with ocean coefficients (likely
  `light_ocean ≈ 4 × light_land`, `moderate_ocean ≈ 3 × moderate_land`,
  `heavy_ocean ≈ 1.5 × heavy_land`).
* `ImpactMap` would render the ocean map differently: instead of
  filled circles around the impact, paint coastline pixels within
  each radius as a soft glow at the appropriate damage colour. A
  cheap proxy is to keep the concentric circles but mask them with
  the basemap's land/water alpha so only land within the radius
  lights up.
* Composition matters here too: a low-density C-type "snowball"
  impacting water tends to disrupt at the surface (less coupled
  energy → smaller tsunami) while an M-type iron rock punches
  deep before depositing energy (larger tsunami). A
  `water_coupling(composition)` multiplier on the radii captures
  this without overhauling the model.

### Per-band coastal effect ladder

Translating the design intent the team agreed on into code:

| Impact mass     | Land outcome                       | Ocean outcome                                        |
| --------------- | ---------------------------------- | ---------------------------------------------------- |
| Just above 10 t | Small yellow speck, building-scale | Local splash, no coastal damage (fully absorbed)     |
| Tunguska (1 Tg) | 25 km regional flatten             | Light damage to coastlines along the same ocean     |
| Didymos (500 Tg)| Heavy ~150 km, moderate ~500 km    | Moderate damage to coasts, heavy on nearest coast    |
| Pg-class        | Country annihilation               | Heavy on every coast of the impacted ocean           |
| Eg-class        | End-of-life globally               | End-of-life globally (atmospheric / climate effects dominate) |

Until this is implemented, ocean impacts use the same radii as land
impacts and just paint over water — visually correct (a Tunguska in
the ocean has no nearby coastline to hit) but it under-represents
the tsunami threat. Worth revisiting once the coastal-cities /
surface-installations content gets fleshed out.


## What the player actually sees in a wave

The mass spread inside a wave is what determines whether the
operator sees variety or "every rock looks the same". Two settings
control it: the mass bands themselves, and the *sampling
distribution* inside each band.

The spawner now uses **log-uniform sampling** within each band, so
each order of magnitude inside a band gets equal weight. (The
legacy `randf_range` distribution stuffed ~90% of a 3-decade band
into its top decade — every "small" rock looked like a 5-10 Gg
boulder, every "medium" rock like a 5-10 Tg city-killer.)

For the current band edges, log-uniform sampling means roughly:

| Band   | Mass range          | Where samples land (≈ third of band each)         |
| ------ | ------------------- | -------------------------------------------------- |
| small  | 10 Mg .. 10 Gg      | 1/3 in 10–100 Mg, 1/3 in 100 Mg–1 Gg, 1/3 in 1–10 Gg |
| medium | 10 Gg .. 10 Tg      | 1/3 in 10–100 Gg, 1/3 in 100 Gg–1 Tg, 1/3 in 1–10 Tg |
| large  | 10 Tg .. 500 Tg     | 1/3 each across roughly half-decade slices         |

In a 20-body alpha-class wave (default mix: 80% small / 15% medium
/ 5% large) you'd typically get something like:

* **5–6 bodies in the 10–100 Mg "boulder" range** — small markers,
  damage radius ~3–7 km, visible single yellow dot on the impact
  map. Player can chip several to inert with one or two laser shots.
* **5–6 bodies in the 100 Mg–1 Gg "village-killer" range** — light
  damage radius ~7–15 km. Lasers handle them with focused fire.
* **3–4 bodies in the 1–10 Gg range** — heavy enough that several
  shots are needed; the impact map paints the orange ring.
* **2–3 medium-band bodies in the 10 Gg–1 Tg range** — Tunguska
  precursors. Players will see all three damage rings on impact.
* **1 large-band Tunguska / Didymos-class body** roughly every
  20-body wave — the boss-class threat the loadout has to plan for.

The 3D marker uses a log-decade scale (`AsteroidPhysics.mass_log_norm`)
so the markers across that span actually look different on screen:

| Mass        | Marker scale (× base 0.15 unit cube) |
| ----------- | ------------------------------------- |
| 10 Mg (1e4) | 0.5x  — minimum (just visible)        |
| 1 Gg (1e6)  | ~1.4x                                 |
| 1 Tg (1e9)  | ~3.9x                                 |
| 100 Tg (1e11)| ~5.4x                                |
| 1 Pg (1e12) | 6.0x  — maximum                       |


## Mass bands the game spawns

`AsteroidPhysics` and `SpawnDirector` agree on three bands. Roughly:

| Band   | Mass range             | Stony HP range   | Heavy radius    |
| ------ | ---------------------- | ---------------- | --------------- |
| small  | 10 Mg .. 10 Gg         | ~100 .. 100,000  | 0.4 .. 4 km     |
| medium | 10 Gg .. 10 Tg         | ~10⁵ .. 10⁸      | 4 .. 40 km      |
| large  | 10 Tg .. 500 Tg        | ~10⁸ .. 5 × 10⁹  | 40 .. 160 km    |

The wave generator weights small heaviest, large lightest, so most
bodies in a wave are killable threats and the rare large body is the
"oh no" moment. Bands and weights are tunable per `WaveUnitClass`
(the alpha / beta / gamma archetypes).


## Sources

- [Meteoroid — Wikipedia](https://en.wikipedia.org/wiki/Meteoroid)
- [HowStuffWorks: How big does an asteroid have to be to make it to the ground?](https://science.howstuffworks.com/question486.htm)
- [Planetary Science Institute size threshold (via space.com asteroid apocalypse article)](https://www.space.com/asteroid-apocalypse-how-big-can-humanity-survive)
- [Tunguska event — Wikipedia](https://en.wikipedia.org/wiki/Tunguska_event)
- [NASA — Probabilistic Assessment of Tunguska-scale Asteroid Impacts](https://ntrs.nasa.gov/api/citations/20190002844/downloads/20190002844.pdf)
- [Density of asteroids (B. Carry, 2012)](https://arxiv.org/pdf/1203.4336)
- [Density and porosity of stone asteroids (Britt & Consolmagno)](https://www.sciencedirect.com/science/article/abs/pii/S0019103599962103)
- [C-type asteroid — Wikipedia](https://en.wikipedia.org/wiki/C-type_asteroid)
- [Chicxulub crater — Britannica](https://www.britannica.com/place/Chicxulub)
- [Deep Impact and the Mass Extinction of Species 65 Million Years Ago — NASA Science](https://science.nasa.gov/earth/deep-impact-and-the-mass-extinction-of-species-65-million-years-ago/)
