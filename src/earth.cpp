// GLEW
#define GLEW_STATIC
#include <GL/glew.h>

// GLFW
#include <GLFW/glfw3.h>

// GL includes
#include "shader.h"
#include "camera.h"
#include "model.h"

// GLM Mathemtics
#define GLM_FORCE_RADIANS
#include <glm/glm.hpp>
#include <glm/gtc/matrix_transform.hpp>
#include <glm/gtc/type_ptr.hpp>

// My stuff
#include <iostream>

#include "hud.h"
#include "orbital_set.h"
#include "earth.h"

// PI is already defined as a macro in ellipse_3d.h (included transitively)

namespace {
void key_callback(GLFWwindow* window, int key, int scancode, int action, int mode) {
    if (key == GLFW_KEY_ESCAPE && action == GLFW_PRESS)
        glfwSetWindowShouldClose(window, GL_TRUE);
    auto* earth = static_cast<EarthSystem*>(glfwGetWindowUserPointer(window));
    if (earth) earth->HandleKey(key, action);
}
void mouse_callback(GLFWwindow* window, double xpos, double ypos) {
    auto* earth = static_cast<EarthSystem*>(glfwGetWindowUserPointer(window));
    if (earth) earth->HandleMouseMove(xpos, ypos);
}
} // namespace

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

void EarthSystem::UpdateEarthPhase()
{
    float dif = (2.0f*PI/(60.0f*60.0f*24.0f));
    earth_phase_ += dif*time_factor_*kTimeResolution;
    if( earth_phase_ > (2.0f*PI) ) {
        earth_phase_ -= (2.0f*PI);
    }
}

void EarthSystem::processKeys(GLfloat deltaTime)
{
    glm::vec3 forward = {1.0f, 0.0f, 0.0f};
    glm::vec3 left = {0.0f, 1.0f, 0.0f};
    glm::vec3 up = {0.0f, 0.0f, 1.0f};
    glm::vec3 current_maneuver = {0.0f, 0.0f, 0.0f};
    if(planning_mode_)
    {
        current_maneuver = planning_maneuver_;
        planning_set_.Clone(real_set_);
    }
    if(keys_[GLFW_KEY_W])
        camera_.ProcessKeyboard(FORWARD, deltaTime);
    if(keys_[GLFW_KEY_S])
        camera_.ProcessKeyboard(BACKWARD, deltaTime);
    if(keys_[GLFW_KEY_A])
        camera_.ProcessKeyboard(LEFT, deltaTime);
    if(keys_[GLFW_KEY_D])
        camera_.ProcessKeyboard(RIGHT, deltaTime);
    if(keys_[GLFW_KEY_UP])
        current_maneuver += forward;
    if(keys_[GLFW_KEY_DOWN])
        current_maneuver -= forward;
    if(keys_[GLFW_KEY_LEFT])
        current_maneuver += left;
    if(keys_[GLFW_KEY_RIGHT])
        current_maneuver -= left;
    if(keys_[GLFW_KEY_PAGE_UP])
        current_maneuver += up;
    if(keys_[GLFW_KEY_PAGE_DOWN])
        current_maneuver -= up;
    if(keys_[GLFW_KEY_Q])
        time_factor_++;
    if(keys_[GLFW_KEY_E] && time_factor_>0)
        time_factor_--;
    if(keys_[GLFW_KEY_T])
        dt_++;
    if(keys_[GLFW_KEY_G] && dt_>0)
        dt_--;
    if(planning_mode_)
    {
        planning_maneuver_ = current_maneuver;
        planning_set_.GetSelectedShip().SetManeuver(current_maneuver);
    } else {
        real_set_.GetSelectedShip().SetManeuver(current_maneuver);
    }
    // Selector
    if(was_pressed_[GLFW_KEY_TAB] && !keys_[GLFW_KEY_TAB]){
        real_set_.SelectNextShip();
        was_pressed_[GLFW_KEY_TAB] = false;
    }
    // Add ship
    if(was_pressed_[GLFW_KEY_N] && !keys_[GLFW_KEY_N]){
        real_set_.AddSatellite();
        was_pressed_[GLFW_KEY_N] = false;
    }
    // Remove ship
    if(was_pressed_[GLFW_KEY_R] && !keys_[GLFW_KEY_R]){
        real_set_.RemoveSatellite();
        was_pressed_[GLFW_KEY_R] = false;
    }
    // Planning Mode
    if(was_pressed_[GLFW_KEY_P] && !keys_[GLFW_KEY_P]){
        if (!planning_mode_)
        {
            planning_set_.Clone(real_set_);
            planning_mode_ = true;
        } else {
            planning_mode_ = false;
        }
        was_pressed_[GLFW_KEY_P] = false;
    }
}

