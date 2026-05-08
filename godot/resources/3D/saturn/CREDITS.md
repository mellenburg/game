# Saturn surface and ring textures

The two `.jpg` / `.png` assets in this directory (`2048_saturn.jpg` and
`2048_rings.png`) are baked from the procedural generator at
`scripts/generate_saturn_textures.py` in the repository root. The
generator produces a banded equirectangular Saturn map keyed to the
zonal-wind latitudes documented in NASA Cassini ISS mosaics, with the
Cassini-era hexagonal polar vortex (~78°N) and the small circular
south-polar cyclone painted on top of the band base.

The ring strip encodes the canonical Saturnian sub-band geometry —
D / C / B / Cassini Division / A / Encke Gap / Roche Division / F —
with radii pulled from the `CelestialBody.make_saturn()` constants
(D-ring inner edge at 66 900 km, F-ring outer edge at 140 220 km
from Saturn's centre). The shader at `shaders/planet_rings.gdshader`
samples this strip's U axis radially and computes Saturn's umbra on
the disc per fragment.

## Why a procedural bake?

Cassini-era equirectangular mosaics from JPL / NASA's Photojournal
exist but the canonical hosting endpoints (`solarsystemscope.com`,
`bjj.mmedia.is/data/saturn`) gate downloads behind captchas that the
authoring environment couldn't satisfy. The procedural bake is good
enough to read as Saturn at the camera distances the renderer uses,
without depending on a network round-trip at build time. Swapping
the JPG for a real Cassini mosaic later is a drop-in replacement —
the file path and aspect ratio (2:1, equirectangular, north-up) are
the contract `MassCenter` and `PlanetRings` consume.

## How to regenerate

From the repository root:

    pip install Pillow
    python3 scripts/generate_saturn_textures.py

Both files land in this directory. The accompanying `.import`
sidecars are committed; running `make import` after a regenerate
will refresh them in-place.
