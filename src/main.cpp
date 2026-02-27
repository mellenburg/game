// Always have this before any import that could grab GLM
#define GLM_FORCE_RADIANS
// GLEW
#define GLEW_STATIC
#include <GL/glew.h>

// GLFW
#include <GLFW/glfw3.h>

// My stuff
//
#include <unistd.h>
#include "earth.h"

#define FPS 30

GLfloat deltaTime = 0.0f;
GLfloat lastFrame = 0.0f;

// Properties
GLuint screenWidth = 1200, screenHeight = 1000;

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

    // Enable vsync - critical for stable rendering under llvmpipe/Crostini
    glfwSwapInterval(1);

    //Init Module
    EarthSystem my_earth(screenWidth, screenHeight);

    // Game loop
    while(!glfwWindowShouldClose(window))
    {
        // Set frame time
        GLfloat currentFrame = glfwGetTime();
        deltaTime = currentFrame - lastFrame;
        lastFrame = currentFrame;

        //printf("%f\n", deltaTime);
        if(deltaTime < 1.0f/FPS){
            unsigned int t = (unsigned int)(1000000*(1.0f/FPS - deltaTime));
            usleep(t);
        }

        // Check and call events
        glfwPollEvents();
        my_earth.processKeys(deltaTime);

        // Clear buffers
        glClearColor(0.03f, 0.03f, 0.03f, 1.0f);
        glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);

        my_earth.step();

        // reset our texture binding
        glActiveTexture(GL_TEXTURE0);
        glBindTexture(GL_TEXTURE_2D, 0);

        // Ensure rendering is complete before swapping (helps with software renderers)
        glFinish();

        // Swap the buffers
        glfwSwapBuffers(window);
    }

    glfwTerminate();
    return 0;
}
