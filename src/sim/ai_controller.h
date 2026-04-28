#ifndef GAME_SIM_AI_CONTROLLER_H_
#define GAME_SIM_AI_CONTROLLER_H_

#include "sim/controller.h"

namespace sim {

// Stub AI player. Currently produces no maneuvers; it exists as a structural
// placeholder so the rest of the engine treats human and AI players
// uniformly. Plug in goal logic here as mechanics solidify.
class AiController : public Controller {
  public:
    void Tick(Player& self, World& world, double real_dt_seconds) override;
};

}  // namespace sim

#endif  // GAME_SIM_AI_CONTROLLER_H_
