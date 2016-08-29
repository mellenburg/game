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

#define PI 3.14
int timeFactor = 3;
int timeResolution = 5;
// Ten seconds per frame, 30
GLfloat scale = 6371.;
// KM/idealized area unit
float earthPhase = 0.0;
float dif = (2.0*PI/(60.0*60.0*24.0));
GLuint VBO, VAO;
GLuint eVBO, eVAO;

// FIXME: terrible hack to use globals
vec3D r = {-6045., -3490., 2500.};
vec3D v = {-3.56, 6.618, 2.533};
EarthOrbit myOrbit(r, v);

// Camera
Camera camera(glm::vec3(3.0f, 0.0f, 0.0f));
bool keys[1024];
GLfloat lastX = 400, lastY = 300;
bool firstMouse = true;

#pragma region "User input"

// Moves/alters the camera positions based on user input
void processKeys(GLfloat deltaTime)
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
        myOrbit.goForward(timeFactor*timeResolution);
    if(keys[GLFW_KEY_DOWN])
        myOrbit.goBackward(timeFactor*timeResolution);
    if(keys[GLFW_KEY_LEFT])
        myOrbit.goLeft(timeFactor*timeResolution);
    if(keys[GLFW_KEY_RIGHT])
        myOrbit.goRight(timeFactor*timeResolution);
    if(keys[GLFW_KEY_PAGE_UP])
        myOrbit.goUp(timeFactor*timeResolution);
    if(keys[GLFW_KEY_PAGE_DOWN])
        myOrbit.goDown(timeFactor*timeResolution);
    if(keys[GLFW_KEY_Q])
        timeFactor++;
    if(keys[GLFW_KEY_E] && timeFactor>0)
        timeFactor--;
}

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
void ellipse3(GLfloat out[], float a, float ecc, float r_p, float inc, float raan, float argp) {
    int points = 1000;
    float b = a * sqrt(1 - pow(ecc, 2));
    glm::vec4 U = {a, 0.0f, 0.0f, 1.0f};
    glm::vec4 V = {0.0f, b, 0.0f, 1.0f};
    glm::mat4 trans_argp;
    //Translate so pnet is in center
    trans_argp = glm::translate(trans_argp, glm::vec3((r_p-a), 0.0f, 0.0f));
    //Rotate out of plane for inclination
    glm::mat4 rot_inc;
    rot_inc = glm::rotate(rot_inc, inc, glm::vec3(0.0f, -1.0f, 0.0f));
    //Rotate around Y axis for RAAN
    float foo;
    if( inc <= PI){
        foo = 1;
    } else {
        foo = -1;
    }
    glm::mat4 rot_raan;
    rot_raan = glm::rotate(rot_raan, float(raan + foo*(PI/2.0f)), glm::vec3(0.0f, 0.0f, 1.0f));
    // Find normal axis to current U and V to define how to rotate argp
    glm::vec3 U_t = glm::vec3(rot_raan * rot_inc * trans_argp * U);
    glm::vec3 V_t = glm::vec3(rot_raan * rot_inc * trans_argp * V);
    glm::vec3 argp_axis = glm::normalize(glm::cross(U_t, V_t));
    // Do argp rotation
    glm::mat4 rot_argp;
    rot_argp = glm::rotate(rot_argp, argp-foo*float(PI/2.0f), argp_axis);
    // Finish transformation
    U = rot_argp * rot_raan * rot_inc * trans_argp * U;
    V = rot_argp * rot_raan * rot_inc * trans_argp * V;
    //Find displacement vector
    glm::vec3 A = a*glm::normalize(glm::vec3(U));
    glm::vec3 delta = glm::vec3(U) - A;
    glm::vec3 B = b*glm::normalize(glm::vec3(V) - delta);
    //Finally step throuh a circle of the unit vectors and translate
    float div = 2*PI/points;
    for (int i = 0; i<points; i++) {
        glm::vec3 res_a = glm::cos(div*float(i))*A;
        glm::vec3 res_b = glm::sin(div*float(i))*B;
        int j = i*3;
        out[j] = (GLfloat) res_a.x + res_b.x + delta.x;
        out[j+1] = (GLfloat) res_a.y + res_b.y + delta.y;
        out[j+2] = (GLfloat) res_a.z + res_b.z + delta.z;
    }
}


