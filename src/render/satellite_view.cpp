#include "render/satellite_view.h"

#include "sim/satellite.h"

namespace render {

SatelliteView::SatelliteView(const sim::Satellite& seed)
    : cube_(seed.orbit()), ellipse_(seed.orbit()) {}

void SatelliteView::Render(const sim::Satellite& sat, Shader shader,
                           glm::vec3 body_color, bool draw_orbit) {
    cube_.SetColor(body_color);
    ellipse_.SetColor(body_color);
    cube_.Update(sat.orbit());
    cube_.Render(shader);
    if (draw_orbit) {
        ellipse_.Update(sat.orbit());
        ellipse_.Render(shader);
    }
}

}  // namespace render
