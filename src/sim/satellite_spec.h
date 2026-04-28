#ifndef GAME_SIM_SATELLITE_SPEC_H_
#define GAME_SIM_SATELLITE_SPEC_H_

#include <string>

#include "sim/orbit.h"

namespace sim {

// Launch-time attributes for a satellite. Designed to grow as the prototype
// adds mechanics (sensors, weapons, etc.) without breaking call sites.
struct SatelliteSpec {
    std::string name = "Sat";

    // Mass model.
    double dry_mass_kg = 250.0;
    double fuel_kg = 100.0;

    // Propulsion. delta_v_per_press is how much instantaneous velocity change
    // a single tick of thrust applies, in km/s. Total budget is implicitly
    // bounded by fuel_kg once we wire up mass flow.
    double max_thrust_kn = 0.5;
    double delta_v_per_press = 0.050;

    // Initial state (planet-centered inertial frame, km, km/s).
    vec3D initial_r{-6045.0, -3490.0, 2500.0};
    vec3D initial_v{-3.56, 6.618, 2.533};
};

}  // namespace sim

#endif  // GAME_SIM_SATELLITE_SPEC_H_
