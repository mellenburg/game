#include "sim/human_controller.h"

#include "sim/player.h"
#include "sim/satellite.h"
#include "sim/world.h"

namespace sim {

void HumanController::Tick(Player& self, World& world, double /*real_dt*/) {
    if (request_launch) self.AddSatellite();
    if (request_destroy) self.RemoveSelected();
    if (request_select_next) self.SelectNext();

    if (dilation_step != 0) {
        self.set_requested_dilation(self.requested_dilation() +
                                    static_cast<double>(dilation_step));
    }

    if (Satellite* sat = self.selected()) {
        sat->SetManeuver(maneuver_direction);
    }
}

}  // namespace sim
