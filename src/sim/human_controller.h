#ifndef GAME_SIM_HUMAN_CONTROLLER_H_
#define GAME_SIM_HUMAN_CONTROLLER_H_

#define GLM_FORCE_RADIANS
#include <glm/glm.hpp>

#include "sim/controller.h"

namespace sim {

// Translates an input snapshot (filled by the harness from GLFW) into player
// actions. The input layer doesn't reach into Player directly; everything
// flows through the fields below.
class HumanController : public Controller {
  public:
    // Per-tick inputs, written by the harness.
    glm::vec3 maneuver_direction{0.0f};
    bool request_select_next = false;
    bool request_launch = false;
    bool request_destroy = false;
    int dilation_step = 0;  // +1 / -1 nudges per tick

    void Tick(Player& self, World& world, double real_dt_seconds) override;

    void ConsumeOneShots() {
        request_select_next = false;
        request_launch = false;
        request_destroy = false;
        dilation_step = 0;
    }
};

}  // namespace sim

#endif  // GAME_SIM_HUMAN_CONTROLLER_H_
