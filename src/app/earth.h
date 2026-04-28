#ifndef GAME_APP_EARTH_H_
#define GAME_APP_EARTH_H_

#define GLEW_STATIC
#include <GL/glew.h>

#include <GLFW/glfw3.h>

#define GLM_FORCE_RADIANS
#include <glm/glm.hpp>
#include <glm/gtc/matrix_transform.hpp>

#include <memory>
#include <vector>

#include "render/camera.h"
#include "render/hud.h"
#include "render/model.h"
#include "render/shader.h"
#include "render/world_view.h"
#include "sim/ai_controller.h"
#include "sim/controller.h"
#include "sim/human_controller.h"
#include "sim/world.h"

// Glue between GLFW, the rendering layer, and the simulation. Owns the live
// world, a planning-mode shadow world, and the per-player controllers.
class EarthSystem {
  public:
    static constexpr float kEarthRadius = 6371.0f;

    EarthSystem(GLFWwindow* window, GLuint width, GLuint height);
    void processKeys(GLfloat deltaTime);
    void step(GLfloat deltaTime);

    void HandleKey(int key, int action);
    void HandleMouseMove(double xpos, double ypos);

  private:
    void UpdateEarthPhase(double sim_dt_seconds);

    GLFWwindow* window_;
    Camera camera_;
    bool keys_[1024] = {};
    bool was_pressed_[1024] = {};
    GLfloat last_x_ = 400.0f;
    GLfloat last_y_ = 300.0f;
    bool first_mouse_ = true;
    bool planning_mode_ = false;
    glm::vec3 planning_maneuver_{0.0f};
    int planning_step_seconds_ = 0;

    glm::mat4 projection_;
    Shader planet_shader_;
    Model planet_model_;
    Shader line_shader_;

    sim::World world_;
    sim::World planning_world_;
    int human_player_idx_ = -1;
    std::vector<std::unique_ptr<sim::Controller>> controllers_;
    sim::HumanController* human_controller_ = nullptr;

    render::WorldView world_view_;
    render::WorldView planning_view_;
    render::GameScreen game_screen_;

    GLuint width_, height_;
    float earth_phase_ = 0.0f;
};

#endif  // GAME_APP_EARTH_H_
