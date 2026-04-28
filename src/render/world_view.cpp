#include "render/world_view.h"

#include "sim/player.h"
#include "sim/satellite.h"
#include "sim/world.h"

namespace render {

void WorldView::Render(const sim::World& world, Shader shader,
                       int active_player_index,
                       bool orbits_only_for_selected) {
    int total = world.total_satellite_count();
    while (static_cast<int>(views_.size()) < total) {
        // Seed any new view with the satellite that will populate that slot
        // this frame. Subsequent frames just reuse the slot.
        const int idx = static_cast<int>(views_.size());
        const auto refs = world.AllSatelliteRefs();
        const auto& seed_player = world.player(refs[idx].player_index);
        views_.push_back(std::make_unique<SatelliteView>(
            seed_player.satellite(refs[idx].satellite_index)));
    }
    if (static_cast<int>(views_.size()) > total) {
        views_.resize(total);
    }

    int linear_index = 0;
    for (int pi = 0; pi < world.player_count(); ++pi) {
        const auto& player = world.player(pi);
        const int selected_idx = player.selected_index();
        for (int si = 0; si < player.satellite_count(); ++si, ++linear_index) {
            const bool is_selected = (si == selected_idx);
            glm::vec3 color = is_selected && pi == active_player_index
                                  ? player.selected_color()
                                  : player.team_color();
            const bool draw_orbit =
                !orbits_only_for_selected ||
                (is_selected && pi == active_player_index);
            views_[linear_index]->Render(player.satellite(si), shader, color,
                                         draw_orbit);
        }
    }
}

}  // namespace render
