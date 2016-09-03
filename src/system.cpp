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
#include <vector>
#include <iostream>
#include <iomanip> //setw and setprecion
#include <sstream>

#include "cube.h"
#include "ellipse_3d.h"
#include "satellite.h"
#include "writer.h"
#include "line.h"
#include "hud.h"
#include "system.h"

#define PI 3.14159265
const float earth_radius = 6371;
int timeFactor = 15;
const float timeResolution = .033333333; // 1/30th of a second clock time

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

void GameSystem::UpdateEarthPhase()
{
    float dif = (2.0*PI/(60.0*60.0*24.0));
    earth_phase_ += dif*timeFactor*timeResolution;
    if( earth_phase_ > (2.0*PI) ) {
        earth_phase_ -= (2.0*PI);
    }
}
Satellite& GameSystem::GetSelectedShip() {
    return satellite_pool_[selected_ship_];
}

void GameSystem::SelectNextShip() {
    GetSelectedShip().Unselect();
    if( (selected_ship_ + 1) == (int) satellite_pool_.size()) {
        selected_ship_ = 0;
    } else {
        selected_ship_++;
    }
    GetSelectedShip().Select();
}

void GameSystem::processKeys(GLfloat deltaTime)
{
    // Camera controls
    if(keys[GLFW_KEY_W])
        camera.ProcessKeyboard(FORWARD, deltaTime);
    if(keys[GLFW_KEY_S])
        camera.ProcessKeyboard(BACKWARD, deltaTime);
    if(keys[GLFW_KEY_A])
        camera.ProcessKeyboard(LEFT, deltaTime);
    if(keys[GLFW_KEY_D])
        camera.ProcessKeyboard(RIGHT, deltaTime);
    if(keys[GLFW_KEY_UP])
        GetSelectedShip().thrustForward(timeFactor*timeResolution);
    if(keys[GLFW_KEY_DOWN])
        GetSelectedShip().thrustBackward(timeFactor*timeResolution);
    if(keys[GLFW_KEY_LEFT])
        GetSelectedShip().thrustLeft(timeFactor*timeResolution);
    if(keys[GLFW_KEY_RIGHT])
        GetSelectedShip().thrustRight(timeFactor*timeResolution);
    if(keys[GLFW_KEY_PAGE_UP])
        GetSelectedShip().thrustUp(timeFactor*timeResolution);
    if(keys[GLFW_KEY_PAGE_DOWN])
        GetSelectedShip().thrustDown(timeFactor*timeResolution);
    if(keys[GLFW_KEY_Q])
        timeFactor++;
    if(keys[GLFW_KEY_E] && timeFactor>0)
        timeFactor--;
    // TODO: use a void that accepts member function pointers
    // http://stackoverflow.com/questions/12662891/c-passing-member-function-as-argument
    // Selector
    if(was_pressed[GLFW_KEY_TAB] && !keys[GLFW_KEY_TAB]){
        this->SelectNextShip();
        was_pressed[GLFW_KEY_TAB] = false;
    }
    // Add ship
    if(was_pressed[GLFW_KEY_N] && !keys[GLFW_KEY_N]){
        this->AddSatellite();
        was_pressed[GLFW_KEY_N] = false;
    }
    // Remove ship
    if(was_pressed[GLFW_KEY_R] && !keys[GLFW_KEY_R]){
        this->RemoveSatellite();
        was_pressed[GLFW_KEY_R] = false;
    }
}

void GameSystem::AddSatellite(){
    Satellite mySat;
    satellite_pool_.push_back(mySat);
    GetSelectedShip().Unselect();
    selected_ship_ = satellite_pool_.size()-1;
    GetSelectedShip().Select();
}

void GameSystem::RemoveSatellite(){
    if( satellite_pool_.size() >0 ) {
        satellite_pool_.erase(satellite_pool_.begin()+selected_ship_);
        this->selected_ship_ = 0;
        GetSelectedShip().Select();
    }
}

GameSystem::GameSystem(GLuint screenWidth, GLuint screenHeight): planet_shader_("shaders/planet.vs", "shaders/planet.frag"), planet_model_("resources/3D/earth/earth.obj"), game_screen_(0, 0, screenWidth, screenHeight, projection_), line_shader_("shaders/basic.vs", "shaders/basic.frag") {
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
    this->AddSatellite();
    GetSelectedShip().Select();
}

void GameSystem::step(){
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
    //glUniform3f(glGetUniformLocation(line_shader_.Program, "setColor"), color.x, color.y, color.z);
    glUniform3f(glGetUniformLocation(line_shader_.Program, "setColor"), 1.0f, 0.0f, 0.0f);
    for (int i = 0; i<(int)satellite_pool_.size(); i++) {
        satellite_pool_[i].Render(line_shader_);
        satellite_pool_[i].orbit_.propagate(timeFactor*timeResolution);
    }
    game_screen_.RenderHud(line_shader_, satellite_pool_, selected_ship_, view);
}
