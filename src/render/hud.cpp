#define GLEW_STATIC
#include <GL/glew.h>

#define GLM_FORCE_RADIANS
#include <glm/glm.hpp>
#include <glm/gtc/matrix_transform.hpp>
#include <glm/gtc/type_ptr.hpp>

#include <iomanip>
#include <sstream>

#include "render/hud.h"
#include "render/line.h"
#include "render/shader.h"
#include "render/writer.h"
#include "sim/player.h"
#include "sim/satellite.h"
#include "sim/world.h"

namespace render {

namespace {

bool SolveQuadratic(GLfloat a, GLfloat b, GLfloat c, GLfloat& x0, GLfloat& x1) {
    float discr = b * b - 4 * a * c;
    if (discr < 0) return false;
    if (discr == 0) {
        x0 = x1 = -0.5f * b / a;
    } else {
        float q = (b > 0) ? -0.5f * (b + sqrt(discr)) : -0.5f * (b - sqrt(discr));
        x0 = q / a;
        x1 = c / q;
    }
    if (x0 > x1) std::swap(x0, x1);
    return true;
}

bool LineIntersectsEarth(glm::vec3 start, glm::vec3 end) {
    GLfloat t0, t1;
    GLfloat radius2 = 40589641.0f;
    glm::vec3 dir = end - start;
    GLfloat a = glm::dot(dir, dir);
    GLfloat b = 2 * glm::dot(dir, start);
    GLfloat c = glm::dot(start, start) - radius2;
    if (!SolveQuadratic(a, b, c, t0, t1)) return false;
    if (t0 > t1) std::swap(t0, t1);
    if (t0 < 0) {
        t0 = t1;
        if (t0 < 0) return false;
    }
    if (t0 > 1) return false;
    return true;
}

}  // namespace

GameScreen::GameScreen(GLuint x, GLuint y, GLuint w, GLuint h, glm::mat4 proj)
    : projection(proj), text_writer_(w, h) {
    screen_dim_ = glm::vec4(x, y, w, h);
}

glm::vec3 GameScreen::ScreenPosition(glm::vec3 real_position, glm::mat4 view) {
    glm::vec3 view_position = glm::vec3(view * glm::vec4(real_position, 1));
    return glm::project(view_position, glm::mat4(), projection, screen_dim_);
}

void GameScreen::RenderHelp() {
    GLfloat x = 10.0f;
    GLfloat top = screen_dim_.w - 30.0f;
    GLfloat line_height = 22.0f;
    GLfloat scale = 0.8f;
    glm::vec3 white(1.0f, 1.0f, 1.0f);
    glm::vec3 dim(0.6f, 0.6f, 0.6f);

    text_writer_.RenderText("-- Controls --", x, top, scale, white);
    text_writer_.RenderText("WASD     Move camera", x, top - 1*line_height, scale, dim);
    text_writer_.RenderText("Mouse    Look around", x, top - 2*line_height, scale, dim);
    text_writer_.RenderText("Arrows   Maneuver", x, top - 3*line_height, scale, dim);
    text_writer_.RenderText("PgUp/Dn  Maneuver up/down", x, top - 4*line_height, scale, dim);
    text_writer_.RenderText("Q/E      Speed up/down", x, top - 5*line_height, scale, dim);
    text_writer_.RenderText("T/G      Time step +/-", x, top - 6*line_height, scale, dim);
    text_writer_.RenderText("N        Add satellite", x, top - 7*line_height, scale, dim);
    text_writer_.RenderText("R        Remove satellite", x, top - 8*line_height, scale, dim);
    text_writer_.RenderText("Tab      Select next", x, top - 9*line_height, scale, dim);
    text_writer_.RenderText("P        Planning mode", x, top - 10*line_height, scale, dim);
    text_writer_.RenderText("Esc      Quit", x, top - 11*line_height, scale, dim);
}

void GameScreen::RenderStatus(double effective_dilation, bool planning) {
    GLfloat x = screen_dim_.z - 360.0f;
    GLfloat y = screen_dim_.w - 30.0f;
    glm::vec3 color(0.85f, 0.85f, 0.85f);
    std::stringstream s;
    s << "Time: " << std::fixed << std::setprecision(1) << effective_dilation
      << "x real";
    text_writer_.RenderText(s.str(), x, y, 0.9f, color);
    if (planning) {
        text_writer_.RenderText("[PLANNING MODE]", x, y - 26.0f, 0.9f,
                                glm::vec3(1.0f, 0.6f, 0.2f));
    }
}

void GameScreen::RenderHud(Shader shader, const sim::World& world,
                           int active_player_index, glm::mat4 view) {
    if (active_player_index < 0 ||
        active_player_index >= world.player_count()) {
        return;
    }
    const sim::Satellite* main_sat = world.player(active_player_index).selected();
    if (!main_sat) return;
    glm::vec3 main_position = main_sat->GetR();
    glm::vec3 main_velocity = main_sat->GetV();

    for (int pi = 0; pi < world.player_count(); ++pi) {
        const auto& player = world.player(pi);
        for (int si = 0; si < player.satellite_count(); ++si) {
            if (pi == active_player_index && si == player.selected_index()) {
                continue;
            }
            const sim::Satellite& other = player.satellite(si);
            glm::vec3 other_position = other.GetR();
            glm::vec3 other_velocity = other.GetV();

            Line targeting;
            shader.Use();
            if (LineIntersectsEarth(main_position, other_position)) {
                glUniform3f(glGetUniformLocation(shader.Program, "setColor"),
                            1.0f, 1.0f, 0.0f);
            } else {
                glUniform3f(glGetUniformLocation(shader.Program, "setColor"),
                            1.0f, 0.0f, 0.0f);
            }
            targeting.Update(main_position, other_position);
            targeting.Draw(shader);

            glm::vec3 tex_pos = ScreenPosition(other_position, view);
            if (tex_pos.z >= 1) continue;

            std::stringstream s;
            float distance = glm::distance(main_position, other_position);
            s << "Distance: " << std::fixed << std::setprecision(0) << distance
              << " km";
            text_writer_.RenderText(s.str(), tex_pos.x, tex_pos.y, 1.0f,
                                    glm::vec3(0.5f, 0.8f, 0.2f));
            s.str("");
            float velocity = glm::distance(main_velocity, other_velocity);
            s << "delta-V: " << std::fixed << std::setprecision(2) << velocity
              << " km/s";
            text_writer_.RenderText(s.str(), tex_pos.x, tex_pos.y - 28.0f, 1.0f,
                                    glm::vec3(0.5f, 0.8f, 0.2f));
        }
    }
}

}  // namespace render
