#include <cmath>

#include "sim/orbit.h"
#include "tests/test_util.h"

namespace {

constexpr double kMu = 398600.4415;        // Earth's GM, km^3/s^2
constexpr double kCircularRadius = 6671.0; // ~300 km altitude

}  // namespace

TEST(orbit, circular_orbit_has_zero_eccentricity) {
    vec3D r0{kCircularRadius, 0.0, 0.0};
    vec3D v0{0.0, std::sqrt(kMu / kCircularRadius), 0.0};
    EarthOrbit orbit(r0, v0);
    EXPECT_NEAR(orbit.ecc, 0.0, 1e-6);
    EXPECT_NEAR(orbit.norm_r, kCircularRadius, 1e-6);
    EXPECT_NEAR(orbit.a, kCircularRadius, 1e-6);
}

TEST(orbit, propagate_full_period_returns_to_start) {
    vec3D r0{kCircularRadius, 0.0, 0.0};
    vec3D v0{0.0, std::sqrt(kMu / kCircularRadius), 0.0};
    EarthOrbit orbit(r0, v0);
    orbit.propagate(orbit.period);
    EXPECT_NEAR(orbit.r.i, r0.i, 1e-2);
    EXPECT_NEAR(orbit.r.j, r0.j, 1e-2);
    EXPECT_NEAR(orbit.r.k, r0.k, 1e-2);
}

TEST(orbit, circular_orbit_keeps_constant_radius) {
    vec3D r0{kCircularRadius, 0.0, 0.0};
    vec3D v0{0.0, std::sqrt(kMu / kCircularRadius), 0.0};
    EarthOrbit orbit(r0, v0);
    const double step = orbit.period / 50.0;
    for (int i = 0; i < 50; ++i) {
        orbit.propagate(step);
        EXPECT_NEAR(orbit.norm_r, kCircularRadius, 1e-3);
    }
}

TEST(orbit, propagate_zero_is_noop) {
    vec3D r0{kCircularRadius, 0.0, 0.0};
    vec3D v0{0.0, std::sqrt(kMu / kCircularRadius), 0.0};
    EarthOrbit orbit(r0, v0);
    orbit.propagate(0.0);
    EXPECT_NEAR(orbit.r.i, r0.i, 1e-9);
    EXPECT_NEAR(orbit.r.j, r0.j, 1e-9);
    EXPECT_NEAR(orbit.r.k, r0.k, 1e-9);
}

TEST(orbit, clone_copies_full_state) {
    vec3D r_a{kCircularRadius, 0.0, 0.0};
    vec3D v_a{0.0, std::sqrt(kMu / kCircularRadius), 0.0};
    EarthOrbit src(r_a, v_a);
    src.propagate(123.4);  // pick a state to copy

    vec3D r_b{-6045.0, -3490.0, 2500.0};
    vec3D v_b{-3.56, 6.618, 2.533};
    EarthOrbit dst(r_b, v_b);
    dst.clone(src);

    EXPECT_NEAR(dst.r.i, src.r.i, 1e-9);
    EXPECT_NEAR(dst.r.j, src.r.j, 1e-9);
    EXPECT_NEAR(dst.r.k, src.r.k, 1e-9);
    EXPECT_NEAR(dst.v.i, src.v.i, 1e-9);
    EXPECT_NEAR(dst.v.j, src.v.j, 1e-9);
    EXPECT_NEAR(dst.v.k, src.v.k, 1e-9);
    EXPECT_NEAR(dst.ecc, src.ecc, 1e-9);
    EXPECT_NEAR(dst.a, src.a, 1e-9);
}

TEST(orbit, prograde_burn_raises_apoapsis) {
    vec3D r0{kCircularRadius, 0.0, 0.0};
    vec3D v0{0.0, std::sqrt(kMu / kCircularRadius), 0.0};
    EarthOrbit orbit(r0, v0);
    const double r_a_before = orbit.r_a;
    // Burn prograde (+i in velocity-aligned frame) for 1 second.
    orbit.relative_maneuver(glm::vec3(0.5f, 0.0f, 0.0f), 1.0);
    EXPECT_TRUE(orbit.r_a > r_a_before);
}
