#ifndef GAME_RENDER_SATELLITE_VIEW_H_
#define GAME_RENDER_SATELLITE_VIEW_H_

#define GLM_FORCE_RADIANS
#include <glm/glm.hpp>

#include "render/cube.h"
#include "render/ellipse_3d.h"
#include "render/shader.h"

namespace sim { class Satellite; }

namespace render {

// Owns the GL buffers used to draw a single satellite (cube marker + orbit
// ellipse). One instance maps to one slot in a render pool; it does not
// retain a pointer to its sim object.
class SatelliteView {
  public:
    explicit SatelliteView(const sim::Satellite& seed);

    // Draw the satellite's cube and (optionally) its orbit ellipse, using
    // `body_color` for the cube/ellipse. When `draw_orbit` is false only
    // the cube is drawn (used by the projection layer).
    void Render(const sim::Satellite& sat, Shader shader, glm::vec3 body_color,
                bool draw_orbit);

  private:
    Cube cube_;
    Ellipse3d ellipse_;
};

}  // namespace render

#endif  // GAME_RENDER_SATELLITE_VIEW_H_
