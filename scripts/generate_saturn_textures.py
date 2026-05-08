#!/usr/bin/env python3
"""Procedurally generate Saturn surface and ring textures.

Saturn imagery on the open web is captcha-walled or paywalled at the
moment of authoring; rather than ship a placeholder solid colour, this
script bakes a banded Saturn body map (with the famous hexagonal
north-polar vortex and a south-polar cyclone) plus a radial ring strip
keyed to the Cassini-division geometry. Outputs are checked into the
repo so the game build doesn't depend on this script at runtime.

The colour palette matches Cassini-era imagery (tan / cream / pale
yellow), and the band latitudes / widths track the standard Saturnian
zonal-wind pattern (EZ / NEB / NTrZ / NTB / NPR with the hexagon).
The ring strip encodes the D / C / B / Cassini Division / A / F sub-
structure as a 1×N alpha gradient that the shader samples by radial
position.

Run from the repo root:

    python3 scripts/generate_saturn_textures.py
"""

from __future__ import annotations

import math
import random
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter


REPO_ROOT = Path(__file__).resolve().parent.parent
TARGET_DIR = REPO_ROOT / "godot" / "resources" / "3D" / "saturn"
TARGET_DIR.mkdir(parents=True, exist_ok=True)


SATURN_WIDTH = 2048
SATURN_HEIGHT = 1024

RING_WIDTH = 2048
RING_HEIGHT = 32  # vertical strip; only the radial axis matters


