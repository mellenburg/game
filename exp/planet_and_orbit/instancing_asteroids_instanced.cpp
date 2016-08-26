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

#define PI 3.14

float inc = 0.0f;
float raan = 0.0f;
float argp = 0.0f;
void ellipse2(int points, GLfloat out[], float inc, float raan, float argp) {
    glm::vec4 U = {.9f, .0f, 0.0f, 0.0f};
    glm::vec4 V = {.0f, .4f, 0.0f, 0.0f};
    glm::mat4 trans;
    trans = glm::rotate(trans, inc, glm::vec3(0.0f, 1.0f, 0.0f));
    trans = glm::rotate(trans, raan, glm::vec3(0.0f, 0.0f, 1.0f));
    glm::vec4 U_t = trans * U;
    glm::vec4 V_t = trans * V;
    glm::vec3 U_tt = {U_t.x, U_t.y, U_t.z};
    glm::vec3 V_tt = {V_t.x, V_t.y, V_t.z};
    glm::vec3 argp_axis = glm::cross(U_tt, V_tt);
    trans = glm::rotate(trans, argp, glm::vec3(argp_axis.x, argp_axis.y, argp_axis.z));
    U = U * trans;
    V = V * trans;
    float div = 2*PI/points;
    for (int i = 0; i<points; i++) {
        glm::vec4 res_a = glm::cos(div*float(i))*U;
        glm::vec4 res_b = glm::sin(div*float(i))*V;
        int j = i*3;
        out[j] = (GLfloat) res_a.x + res_b.x;
        out[j+1] = (GLfloat) res_a.y + res_b.y;
        out[j+2] = (GLfloat) res_a.z + res_b.z;
    }
}
// Properties
GLuint screenWidth = 800, screenHeight = 600;

// Function prototypes
void key_callback(GLFWwindow* window, int key, int scancode, int action, int mode);
void mouse_callback(GLFWwindow* window, double xpos, double ypos);
void Do_Movement();

// Camera
Camera camera(glm::vec3(0.0f, 0.0f, 10.0f));
bool keys[1024];
GLfloat lastX = 400, lastY = 300;
bool firstMouse = true;

GLfloat deltaTime = 0.0f;
GLfloat lastFrame = 0.0f;

// The MAIN function, from here we start our application and run our Game loop
int main()
{
    // Init GLFW
    glfwInit();
    glfwWindowHint(GLFW_CONTEXT_VERSION_MAJOR, 3);
    glfwWindowHint(GLFW_CONTEXT_VERSION_MINOR, 3);
    glfwWindowHint(GLFW_OPENGL_PROFILE, GLFW_OPENGL_CORE_PROFILE);
    glfwWindowHint(GLFW_RESIZABLE, GL_FALSE);

    GLFWwindow* window = glfwCreateWindow(screenWidth, screenHeight, "LearnOpenGL", nullptr, nullptr); // Windowed
    glfwMakeContextCurrent(window);

    // Set the required callback functions
    glfwSetKeyCallback(window, key_callback);
    glfwSetCursorPosCallback(window, mouse_callback);

    // Options
    glfwSetInputMode(window, GLFW_CURSOR, GLFW_CURSOR_DISABLED);

    // Initialize GLEW to setup the OpenGL Function pointers
    glewExperimental = GL_TRUE;
    glewInit();

    // Define the viewport dimensions
    glViewport(0, 0, screenWidth, screenHeight);

    // Setup OpenGL options
    glEnable(GL_DEPTH_TEST);

    // Setup and compile our shaders
    Shader planetShader("planet.vs", "planet.frag");

    // Load models
    Model planet("planet/planet.obj");

    // Set projection matrix
    glm::mat4 projection = glm::perspective(45.0f, (GLfloat)screenWidth/(GLfloat)screenHeight, .1f, 100.0f);
    //glm::mat4 projection = glm::perspective(45.0f, (GLfloat)screenWidth/(GLfloat)screenHeight, .1f, 100.0f);
    planetShader.Use();
    glUniformMatrix4fv(glGetUniformLocation(planetShader.Program, "projection"), 1, GL_FALSE, glm::value_ptr(projection));

    // Ellipse time
    Shader ourShader("basic.vs", "basic.frag");
    ourShader.Use();
    glUniformMatrix4fv(glGetUniformLocation(ourShader.Program, "projection"), 1, GL_FALSE, glm::value_ptr(projection));
    GLuint VBO, VAO;
    // Game loop
    while(!glfwWindowShouldClose(window))
    {
        int pt = 1000;
        GLfloat vertices[pt*6];
        ellipse2(pt, vertices, inc, raan, argp);
        glGenVertexArrays(1, &VAO);
        glGenBuffers(1, &VBO);
        glBindVertexArray(VAO);
        glBindBuffer(GL_ARRAY_BUFFER, VBO);
        glBufferData(GL_ARRAY_BUFFER, sizeof(vertices), vertices, GL_STATIC_DRAW);
        glVertexAttribPointer(0, 3, GL_FLOAT, GL_FALSE, 3 * sizeof(GLfloat), (GLvoid*)0);
        glEnableVertexAttribArray(0);
        glBindVertexArray(0); // Unbind VAO
        // Set frame time
        GLfloat currentFrame = glfwGetTime();
        deltaTime = currentFrame - lastFrame;
        lastFrame = currentFrame;

        // Check and call events
        glfwPollEvents();
        Do_Movement();

        // Clear buffers
        glClearColor(0.03f, 0.03f, 0.03f, 1.0f);
        glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);

        // Add transformation matrices
        planetShader.Use();
        glUniformMatrix4fv(glGetUniformLocation(planetShader.Program, "view"), 1, GL_FALSE, glm::value_ptr(camera.GetViewMatrix()));
        ourShader.Use();
        glUniformMatrix4fv(glGetUniformLocation(ourShader.Program, "view"), 1, GL_FALSE, glm::value_ptr(camera.GetViewMatrix()));

        // Draw Planet
        planetShader.Use();
        glm::mat4 model;
        model = glm::translate(model, glm::vec3(0.0f, -.50f, 0.0f));
        model = glm::scale(model, glm::vec3(.50f, .50f, .50f));
        glUniformMatrix4fv(glGetUniformLocation(planetShader.Program, "model"), 1, GL_FALSE, glm::value_ptr(model));
        planet.Draw(planetShader);

        // Draw Orbit
        ourShader.Use();
        glm::mat4 model2;
        model2 = glm::scale(model2, glm::vec3(4.0f, 4.0f, 4.0f));
        glBindVertexArray(VAO);
        glUniformMatrix4fv(glGetUniformLocation(ourShader.Program, "model"), 1, GL_FALSE, glm::value_ptr(model2));
        glDrawArrays(GL_LINE_LOOP, 0, pt);
        glBindVertexArray(0);


        // reset our texture binding
        glActiveTexture(GL_TEXTURE0);
        glBindTexture(GL_TEXTURE_2D, 0);

        // Swap the buffers
        glfwSwapBuffers(window);
    }

    glfwTerminate();
    return 0;
}

#pragma region "User input"

// Moves/alters the camera positions based on user input
void Do_Movement()
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
        raan += .5;
    if(keys[GLFW_KEY_DOWN])
        raan -= .5;
    if(keys[GLFW_KEY_LEFT])
        inc += .5;
    if(keys[GLFW_KEY_RIGHT])
        inc -= .5;
    if(keys[GLFW_KEY_PAGE_UP])
        argp += .5;
    if(keys[GLFW_KEY_PAGE_DOWN])
        argp -= .5;

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