EarthSystem::EarthSystem(GLFWwindow* window, GLuint screenWidth, GLuint screenHeight)
    : window_(window),
      camera_(glm::vec3(3 * kEarthRadius, 0.0f, 0.0f)),
      planet_shader_("shaders/planet.vs", "shaders/planet.frag"),
      planet_model_("resources/3D/earth/earth.obj"),
      game_screen_(0, 0, screenWidth, screenHeight, projection_),
      line_shader_("shaders/basic.vs", "shaders/basic.frag")
{
    width_=screenWidth;
    height_=screenHeight;

    // Register GLFW callbacks
    glfwSetWindowUserPointer(window_, this);
    glfwSetKeyCallback(window_, key_callback);
    glfwSetCursorPosCallback(window_, mouse_callback);
    glfwSetInputMode(window_, GLFW_CURSOR, GLFW_CURSOR_DISABLED);

    // Define the viewport dimensions
    glViewport(0, 0, screenWidth, screenHeight);

    // Setup OpenGL options
    glEnable(GL_DEPTH_TEST);

    // Enable transparency
    glEnable(GL_BLEND);
    glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);

    // Setup consistent projection_ for system
    projection_ = glm::perspective(45.0f, (GLfloat)screenWidth/(GLfloat)screenHeight, 300.0f, 100*kEarthRadius);

    game_screen_.projection_ = projection_;
    // Setup planet just once
    planet_shader_.Use();
    glUniformMatrix4fv(glGetUniformLocation(planet_shader_.Program, "projection"), 1, GL_FALSE, glm::value_ptr(projection_));
    line_shader_.Use();
    glUniformMatrix4fv(glGetUniformLocation(line_shader_.Program, "projection"), 1, GL_FALSE, glm::value_ptr(projection_));
    real_set_.AddSatellite();
    real_set_.GetSelectedShip().Select();
}

void EarthSystem::step(){
    glm::mat4 view = camera_.GetViewMatrix();
    planet_shader_.Use();
    glUniformMatrix4fv(glGetUniformLocation(planet_shader_.Program, "view"), 1, GL_FALSE, glm::value_ptr(view));
    glm::mat4 model(1.0f);
    float pscale = 18.4759f;
    model = glm::rotate(model, earth_phase_, glm::vec3(0.0f, 0.0f, 1.0f));
    model = glm::rotate(model, float(PI/2.0), glm::vec3(1.0f, 0.0f, 0.0f));
    model = glm::translate(model, glm::vec3(0.0f, -1*pscale, 0.0f));
    model = glm::scale(model, glm::vec3(pscale, pscale, pscale));
    glUniformMatrix4fv(glGetUniformLocation(planet_shader_.Program, "model"), 1, GL_FALSE, glm::value_ptr(model));
    planet_model_.Draw(planet_shader_);
    UpdateEarthPhase();

    line_shader_.Use();
    glUniformMatrix4fv(glGetUniformLocation(line_shader_.Program, "view"), 1, GL_FALSE, glm::value_ptr(view));
    glm::mat4 model2(1.0f);
    glUniformMatrix4fv(glGetUniformLocation(line_shader_.Program, "model"), 1, GL_FALSE, glm::value_ptr(model2));
    if(planning_mode_)
    {
        planning_set_.Advance(float(dt_));
        // Render orbits and their satellites
        planning_set_.Render(line_shader_, true);
        // Render display info and target lines
        game_screen_.RenderHud(line_shader_, planning_set_, view);
    }
    // Render orbits and their satellites
    real_set_.Render(line_shader_, false);
    real_set_.Advance(time_factor_*kTimeResolution);
    // Render display info and target lines
    game_screen_.RenderHud(line_shader_, real_set_, view);
    // Render key mapping overlay
    game_screen_.RenderHelp();
}
