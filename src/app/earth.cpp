#define GLEW_STATIC
#include <GL/glew.h>

#include <GLFW/glfw3.h>

#define GLM_FORCE_RADIANS
#include <glm/glm.hpp>
#include <glm/gtc/matrix_transform.hpp>
#include <glm/gtc/type_ptr.hpp>

#include "app/earth.h"
#include "render/camera.h"
#include "render/hud.h"
#include "render/model.h"
#include "render/shader.h"
#include "sim/ai_controller.h"
#include "sim/human_controller.h"
#include "sim/player.h"
#include "sim/satellite_spec.h"
#include "sim/world.h"

namespace {

constexpr float kPi = 3.14159265358979f;

void key_callback(GLFWwindow* window, int key, int /*scancode*/, int action,
                  int /*mode*/) {
    if (key == GLFW_KEY_ESCAPE && action == GLFW_PRESS) {
        glfwSetWindowShouldClose(window, GL_TRUE);
    }
    auto* earth = static_cast<EarthSystem*>(glfwGetWindowUserPointer(window));
    if (earth) earth->HandleKey(key, action);
}

void mouse_callback(GLFWwindow* window, double xpos, double ypos) {
    auto* earth = static_cast<EarthSystem*>(glfwGetWindowUserPointer(window));
    if (earth) earth->HandleMouseMove(xpos, ypos);
}

}  // namespace

void EarthSystem::HandleKey(int key, int action) {
    if (action == GLFW_PRESS) {
        keys_[key] = true;
        was_pressed_[key] = true;
    } else if (action == GLFW_RELEASE) {
        keys_[key] = false;
    }
}

void EarthSystem::HandleMouseMove(double xpos, double ypos) {
    if (first_mouse_) {
        last_x_ = xpos;
        last_y_ = ypos;
        first_mouse_ = false;
    }
    GLfloat xoffset = xpos - last_x_;
    GLfloat yoffset = last_y_ - ypos;
    last_x_ = xpos;
    last_y_ = ypos;
    camera_.ProcessMouseMovement(xoffset, yoffset);
}

void EarthSystem::UpdateEarthPhase(double sim_dt_seconds) {
    constexpr float kSecondsPerDay = 60.0f * 60.0f * 24.0f;
    earth_phase_ += static_cast<float>(2.0 * kPi * sim_dt_seconds / kSecondsPerDay);
    if (earth_phase_ > 2.0f * kPi) earth_phase_ -= 2.0f * kPi;
}

void EarthSystem::processKeys(GLfloat deltaTime) {
    if (keys_[GLFW_KEY_W]) camera_.ProcessKeyboard(FORWARD, deltaTime);
    if (keys_[GLFW_KEY_S]) camera_.ProcessKeyboard(BACKWARD, deltaTime);
    if (keys_[GLFW_KEY_A]) camera_.ProcessKeyboard(LEFT, deltaTime);
    if (keys_[GLFW_KEY_D]) camera_.ProcessKeyboard(RIGHT, deltaTime);

    glm::vec3 forward{1.0f, 0.0f, 0.0f};
    glm::vec3 left{0.0f, 1.0f, 0.0f};
    glm::vec3 up{0.0f, 0.0f, 1.0f};
    glm::vec3 maneuver{0.0f};
    if (keys_[GLFW_KEY_UP]) maneuver += forward;
    if (keys_[GLFW_KEY_DOWN]) maneuver -= forward;
    if (keys_[GLFW_KEY_LEFT]) maneuver += left;
    if (keys_[GLFW_KEY_RIGHT]) maneuver -= left;
    if (keys_[GLFW_KEY_PAGE_UP]) maneuver += up;
    if (keys_[GLFW_KEY_PAGE_DOWN]) maneuver -= up;

    int dilation_step = 0;
    if (keys_[GLFW_KEY_Q]) dilation_step += 1;
    if (keys_[GLFW_KEY_E]) dilation_step -= 1;

    if (keys_[GLFW_KEY_T]) planning_step_seconds_++;
    if (keys_[GLFW_KEY_G] && planning_step_seconds_ > 0) {
        planning_step_seconds_--;
    }

    if (human_controller_) {
        human_controller_->maneuver_direction = maneuver;
        human_controller_->dilation_step = dilation_step;

        if (was_pressed_[GLFW_KEY_TAB] && !keys_[GLFW_KEY_TAB]) {
            human_controller_->request_select_next = true;
            was_pressed_[GLFW_KEY_TAB] = false;
        }
        if (was_pressed_[GLFW_KEY_N] && !keys_[GLFW_KEY_N]) {
            human_controller_->request_launch = true;
            was_pressed_[GLFW_KEY_N] = false;
        }
        if (was_pressed_[GLFW_KEY_R] && !keys_[GLFW_KEY_R]) {
            human_controller_->request_destroy = true;
            was_pressed_[GLFW_KEY_R] = false;
        }
    }

    if (was_pressed_[GLFW_KEY_P] && !keys_[GLFW_KEY_P]) {
        planning_mode_ = !planning_mode_;
        if (planning_mode_) planning_world_.CloneStateFrom(world_);
        was_pressed_[GLFW_KEY_P] = false;
    }

    if (planning_mode_) {
        planning_maneuver_ = maneuver;
    }
}