def lerp_color(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


# Zonal band table. Each row is (latitude_north_degrees_center, half_width_deg, base_color).
# Ordered south-to-north so adjacent rows can be blended by latitude
# distance into a smooth meridional profile. Colours are eyeballed from
# Cassini ISS NA mosaics; the goal is "reads as Saturn at a glance" not
# a publishable scientific reconstruction.
BANDS = [
    (-90.0, 12.0, (188, 168, 132)),  # south polar cap (slightly darker tan)
    (-72.0, 8.0, (210, 188, 150)),
    (-58.0, 8.0, (224, 200, 158)),  # SPR
    (-42.0, 6.0, (200, 174, 130)),  # STB
    (-30.0, 6.0, (228, 204, 160)),  # STrZ
    (-18.0, 5.0, (198, 168, 124)),  # SEB darker
    (-8.0, 5.0, (236, 214, 168)),  # EZ bright cream
    (0.0, 4.0, (244, 224, 178)),
    (8.0, 5.0, (236, 214, 168)),
    (18.0, 5.0, (200, 170, 126)),  # NEB
    (30.0, 6.0, (230, 206, 162)),  # NTrZ
    (42.0, 6.0, (200, 174, 130)),  # NTB
    (58.0, 8.0, (220, 196, 154)),  # NPR
    (72.0, 8.0, (208, 184, 144)),
    (90.0, 12.0, (190, 168, 134)),  # north polar cap (darkened by hex shadowing)
]


def base_color_for_lat(lat_deg: float) -> tuple[int, int, int]:
    """Smoothly interpolate the band table at the given latitude."""

    # Nearest two bands by latitude; weight by inverse distance, falling
    # back to the closest band's colour if the supplied lat falls
    # outside the table's range.
    sorted_bands = sorted(BANDS, key=lambda row: abs(row[0] - lat_deg))
    a_lat, a_w, a_c = sorted_bands[0]
    b_lat, b_w, b_c = sorted_bands[1]
    span = abs(b_lat - a_lat)
    if span < 1e-6:
        return a_c
    t = abs(lat_deg - a_lat) / span
    t = max(0.0, min(1.0, t))
    return lerp_color(a_c, b_c, t)


def bake_saturn_body() -> Image.Image:
    rng = random.Random(20260508)
    img = Image.new("RGB", (SATURN_WIDTH, SATURN_HEIGHT), (210, 188, 148))
    pixels = img.load()

    # Per-row turbulence offset: sum of a few low-frequency sines along
    # the longitude axis so each band has streaky cloud structure rather
    # than a flat colour line. Phase / amplitude rolls per row so the
    # streaks aren't aligned vertically.
    for y in range(SATURN_HEIGHT):
        v = y / (SATURN_HEIGHT - 1)
        lat_deg = 90.0 - 180.0 * v
        base = base_color_for_lat(lat_deg)

        # Soft polar darkening: cos(lat) shaves a bit off the value as
        # the surface tips away from the camera near the poles, the way
        # the gas giant integrates over an oblique path.
        polar_dim = 0.92 + 0.08 * math.cos(math.radians(lat_deg))

        # Amplitude / frequency of the turbulence band changes with lat
        # so equatorial zones look smooth and mid-latitude belts read as
        # streaky.
        belt_bias = 0.08 + 0.18 * (1.0 - abs(math.cos(math.radians(lat_deg))))
        n_freqs = 6
        amps = [rng.uniform(2.0, 12.0) * belt_bias for _ in range(n_freqs)]
        freqs = [rng.uniform(2.0, 18.0) for _ in range(n_freqs)]
        phases = [rng.uniform(0.0, math.tau) for _ in range(n_freqs)]

        for x in range(SATURN_WIDTH):
            u = x / (SATURN_WIDTH - 1)
            lon = u * math.tau
            t = sum(
                a * math.sin(f * lon + p)
                for a, f, p in zip(amps, freqs, phases)
            )
            grain = rng.uniform(-3.0, 3.0)
            scale = 1.0 + (t + grain) / 255.0
            r = max(0, min(255, int(base[0] * polar_dim * scale)))
            g = max(0, min(255, int(base[1] * polar_dim * scale)))
            b = max(0, min(255, int(base[2] * polar_dim * scale)))
            pixels[x, y] = (r, g, b)

    # Soften the streaks: a tiny gaussian blur knocks out the per-pixel
    # noise without erasing the banded structure.
    img = img.filter(ImageFilter.GaussianBlur(radius=0.8))
    img = paint_north_hexagon(img)
    img = paint_south_vortex(img)
    return img


def lat_to_y(lat_deg: float) -> float:
    return (90.0 - lat_deg) / 180.0 * (SATURN_HEIGHT - 1)


def paint_north_hexagon(img: Image.Image) -> Image.Image:
    """Render the polar-projected hexagon as it would appear sitting
    near 78°N when wrapped to an equirectangular map.

    Approach: sample each pixel's lat/lon, project to a polar (rho, phi)
    chart centered on the north pole, then test against a hexagonal
    boundary. Two boundaries (an outer "edge" band and an inner "eye"
    region) tint the surface darker / more amber so the hexagon reads
    as a clear feature rather than a faint outline.
    """

    pixels = img.load()
    hex_center_lat = 78.0  # actual Cassini hexagon sits ~78°N
    inner_radius_deg = 4.0  # eye of the hex polar cyclone
    outer_radius_deg = 11.0  # outer hexagon edge distance from pole
    edge_thickness_deg = 1.6
    hex_rotation_deg = 7.0  # arbitrary; off-axis to taste
    edge_color = (96, 64, 32)  # dark amber edge
    eye_color = (52, 32, 14)  # darker eye
    inner_blend = 0.85
    edge_blend = 0.78

    # Polar projection: take latitude as radial distance from the pole
    # in degrees, longitude as angular coordinate. A regular hexagon is
    # the locus of points where rho * cos(theta - k * 60°) <= R for
    # k = 0..5; equivalently the max over those projections equals the
    # apothem of the bounding hexagon.
    cos60 = 0.5
    sin60 = math.sin(math.radians(60.0))

    def hex_apothem_factor(theta: float) -> float:
        # Distance from center along the angle theta to the hex edge,
        # measured as a multiple of the hex apothem. cos(theta_mod) over
        # the [0, 60°) wedge gives the apothem-relative distance to the
        # edge along that ray.
        t = (theta % math.radians(60.0)) - math.radians(30.0)
        return 1.0 / max(math.cos(t), 1e-3)

    rot = math.radians(hex_rotation_deg)
    for y in range(SATURN_HEIGHT):
        v = y / (SATURN_HEIGHT - 1)
        lat_deg = 90.0 - 180.0 * v
        rho_deg = 90.0 - lat_deg  # 0 at pole, increasing southward
        # Outside the hexagon's region of influence — skip whole rows.
        if rho_deg > outer_radius_deg + edge_thickness_deg + 1.0:
            continue
        for x in range(SATURN_WIDTH):
            u = x / (SATURN_WIDTH - 1)
            lon_rad = u * math.tau
            theta = lon_rad - rot
            edge_distance_factor = hex_apothem_factor(theta)
            # The hex's outer apothem corresponds to outer_radius_deg
            # measured along a face-normal (theta_mod = 0). At a vertex
            # the apothem multiplier stretches to 1/cos(30°), so the
            # vertex distance is outer_radius_deg / cos(30°) ≈ 11.0°.
            inside_outer = rho_deg <= outer_radius_deg * edge_distance_factor
            inside_inner = rho_deg <= (outer_radius_deg - edge_thickness_deg) * edge_distance_factor
            if not inside_outer:
                continue
            cur = pixels[x, y]
            if rho_deg <= inner_radius_deg:
                # Eye of the hex.
                pixels[x, y] = lerp_color(cur, eye_color, inner_blend)
            elif inside_outer and not inside_inner:
                # Edge band of the hex.
                pixels[x, y] = lerp_color(cur, edge_color, edge_blend)
            else:
                # Inside the hex but not on the edge — darken
                # noticeably so the hexagon's footprint reads as one
                # contiguous shape against the lighter polar collar.
                pixels[x, y] = lerp_color(cur, edge_color, 0.45)

    return img


def paint_south_vortex(img: Image.Image) -> Image.Image:
    """Cassini observed a roughly circular polar cyclone at the south
    pole — much simpler shape than the hexagon. Render as a small dark
    disk so the south pole isn't conspicuously featureless next to the
    north."""

    pixels = img.load()
    south_center_lat = -88.5
    radius_deg = 3.5
    eye_color = (108, 78, 44)
    eye_blend = 0.5

    for y in range(SATURN_HEIGHT):
        v = y / (SATURN_HEIGHT - 1)
        lat_deg = 90.0 - 180.0 * v
        if lat_deg > -85.0:
            continue
        rho_deg = abs(lat_deg - south_center_lat)
        if rho_deg > radius_deg + 1.0:
            continue
        # The polar projection here is degenerate (longitude lines
        # converge), so paint every column on this row that's inside
        # the radius — at the equirectangular wrap that's all of them.
        for x in range(SATURN_WIDTH):
            cur = pixels[x, y]
            blend = eye_blend * max(0.0, 1.0 - rho_deg / radius_deg)
            pixels[x, y] = lerp_color(cur, eye_color, blend)

    return img


# Ring substructure. Each row is (radius_fraction_low, radius_fraction_high,
# rgba_color). Radii are normalised to [0, 1] across the texture's U axis,
# where 0 maps to the D-ring inner edge (66 900 km from Saturn's centre)
# and 1 maps to the F-ring outer edge (140 220 km). Sub-band positions
# are computed from the Cassini-derived radii so the texture lines up
# with the ring mesh that matches the same radii on CelestialBody.
#   D (inner haze) | C (translucent) | B (densest) | Cassini Division
#   (gap) | A (bright) | Encke gap | A outer | F (thin)
def _frac(r_km: float) -> float:
    return (r_km - 66900.0) / (140220.0 - 66900.0)


RING_BANDS = [
    (_frac(66900.0), _frac(74510.0), (180, 152, 110, 60)),  # D ring (faint)
    (_frac(74510.0), _frac(92000.0), (188, 166, 122, 130)),  # C ring
    (_frac(92000.0), _frac(105000.0), (224, 200, 158, 235)),  # B inner
    (_frac(105000.0), _frac(117580.0), (236, 212, 170, 255)),  # B outer (densest)
    (_frac(117580.0), _frac(122170.0), (160, 138, 100, 50)),  # Cassini Division
    (_frac(122170.0), _frac(133589.0), (220, 196, 154, 220)),  # A ring inner / mid
    (_frac(133589.0), _frac(133914.0), (140, 122, 90, 60)),  # Encke Gap
    (_frac(133914.0), _frac(136775.0), (218, 196, 156, 220)),  # A ring outer
    (_frac(136775.0), _frac(140100.0), (170, 148, 110, 30)),  # Roche Division (mostly clear)
    (_frac(140100.0), _frac(140220.0), (210, 184, 140, 200)),  # F ring (thin)
]


def bake_ring_strip() -> Image.Image:
    rng = random.Random(20260601)
    img = Image.new("RGBA", (RING_WIDTH, RING_HEIGHT), (0, 0, 0, 0))
    pixels = img.load()

    def sample_band(u: float) -> tuple[int, int, int, int]:
        for low, high, color in RING_BANDS:
            if low <= u <= high:
                # Edge-fade: soft falloff at each band boundary so the
                # transitions read as gradual rather than as paint-bucket
                # rectangles. Inner 80% of the band stays at the band's
                # full alpha; outer 10% on each side fades toward an
                # average of neighbouring bands.
                width = max(high - low, 1e-6)
                t = (u - low) / width
                edge = min(t, 1.0 - t)
                edge_factor = min(1.0, edge / 0.1)
                r, g, b, a = color
                a = int(a * edge_factor + a * (1.0 - edge_factor) * 0.85)
                return (r, g, b, a)
        return (0, 0, 0, 0)

    # Per-pixel ringlet noise: vary alpha by a tiny amount along the
    # radial axis so the dense rings look subdivided into ringlets when
    # rendered at high resolution. Real Saturn rings have hundreds of
    # ringlets; simulating two octaves of noise gives the right "speckled
    # but coherent" feel on close inspection.
    for x in range(RING_WIDTH):
        u = x / (RING_WIDTH - 1)
        r, g, b, a = sample_band(u)
        if a > 0:
            n = sum(
                math.sin(u * f + p) * amp
                for f, p, amp in (
                    (140.0, rng.uniform(0.0, math.tau), 0.06),
                    (550.0, rng.uniform(0.0, math.tau), 0.04),
                    (2200.0, rng.uniform(0.0, math.tau), 0.025),
                )
            )
            a = max(0, min(255, int(a * (1.0 + n))))
            tint = 1.0 + n * 0.5
            r = max(0, min(255, int(r * tint)))
            g = max(0, min(255, int(g * tint)))
            b = max(0, min(255, int(b * tint)))
        for y in range(RING_HEIGHT):
            pixels[x, y] = (r, g, b, a)

    return img


def main() -> None:
    saturn = bake_saturn_body()
    saturn_path = TARGET_DIR / "2048_saturn.jpg"
    saturn.save(saturn_path, "JPEG", quality=88, optimize=True)
    print(f"Wrote {saturn_path} ({saturn_path.stat().st_size / 1024:.1f} KiB)")

    rings = bake_ring_strip()
    rings_path = TARGET_DIR / "2048_rings.png"
    rings.save(rings_path, "PNG", optimize=True)
    print(f"Wrote {rings_path} ({rings_path.stat().st_size / 1024:.1f} KiB)")


if __name__ == "__main__":
    main()
