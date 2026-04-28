#ifndef GAME_RENDER_HUD_H_
#define GAME_RENDER_HUD_H_

#define GLEW_STATIC
#include <GL/glew.h>

#define GLM_FORCE_RADIANS
#include <glm/glm.hpp>
#include <glm/gtc/matrix_transform.hpp>

#include "render/shader.h"
#include "render/writer.h"

namespace sim { class World; }

namespace render {

// HUD layer: targeting lines, distance/delta-V annotations, control overlay.
// Reads simulation state only.
class GameScreen {
  public:
    GameScreen(GLuint x, GLuint y, GLuint w, GLuint h, glm::mat4 projection);

    glm::mat4 projection;

    glm::vec3 ScreenPosition(glm::vec3 real_position, glm::mat4 view);

    // Targeting lines from the active player's selected satellite to every
    // other satellite (across all players).
    void RenderHud(Shader shader, const sim::World& world,
                   int active_player_index, glm::mat4 view);
    void RenderHelp();
    void RenderStatus(double effective_dilation, bool planning);

  private:
    glm::vec4 screen_dim_;
    FtWriter text_writer_;
};

}  // namespace render

#endif  // GAME_RENDER_HUD_H_