void updateEarthPhase()
{
    //earthPhase += dif*timeFactor*timeResolution;
    earthPhase += dif*3*15;
    if( earthPhase > (2.0*PI) ) {
        earthPhase -= (2.0*PI);
    }
}

class gameSystem {
    public:
        vector<Shader> shaderBank;
        vector<Model> modelBank;
        gameSystem(GLuint, GLuint);
        void step();
};

gameSystem::gameSystem(GLuint screenWidth, GLuint screenHeight){

    // Define the viewport dimensions
    glViewport(0, 0, screenWidth, screenHeight);

    // Setup OpenGL options
    glEnable(GL_DEPTH_TEST);

    // Enable transparency
    glEnable (GL_BLEND);
    //glBlendFunc (GL_ONE, GL_ONE);
    glBlendFunc (GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);

    // Setup and compile our shaders
    Shader planetShader("shaders/planet.vs", "shaders/planet.frag");
    shaderBank.push_back(planetShader);
    Model planet("resources/3D/earth/earth.obj");
    modelBank.push_back(planet);
    glm::mat4 projection = glm::perspective(45.0f, (GLfloat)screenWidth/(GLfloat)screenHeight, .1f, 100.0f);
    this->shaderBank[0].Use();
    glUniformMatrix4fv(glGetUniformLocation(this->shaderBank[0].Program, "projection"), 1, GL_FALSE, glm::value_ptr(projection));

    GLfloat vertices[] = {
-0.5f, -0.5f, -0.5f,  0.0f, 0.0f,
0.5f, -0.5f, -0.5f,  1.0f, 0.0f,
0.5f,  0.5f, -0.5f,  1.0f, 1.0f,
0.5f,  0.5f, -0.5f,  1.0f, 1.0f,
-0.5f,  0.5f, -0.5f,  0.0f, 1.0f,
-0.5f, -0.5f, -0.5f,  0.0f, 0.0f,

-0.5f, -0.5f,  0.5f,  0.0f, 0.0f,
0.5f, -0.5f,  0.5f,  1.0f, 0.0f,
0.5f,  0.5f,  0.5f,  1.0f, 1.0f,
0.5f,  0.5f,  0.5f,  1.0f, 1.0f,
-0.5f,  0.5f,  0.5f,  0.0f, 1.0f,
-0.5f, -0.5f,  0.5f,  0.0f, 0.0f,

-0.5f,  0.5f,  0.5f,  1.0f, 0.0f,
-0.5f,  0.5f, -0.5f,  1.0f, 1.0f,
-0.5f, -0.5f, -0.5f,  0.0f, 1.0f,
-0.5f, -0.5f, -0.5f,  0.0f, 1.0f,
-0.5f, -0.5f,  0.5f,  0.0f, 0.0f,
-0.5f,  0.5f,  0.5f,  1.0f, 0.0f,

0.5f,  0.5f,  0.5f,  1.0f, 0.0f,
0.5f,  0.5f, -0.5f,  1.0f, 1.0f,
0.5f, -0.5f, -0.5f,  0.0f, 1.0f,
0.5f, -0.5f, -0.5f,  0.0f, 1.0f,
0.5f, -0.5f,  0.5f,  0.0f, 0.0f,
0.5f,  0.5f,  0.5f,  1.0f, 0.0f,

-0.5f, -0.5f, -0.5f,  0.0f, 1.0f,
0.5f, -0.5f, -0.5f,  1.0f, 1.0f,
0.5f, -0.5f,  0.5f,  1.0f, 0.0f,
0.5f, -0.5f,  0.5f,  1.0f, 0.0f,
-0.5f, -0.5f,  0.5f,  0.0f, 0.0f,
-0.5f, -0.5f, -0.5f,  0.0f, 1.0f,

-0.5f,  0.5f, -0.5f,  0.0f, 1.0f,
0.5f,  0.5f, -0.5f,  1.0f, 1.0f,
0.5f,  0.5f,  0.5f,  1.0f, 0.0f,
0.5f,  0.5f,  0.5f,  1.0f, 0.0f,
-0.5f,  0.5f,  0.5f,  0.0f, 0.0f,
-0.5f,  0.5f, -0.5f,  0.0f, 1.0f
};
    Shader boxShader("shaders/box.vs", "shaders/box.frag");
    this->shaderBank.push_back(boxShader);
    this->shaderBank[1].Use();
    glUniformMatrix4fv(glGetUniformLocation(this->shaderBank[1].Program, "projection"), 1, GL_FALSE, glm::value_ptr(projection));
    glGenVertexArrays(1, &VAO);
    glGenBuffers(1, &VBO);
    glBindVertexArray(VAO);
    glBindBuffer(GL_ARRAY_BUFFER, VBO);
    glBufferData(GL_ARRAY_BUFFER, sizeof(vertices), vertices, GL_STATIC_DRAW);
    glVertexAttribPointer(0, 3, GL_FLOAT, GL_FALSE, 5 * sizeof(GLfloat), (GLvoid*)0);
    glEnableVertexAttribArray(0);
    glBindVertexArray(0);

    // Ellipse time
    Shader ourShader("shaders/basic.vs", "shaders/basic.frag");
    this->shaderBank.push_back(ourShader);
    this->shaderBank[2].Use();
    glUniformMatrix4fv(glGetUniformLocation(this->shaderBank[2].Program, "projection"), 1, GL_FALSE, glm::value_ptr(projection));
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

    this->shaderBank[1].Use();
    glUniformMatrix4fv(glGetUniformLocation(this->shaderBank[1].Program, "view"), 1, GL_FALSE, glm::value_ptr(view));
    glm::mat4 model3;

     model3 = glm::translate(model3, glm::vec3(myOrbit.r.i/scale, myOrbit.r.j/scale, myOrbit.r.k/scale));
    //model3 = glm::translate(model3, glm::vec3(-6045/scaley, -3940/scaley, 2500./scaley));
    //model3 = glm::scale(model3, glm::vec3(1.1547f, 1.1547f, 1.1547f)); // unit-earth-radius reference box
    model3 = glm::scale(model3, glm::vec3(.05f, .05f, .05f));
    glBindVertexArray(VAO);
    glUniformMatrix4fv(glGetUniformLocation(this->shaderBank[1].Program, "model"), 1, GL_FALSE, glm::value_ptr(model3));
    glDrawArrays(GL_TRIANGLES, 0, 36);
    glBindVertexArray(0);
    // Draw Orbit
    GLfloat vertices[6000];
    ellipse3(vertices, myOrbit.a/scale, myOrbit.ecc, myOrbit.r_p/scale, myOrbit.inc, myOrbit.raan, myOrbit.argp);
    glGenVertexArrays(1, &eVAO);
    glGenBuffers(1, &eVBO);
    glBindVertexArray(eVAO);
    glBindBuffer(GL_ARRAY_BUFFER, eVBO);
    glBufferData(GL_ARRAY_BUFFER, sizeof(vertices), vertices, GL_STATIC_DRAW);
    glVertexAttribPointer(0, 3, GL_FLOAT, GL_FALSE, 3 * sizeof(GLfloat), (GLvoid*)0);
    glEnableVertexAttribArray(0);
    glBindVertexArray(0); // Unbind VAO
    this->shaderBank[2].Use();
    glUniformMatrix4fv(glGetUniformLocation(this->shaderBank[2].Program, "view"), 1, GL_FALSE, glm::value_ptr(view));
    glm::mat4 model2;
    glBindVertexArray(eVAO);
    glUniformMatrix4fv(glGetUniformLocation(this->shaderBank[2].Program, "model"), 1, GL_FALSE, glm::value_ptr(model2));
    glDrawArrays(GL_LINE_LOOP, 0, 1000);
    glBindVertexArray(0);

    //move everything around
    myOrbit.propagate(timeFactor*timeResolution);
}
