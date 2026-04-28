#ifndef GAME_SIM_SATELLITE_H_
#define GAME_SIM_SATELLITE_H_

#define GLM_FORCE_RADIANS
#include <glm/glm.hpp>

#include "sim/orbit.h"
#include "sim/satellite_spec.h"

namespace sim {

// Pure-simulation satellite. Holds orbital state and the player-issued
// maneuver intent for the current tick. No rendering concerns live here.
class Satellite {
  public:
    Satellite();
    explicit Satellite(const SatelliteSpec& spec);

    // Advance orbit by `dt_seconds`, applying any pending maneuver.
    void AdvanceTime(double dt_seconds);

    // Maneuver intent for the next AdvanceTime call. Components are unit
    // directions in the velocity-aligned frame; the magnitude is scaled by
    // spec.delta_v_per_press at apply time.
    void SetManeuver(glm::vec3 raw_direction);
    void ClearManeuver();

    const EarthOrbit& orbit() const { return orbit_; }
    EarthOrbit& mutable_orbit() { return orbit_; }
    const SatelliteSpec& spec() const { return spec_; }
    glm::vec3 GetR() const;
    glm::vec3 GetV() const;
    glm::vec3 GetCurrentManeuver() const;

    // Copy orbital + maneuver state from another satellite (spec untouched).
    // Used by planning-mode shadow worlds.
    void CloneStateFrom(const Satellite& other);

  private:
    SatelliteSpec spec_;
    EarthOrbit orbit_;
    bool did_maneuver_ = false;
    glm::vec3 raw_current_maneuver_{0.0f};
};

}  // namespace sim

#endif  // GAME_SIM_SATELLITE_H_
