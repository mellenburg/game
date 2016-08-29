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
#include <unistd.h>
#include <vector>
#include <iostream>
#include <math.h>
#include "orbit.h"
#include "cube.h"
#include "ellipse_3d.h"
#include "satellite.h"

#define PI 3.14
int timeFactor = 3;
int timeResolution = 5;
// Ten seconds per frame, 30
// KM/idealized area unit
float earthPhase = 0.0;
float dif = (2.0*PI/(60.0*60.0*24.0));
GLfloat scale = 6371.;
// FIXME: terrible hack to use globals

// Camera
Camera camera(glm::vec3(3.0f, 0.0f, 0.0f));
bool keys[1024];
GLfloat lastX = 400, lastY = 300;
bool firstMouse = true;

#pragma region "User input"

// Moves/alters the camera positions based on user input
// Is called whenever a key is pressed/released via GLFW
void key_callback(GLFWwindow* window, int key, int scancode, int action, int mode)
{
    if(key == GLFW_KEY_ESCAPE && action == GLFW_PRESS)
        glfwSetWindowShouldClose(window, GL_TRUE);

    if(action == GLFW_PRESS)
        keys[key] = true;
    else if(action == GLFW_RELEASE)
        keys[key] = false;
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
    //earthPhase += dif*timeFactor*timeResolution;
    earthPhase += dif*3*15;
    if( earthPhase > (2.0*PI) ) {
        earthPhase -= (2.0*PI);
    }
}

class gameSystem {
    private:
        int idx = -1;
        glm::mat4 projection;
    public:
        vector<Shader> shaderBank;
        vector<Model> modelBank;
        vector<Satellite> sBank;
        gameSystem(GLuint, GLuint);
        void processKeys(GLfloat);
        void step();
        void AddSatellite();
        void RemoveSatellite();
};

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
        sBank[idx].thrustForward(timeFactor*timeResolution);
    if(keys[GLFW_KEY_DOWN])
        sBank[idx].thrustBackward(timeFactor*timeResolution);
    if(keys[GLFW_KEY_LEFT])
        sBank[idx].thrustLeft(timeFactor*timeResolution);
    if(keys[GLFW_KEY_RIGHT])
        sBank[idx].thrustRight(timeFactor*timeResolution);
    if(keys[GLFW_KEY_PAGE_UP])
        sBank[idx].thrustUp(timeFactor*timeResolution);
    if(keys[GLFW_KEY_PAGE_DOWN])
        sBank[idx].thrustDown(timeFactor*timeResolution);
    if(keys[GLFW_KEY_Q])
        timeFactor++;
    if(keys[GLFW_KEY_E] && timeFactor>0)
        timeFactor--;
    if(keys[GLFW_KEY_F])
        this->AddSatellite();
    if(keys[GLFW_KEY_R])
        this->RemoveSatellite();

}

void gameSystem::AddSatellite(){
    Satellite mySat(projection);
    sBank.push_back(mySat);
    idx++;
}

void gameSystem::RemoveSatellite(){
    sBank.erase(sBank.begin()+idx);
    idx--;
}

gameSystem::gameSystem(GLuint screenWidth, GLuint screenHeight){

    // Define the viewport dimensions
    glViewport(0, 0, screenWidth, screenHeight);

    // Setup OpenGL options
    glEnable(GL_DEPTH_TEST);

    // Enable transparency
    glEnable (GL_BLEND);
    //glBlendFunc (GL_ONE, GL_ONE);
    glBlendFunc (GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);

    projection = glm::perspective(45.0f, (GLfloat)screenWidth/(GLfloat)screenHeight, .1f, 100.0f);

    Shader planetShader("shaders/planet.vs", "shaders/planet.frag");
    shaderBank.push_back(planetShader);
    Model planet("resources/3D/earth/earth.obj");
    modelBank.push_back(planet);
    this->shaderBank[0].Use();
    glUniformMatrix4fv(glGetUniformLocation(this->shaderBank[0].Program, "projection"), 1, GL_FALSE, glm::value_ptr(projection));
    this->AddSatellite();
}

void gameSystem::step(){
    glm::mat4 view = camera.GetViewMatrix();
    this->shaderBank[0].Use();
    glUniformMatrix4fv(glGetUniformLocation(this->shaderBank[0].Program, "view"), 1, GL_FALSE, glm::value_ptr(view));
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
    glUniformMatrix4fv(glGetUniformLocation(this->shaderBank[0].Program, "model"), 1, GL_FALSE, glm::value_ptr(model));
    modelBank[0].Draw(this->shaderBank[0]);
    updateEarthPhase();
    for (int i = 0; i<=idx; i++) {
        sBank[i].Render(view);
        sBank[i].orbit_.propagate(timeFactor*timeResolution);
    }
}
#endif // GAME_SYSTEM_H_
