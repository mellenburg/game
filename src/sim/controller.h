#ifndef GAME_SIM_CONTROLLER_H_
#define GAME_SIM_CONTROLLER_H_

#define GLM_FORCE_RADIANS
#include <glm/glm.hpp>

namespace sim {

class Player;
class World;

// A Controller drives a single Player on each tick. Subclasses implement the
// policy: human input handlers, AI planners, scripted demos, replays.
//
// The Controller owns no game state — it observes the world and mutates its
// own player. Keep this header light so swapping windowing systems doesn't
// drag in render dependencies.
class Controller {
  public:
    virtual ~Controller() = default;

    // Called every real-time frame *before* World::Advance. real_dt_seconds
    // is wall-clock time since the last tick.
    virtual void Tick(Player& self, World& world, double real_dt_seconds) = 0;
};

}  // namespace sim

#endif  // GAME_SIM_CONTROLLER_H_
