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

#define PI 3.14159265
bool planning_mode = false;
const float earth_radius = 6371;
int timeFactor = 10;
int dt = 0;
glm::vec3 planning_maneuver = {0.0f, 0.0f, 0.0f};

// Camera
Camera camera(glm::vec3(3*earth_radius, 0.0f, 0.0f));
bool keys[1024];
// This array will only flip back once an action undoes it
bool was_pressed[1024];
GLfloat lastX = 400, lastY = 300;
bool firstMouse = true;

void key_callback(GLFWwindow* window, int key, int scancode, int action, int mode)
{
    if(key == GLFW_KEY_ESCAPE && action == GLFW_PRESS)
        glfwSetWindowShouldClose(window, GL_TRUE);

    if(action == GLFW_PRESS) {
        keys[key] = true;
        was_pressed[key] = true;
    } else if(action == GLFW_RELEASE) {
        keys[key] = false;
    }
}

void mouse_callback(GLFWwindow* window, double xpos, double ypos)
{
    if(firstMouse)
    {
        lastX = xpos;
        lastY = ypos;
        firstMouse = false;
    }
    GLfloat xoffset = xpos - lastX;
    GLfloat yoffset = lastY - ypos;
    lastX = xpos;
    lastY = ypos;
    camera.ProcessMouseMovement(xoffset, yoffset);
}

void EarthSystem::UpdateEarthPhase()
{
    float dif = (2.0*PI/(60.0*60.0*24.0));
    earth_phase_ += dif*timeFactor*TIME_RESOLUTION;
    if( earth_phase_ > (2.0*PI) ) {
        earth_phase_ -= (2.0*PI);
    }
}

void EarthSystem::processKeys(GLfloat deltaTime)
{
    glm::vec3 forward = {1.0f, 0.0f, 0.0f};
    glm::vec3 left = {0.0f, 1.0f, 0.0f};
    glm::vec3 up = {0.0f, 0.0f, 1.0f};
    glm::vec3 current_maneuver = {0.0f, 0.0f, 0.0f};
    if(planning_mode)
    {
        current_maneuver = planning_maneuver;
        planning_set_.Clone(real_set_);
    }
    if(keys[GLFW_KEY_W])
        camera.ProcessKeyboard(FORWARD, deltaTime);
    if(keys[GLFW_KEY_S])
        camera.ProcessKeyboard(BACKWARD, deltaTime);
    if(keys[GLFW_KEY_A])
        camera.ProcessKeyboard(LEFT, deltaTime);
    if(keys[GLFW_KEY_D])
        camera.ProcessKeyboard(RIGHT, deltaTime);
    if(keys[GLFW_KEY_UP])
        current_maneuver += forward;
    if(keys[GLFW_KEY_DOWN])
        current_maneuver -= forward;
    if(keys[GLFW_KEY_LEFT])
        current_maneuver += left;
    if(keys[GLFW_KEY_RIGHT])
        current_maneuver -= left;
    if(keys[GLFW_KEY_PAGE_UP])
        current_maneuver += up;
    if(keys[GLFW_KEY_PAGE_DOWN])
        current_maneuver -= up;
    if(keys[GLFW_KEY_Q])
        timeFactor++;
    if(keys[GLFW_KEY_E] && timeFactor>0)
        timeFactor--;
    if(keys[GLFW_KEY_T])
        dt+=20;
    if(keys[GLFW_KEY_G] && dt>0)
        dt-=20;
    if(planning_mode)
    {
        planning_maneuver = current_maneuver;
        planning_set_.GetSelectedShip().SetManeuver(current_maneuver);
    } else {
        real_set_.GetSelectedShip().SetManeuver(current_maneuver);
    }
    // TODO: use a void that accepts member function pointers
    // http://stackoverflow.com/questions/12662891/c-passing-member-function-as-argument
    // Selector
    if(was_pressed[GLFW_KEY_TAB] && !keys[GLFW_KEY_TAB]){
        real_set_.SelectNextShip();
        was_pressed[GLFW_KEY_TAB] = false;
    }
    // Add ship
    if(was_pressed[GLFW_KEY_N] && !keys[GLFW_KEY_N]){
        real_set_.AddSatellite();
        was_pressed[GLFW_KEY_N] = false;
    }
    // Remove ship
    if(was_pressed[GLFW_KEY_R] && !keys[GLFW_KEY_R]){
        real_set_.RemoveSatellite();
        was_pressed[GLFW_KEY_R] = false;
    }
    // Planning Mode
    if(was_pressed[GLFW_KEY_P] && !keys[GLFW_KEY_P]){
        if (!planning_mode)
        {
            planning_set_.Clone(real_set_);
            planning_mode = true;
        } else {
            planning_mode = false;
        }
        was_pressed[GLFW_KEY_P] = false;
    }
}

EarthSystem::EarthSystem(GLuint screenWidth, GLuint screenHeight): planet_shader_("shaders/planet.vs", "shaders/planet.frag"), planet_model_("resources/3D/earth/earth.obj"), game_screen_(0, 0, screenWidth, screenHeight, projection_), line_shader_("shaders/basic.vs", "shaders/basic.frag") {
    width_=screenWidth;
    height_=screenHeight;
    // Define the viewport dimensions
    glViewport(0, 0, screenWidth, screenHeight);

    // Setup OpenGL options
    glEnable(GL_DEPTH_TEST);

    // Enable transparency
    glEnable(GL_BLEND);
    glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
    // this should be enabled for performance
    //glEnable(GL_CULL_FACE);

    // Draw in wireframe
    //glPolygonMode(GL_FRONT_AND_BACK, GL_LINE);

    // Setup consistent projection_ for system
    projection_ = glm::perspective(45.0f, (GLfloat)screenWidth/(GLfloat)screenHeight, 300.0f, 100*earth_radius);

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
    glm::mat4 view = camera.GetViewMatrix();
    planet_shader_.Use();
    glUniformMatrix4fv(glGetUniformLocation(planet_shader_.Program, "view"), 1, GL_FALSE, glm::value_ptr(view));
    glm::mat4 model;
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
    glm::mat4 model2;
    glUniformMatrix4fv(glGetUniformLocation(line_shader_.Program, "model"), 1, GL_FALSE, glm::value_ptr(model2));
    if(planning_mode)
    {
        planning_set_.Advance(float(dt));
        // Render orbits and their satellites
        planning_set_.Render(line_shader_, true);
        // Render display info and target lines
        game_screen_.RenderHud(line_shader_, planning_set_, view);
    }
    // Render orbits and their satellites
    real_set_.Render(line_shader_, false);
    real_set_.Advance(timeFactor*TIME_RESOLUTION);
    // Render display info and target lines
    game_screen_.RenderHud(line_shader_, real_set_, view);
}
