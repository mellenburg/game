#include "sim/ai_controller.h"

#include "sim/player.h"
#include "sim/satellite.h"
#include "sim/world.h"

namespace sim {

void AiController::Tick(Player& self, World& /*world*/, double /*real_dt*/) {
    // Clear any maneuver from prior ticks so the AI's satellites coast by
    // default. Replace this body with real AI policy when ready.
    if (Satellite* sat = self.selected()) {
        sat->ClearManeuver();
    }
}

}  // namespace sim
