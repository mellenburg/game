#ifndef GAME_SYSTEM_H_
#define GAME_SYSTEM_H_

#define GLM_FORCE_RADIANS
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

#define PI 3.14159265
int timeFactor = 15;
float timeResolution = .033333333;
// Ten seconds per frame, 30
// KM/idealized area unit
float earthPhase = 0.0;
float dif = (2.0*PI/(60.0*60.0*24.0));
GLfloat scale = 6371.;

// Camera
Camera camera(glm::vec3(3.0f, 0.0f, 0.0f));
bool keys[1024];
// This array will only flip back once an action undoes it
bool was_pressed[1024];
GLfloat lastX = 400, lastY = 300;
bool firstMouse = true;

// Rando
bool press_new = false;
bool press_delete = false;
bool press_tab = false;

#pragma region "User input"
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

#pragma endregion

void updateEarthPhase()
{
    earthPhase += dif*timeFactor*timeResolution;
    if( earthPhase > (2.0*PI) ) {
        earthPhase -= (2.0*PI);
    }
}

class gameSystem {
    private:
        int selected_ship_ = 0;
        int total_ships_ = 0;
        glm::mat4 projection;
        Shader planetShader;
        Model planetModel;
        FtWriter textWriter;
        vector<Satellite> sBank;
        GLuint WIDTH, HEIGHT;
    public:
        gameSystem(GLuint, GLuint);
        void processKeys(GLfloat);
        void step();
        void AddSatellite();
        void RemoveSatellite();
        Satellite& GetSelectedShip();
        void SelectNextShip();
};

Satellite& gameSystem::GetSelectedShip() {
    return sBank[selected_ship_];
}

void gameSystem::SelectNextShip() {
    GetSelectedShip().Unselect();
    if( (selected_ship_ + 1)== total_ships_) {
        selected_ship_ = 0;
    } else {
        selected_ship_++;
    }
    GetSelectedShip().Select();
}

void gameSystem::processKeys(GLfloat deltaTime)
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

void gameSystem::AddSatellite(){
    Satellite mySat(projection);
    sBank.push_back(mySat);
    GetSelectedShip().Unselect();
    total_ships_++;
    selected_ship_ = total_ships_-1;
    GetSelectedShip().Select();
}

void gameSystem::RemoveSatellite(){
    if( this->total_ships_ >0 ) {
        sBank.erase(sBank.begin()+selected_ship_);
        this->selected_ship_ = 0;
        total_ships_--;
        GetSelectedShip().Select();
    }
}

gameSystem::gameSystem(GLuint screenWidth, GLuint screenHeight): planetShader("shaders/planet.vs", "shaders/planet.frag"), planetModel("resources/3D/earth/earth.obj"), textWriter(screenWidth, screenHeight) {
    WIDTH=screenWidth;
    HEIGHT=screenHeight;
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

    // Setup consistent projection for system
    projection = glm::perspective(45.0f, (GLfloat)screenWidth/(GLfloat)screenHeight, .1f, 100.0f);

    // Setup planet just once
    planetShader.Use();
    glUniformMatrix4fv(glGetUniformLocation(planetShader.Program, "projection"), 1, GL_FALSE, glm::value_ptr(projection));
    this->AddSatellite();
    GetSelectedShip().Select();
}

void gameSystem::step(){
    glm::mat4 view = camera.GetViewMatrix();
    planetShader.Use();
    glUniformMatrix4fv(glGetUniformLocation(planetShader.Program, "view"), 1, GL_FALSE, glm::value_ptr(view));
    glm::mat4 model;
    //Scaling to place clearly in center with radius ~1
    //Thus 6371km ~ 1unit here
    float pscale = .0029f; // sat-earth model
    //float pscale = .375; // desert planet
    // NOTE: sux2hard code but finding diameter of a sphere is lame
    model = glm::rotate(model, earthPhase, glm::vec3(0.0f, 0.0f, 1.0f));
    model = glm::rotate(model, float(PI/2.0), glm::vec3(1.0f, 0.0f, 0.0f));
    model = glm::translate(model, glm::vec3(0.0f, -1*pscale, 0.0f));
    model = glm::scale(model, glm::vec3(pscale, pscale, pscale));
    glUniformMatrix4fv(glGetUniformLocation(planetShader.Program, "model"), 1, GL_FALSE, glm::value_ptr(model));
    planetModel.Draw(planetShader);
    updateEarthPhase();
    for (int i = 0; i< total_ships_; i++) {
        sBank[i].Render(view);
        sBank[i].orbit_.propagate(timeFactor*timeResolution);
    }
    //TODO: turn this into a neat annotation class
    if(this->total_ships_ > 0) {
        glm::vec3 box_pos = GetSelectedShip().GetR()/scale;
        glm::vec3 box_pos_2 = glm::vec3(view*glm::vec4(box_pos, 1));
        glm::vec3 tex_pos = glm::project(box_pos_2, glm::mat4(), projection, glm::vec4(0,0,WIDTH,HEIGHT));
        std::stringstream s;
        float velocity = glm::length(GetSelectedShip().GetV());
        s<<"Velocity: "<<std::fixed<<std::setprecision(1)<<velocity<<" km/s";
        textWriter.RenderText(s.str(), tex_pos.x, tex_pos.y, 1.0f, glm::vec3(0.5, 0.8f, 0.2f));
    }
}
#endif // GAME_SYSTEM_H_
