#define GLM_FORCE_RADIANS
#include <glm/glm.hpp>

#include "sim/orbit.h"
#include "sim/satellite.h"

namespace sim {

Satellite::Satellite() : Satellite(SatelliteSpec{}) {}

Satellite::Satellite(const SatelliteSpec& spec)
    : spec_(spec), orbit_(spec.initial_r, spec.initial_v) {}

void Satellite::SetManeuver(glm::vec3 raw_direction) {
    raw_current_maneuver_ = raw_direction;
    did_maneuver_ = true;
}

void Satellite::ClearManeuver() {
    raw_current_maneuver_ = glm::vec3(0.0f);
    did_maneuver_ = false;
}

glm::vec3 Satellite::GetCurrentManeuver() const {
    return float(spec_.delta_v_per_press) * raw_current_maneuver_;
}

glm::vec3 Satellite::GetR() const {
    return glm::vec3(orbit_.r.i, orbit_.r.j, orbit_.r.k);
}

glm::vec3 Satellite::GetV() const {
    return glm::vec3(orbit_.v.i, orbit_.v.j, orbit_.v.k);
}

void Satellite::AdvanceTime(double dt_seconds) {
    if (did_maneuver_ && glm::length(raw_current_maneuver_) == 0.0f) {
        did_maneuver_ = false;
    }
    if (did_maneuver_) {
        orbit_.relative_maneuver(GetCurrentManeuver(), dt_seconds);
    } else {
        orbit_.propagate(dt_seconds);
    }
    did_maneuver_ = false;
}

void Satellite::CloneStateFrom(const Satellite& other) {
    orbit_.clone(other.orbit_);
    raw_current_maneuver_ = other.raw_current_maneuver_;
    did_maneuver_ = other.did_maneuver_;
}

}  // namespace sim
