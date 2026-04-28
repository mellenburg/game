#include "sim/satellite.h"
#include "sim/satellite_spec.h"
#include "tests/test_util.h"

#include <glm/glm.hpp>

TEST(satellite, default_spec_is_low_earth_orbit) {
    sim::Satellite sat;
    glm::vec3 r = sat.GetR();
    // Default spec is below GEO; sanity-check magnitude.
    EXPECT_TRUE(glm::length(r) > 6000.0f);
    EXPECT_TRUE(glm::length(r) < 50000.0f);
}

TEST(satellite, advance_with_no_maneuver_changes_position) {
    sim::Satellite sat;
    glm::vec3 r0 = sat.GetR();
    sat.AdvanceTime(60.0);
    EXPECT_TRUE(glm::distance(sat.GetR(), r0) > 0.0f);
}

TEST(satellite, set_then_clear_maneuver_resets_intent) {
    sim::Satellite sat;
    sat.SetManeuver(glm::vec3(1.0f, 0.0f, 0.0f));
    EXPECT_TRUE(glm::length(sat.GetCurrentManeuver()) > 0.0f);
    sat.ClearManeuver();
    EXPECT_NEAR(glm::length(sat.GetCurrentManeuver()), 0.0, 1e-9);
}

TEST(satellite, maneuver_diverges_from_no_maneuver) {
    sim::Satellite a;
    sim::Satellite b;
    a.SetManeuver(glm::vec3(1.0f, 0.0f, 0.0f));
    a.AdvanceTime(10.0);
    b.AdvanceTime(10.0);
    EXPECT_TRUE(glm::distance(a.GetV(), b.GetV()) > 1e-3f);
}

TEST(satellite, clone_state_copies_orbit_state) {
    sim::Satellite a;
    a.AdvanceTime(120.0);

    sim::Satellite b;
    b.CloneStateFrom(a);
    EXPECT_NEAR(b.GetR().x, a.GetR().x, 1e-3);
    EXPECT_NEAR(b.GetR().y, a.GetR().y, 1e-3);
    EXPECT_NEAR(b.GetR().z, a.GetR().z, 1e-3);
    EXPECT_NEAR(b.GetV().x, a.GetV().x, 1e-6);
}

TEST(satellite, custom_spec_uses_provided_initial_state) {
    sim::SatelliteSpec spec;
    spec.initial_r = vec3D{42164.0, 0.0, 0.0};   // GEO altitude
    spec.initial_v = vec3D{0.0, 3.0746611, 0.0}; // ~ circular GEO
    sim::Satellite sat(spec);
    EXPECT_NEAR(sat.GetR().x, 42164.0, 1e-6);
    EXPECT_NEAR(sat.GetV().y, 3.0746611, 1e-6);
}