EarthSystem::EarthSystem(GLFWwindow* window, GLuint screenWidth,
                         GLuint screenHeight)
    : window_(window),
      camera_(glm::vec3(3 * kEarthRadius, 0.0f, 0.0f)),
      planet_shader_("shaders/planet.vs", "shaders/planet.frag"),
      planet_model_("resources/3D/earth/earth.obj"),
      line_shader_("shaders/basic.vs", "shaders/basic.frag"),
      game_screen_(0, 0, screenWidth, screenHeight, projection_),
      width_(screenWidth),
      height_(screenHeight) {
    glfwSetWindowUserPointer(window_, this);
    glfwSetKeyCallback(window_, key_callback);
    glfwSetCursorPosCallback(window_, mouse_callback);
    glfwSetInputMode(window_, GLFW_CURSOR, GLFW_CURSOR_DISABLED);

    glViewport(0, 0, screenWidth, screenHeight);
    glEnable(GL_DEPTH_TEST);
    glEnable(GL_BLEND);
    glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);

    projection_ = glm::perspective(45.0f,
                                   (GLfloat)screenWidth / (GLfloat)screenHeight,
                                   300.0f, 100 * kEarthRadius);
    game_screen_.projection = projection_;

    planet_shader_.Use();
    glUniformMatrix4fv(glGetUniformLocation(planet_shader_.Program, "projection"),
                       1, GL_FALSE, glm::value_ptr(projection_));
    line_shader_.Use();
    glUniformMatrix4fv(glGetUniformLocation(line_shader_.Program, "projection"),
                       1, GL_FALSE, glm::value_ptr(projection_));

    // Set up players. The human is index 0, the AI is index 1. Each starts
    // with one satellite to keep parity with the previous behavior.
    sim::Player& human = world_.AddPlayer("Player", sim::PlayerKind::Human,
                                          glm::vec3(0.0f, 0.0f, 1.0f));
    sim::Player& ai = world_.AddPlayer("Adversary", sim::PlayerKind::Ai,
                                       glm::vec3(0.9f, 0.3f, 0.3f));
    human.AddSatellite(sim::SatelliteSpec{});

    sim::SatelliteSpec ai_spec;
    ai_spec.name = "Adversary-1";
    ai_spec.initial_r = vec3D{42164.0, 0.0, 0.0};
    ai_spec.initial_v = vec3D{0.0, 3.0646981, 0.0};
    ai.AddSatellite(ai_spec);

    auto h = std::make_unique<sim::HumanController>();
    human_controller_ = h.get();
    controllers_.push_back(std::move(h));
    controllers_.push_back(std::make_unique<sim::AiController>());
    human_player_idx_ = world_.human_player_index();
}

void EarthSystem::step(GLfloat deltaTime) {
    // 1. Drive each controller (mutates satellites' maneuver intents).
    for (int i = 0; i < world_.player_count(); ++i) {
        controllers_[i]->Tick(world_.player(i), world_, deltaTime);
    }
    if (human_controller_) human_controller_->ConsumeOneShots();

    // 2. Compute simulated dt and advance.
    const double sim_dt =
        static_cast<double>(deltaTime) * world_.EffectiveDilation();
    if (planning_mode_) {
        planning_world_.CloneStateFrom(world_);
        if (planning_world_.player_count() > human_player_idx_ &&
            human_player_idx_ >= 0) {
            sim::Player& planning_human =
                planning_world_.player(human_player_idx_);
            if (sim::Satellite* sat = planning_human.selected()) {
                sat->SetManeuver(planning_maneuver_);
            }
        }
        planning_world_.Advance(static_cast<double>(planning_step_seconds_));
    }
    world_.Advance(sim_dt);
    UpdateEarthPhase(sim_dt);

    // 3. Draw planet.
    glm::mat4 view = camera_.GetViewMatrix();
    planet_shader_.Use();
    glUniformMatrix4fv(glGetUniformLocation(planet_shader_.Program, "view"), 1,
                       GL_FALSE, glm::value_ptr(view));
    glm::mat4 model(1.0f);
    float pscale = 18.4759f;
    model = glm::rotate(model, earth_phase_, glm::vec3(0.0f, 0.0f, 1.0f));
    model = glm::rotate(model, float(kPi / 2.0), glm::vec3(1.0f, 0.0f, 0.0f));
    model = glm::translate(model, glm::vec3(0.0f, -1.0f * pscale, 0.0f));
    model = glm::scale(model, glm::vec3(pscale, pscale, pscale));
    glUniformMatrix4fv(glGetUniformLocation(planet_shader_.Program, "model"), 1,
                       GL_FALSE, glm::value_ptr(model));
    planet_model_.Draw(planet_shader_);

    // 4. Draw lines (orbits + targeting).
    line_shader_.Use();
    glUniformMatrix4fv(glGetUniformLocation(line_shader_.Program, "view"), 1,
                       GL_FALSE, glm::value_ptr(view));
    glm::mat4 ident(1.0f);
    glUniformMatrix4fv(glGetUniformLocation(line_shader_.Program, "model"), 1,
                       GL_FALSE, glm::value_ptr(ident));

    if (planning_mode_) {
        planning_view_.Render(planning_world_, line_shader_, human_player_idx_,
                              /*orbits_only_for_selected=*/true);
        game_screen_.RenderHud(line_shader_, planning_world_,
                               human_player_idx_, view);
    }
    world_view_.Render(world_, line_shader_, human_player_idx_,
                       /*orbits_only_for_selected=*/false);
    game_screen_.RenderHud(line_shader_, world_, human_player_idx_, view);

    // 5. Overlays.
    game_screen_.RenderHelp();
    game_screen_.RenderStatus(world_.EffectiveDilation(), planning_mode_);
}
