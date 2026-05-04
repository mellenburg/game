# Asteroid & meteor fun facts

Reference notes for keeping the meteorite system grounded in plausible
physics. The numbers here drove the calibration of `MeteorPhysics`
(`godot/scripts/meteor_physics.gd`); future tuning passes should
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
| Sizable meteorite makes it down           | ~100 kg (basketball)|
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
below come from bulk-density measurements of meteorite analogs
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

`MeteorPhysics.sample_density()` rolls the class first (weighted),
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


## Mass bands the game spawns

`MeteorPhysics` and `SpawnDirector` agree on three bands. Roughly:

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
- [HowStuffWorks: How big does a meteor have to be to make it to the ground?](https://science.howstuffworks.com/question486.htm)
- [Planetary Science Institute size threshold (via space.com asteroid apocalypse article)](https://www.space.com/asteroid-apocalypse-how-big-can-humanity-survive)
- [Tunguska event — Wikipedia](https://en.wikipedia.org/wiki/Tunguska_event)
- [NASA — Probabilistic Assessment of Tunguska-scale Asteroid Impacts](https://ntrs.nasa.gov/api/citations/20190002844/downloads/20190002844.pdf)
- [Density of asteroids (B. Carry, 2012)](https://arxiv.org/pdf/1203.4336)
- [Density and porosity of stone meteorites (Britt & Consolmagno)](https://www.sciencedirect.com/science/article/abs/pii/S0019103599962103)
- [C-type asteroid — Wikipedia](https://en.wikipedia.org/wiki/C-type_asteroid)
- [Chicxulub crater — Britannica](https://www.britannica.com/place/Chicxulub)
- [Deep Impact and the Mass Extinction of Species 65 Million Years Ago — NASA Science](https://science.nasa.gov/earth/deep-impact-and-the-mass-extinction-of-species-65-million-years-ago/)
