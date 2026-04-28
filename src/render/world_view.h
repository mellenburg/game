#ifndef GAME_RENDER_WORLD_VIEW_H_
#define GAME_RENDER_WORLD_VIEW_H_

#include <memory>
#include <vector>

#define GLM_FORCE_RADIANS
#include <glm/glm.hpp>

#include "render/satellite_view.h"
#include "render/shader.h"

namespace sim { class World; }

namespace render {

// Owns the per-satellite GL state for an entire World. Resizes its internal
// pool of SatelliteViews to match the world's satellite count each frame.
//
// Caller decides how to display the selected ship of the *active* (human)
// player by passing its (player_index, satellite_index) to Render.
class WorldView {
  public:
    // If `orbits_only_for_selected` is true, only the selected satellite's
    // orbit ellipse is drawn (used for the planning-mode shadow).
    void Render(const sim::World& world, Shader shader,
                int active_player_index, bool orbits_only_for_selected);

  private:
    std::vector<std::unique_ptr<SatelliteView>> views_;
};

}  // namespace render

#endif  // GAME_RENDER_WORLD_VIEW_H_
