#include <iostream>
#include <math.h>

// GLEW
#define GLEW_STATIC
#include <GL/glew.h>

// GLFW
#include <GLFW/glfw3.h>

//GLM
#include <glm/glm.hpp>
#include <glm/gtc/matrix_transform.hpp>
#include <glm/gtc/type_ptr.hpp>

// Other includes
#include "shader.h"

#define PI 3.14

float inc = 0.0f;
float raan = 0.0f;
float argp = 0.0f;
void Do_Movement();

bool keys[1024];

void ellipse(int points, GLfloat out[]) {
    int j;
    GLfloat a = .4;
    GLfloat b = .90;
    float div = 2*PI/points;
    for( int i = 0; i < points; i++) {
        j = i * 3;
        out[j] = a*cos(div*float(i));
        out[j+1] = b*sin(div*float(i));
        out[j+2] = 0.0f;
    }
}

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
// Function prototypes
void key_callback(GLFWwindow* window, int key, int scancode, int action, int mode);

// Window dimensions
const GLuint WIDTH = 800, HEIGHT = 600;

// The MAIN function, from here we start the application and run the game loop
int main()
{
    // Init GLFW
    glfwInit();
    // Set all the required options for GLFW
    glfwWindowHint(GLFW_CONTEXT_VERSION_MAJOR, 3);
    glfwWindowHint(GLFW_CONTEXT_VERSION_MINOR, 3);
    glfwWindowHint(GLFW_OPENGL_PROFILE, GLFW_OPENGL_CORE_PROFILE);
    glfwWindowHint(GLFW_RESIZABLE, GL_FALSE);

    // Create a GLFWwindow object that we can use for GLFW's functions
    GLFWwindow* window = glfwCreateWindow(WIDTH, HEIGHT, "LearnOpenGL", nullptr, nullptr);
    glfwMakeContextCurrent(window);

    // Set the required callback functions
    glfwSetKeyCallback(window, key_callback);

    // Set this to true so GLEW knows to use a modern approach to retrieving function pointers and extensions
    glewExperimental = GL_TRUE;
    // Initialize GLEW to setup the OpenGL Function pointers
    glewInit();

    // Define the viewport dimensions
    glViewport(0, 0, WIDTH, HEIGHT);

    // Build and compile our shader program
    Shader ourShader("basic.vs", "basic.frag");

    /* Set up vertex data (and buffer(s)) and attribute pointers
    int pt = 1000;
    GLfloat vertices[pt*6];
    // Make the ellipse
    //ellipse(pt, vertices);
    ellipse2(pt, vertices, inc, raan, argp);
    GLuint VBO, VAO;
    glGenVertexArrays(1, &VAO);
    glGenBuffers(1, &VBO);
    // Bind the Vertex Array Object first, then bind and set vertex buffer(s) and attribute pointer(s).
    glBindVertexArray(VAO);

    glBindBuffer(GL_ARRAY_BUFFER, VBO);
    glBufferData(GL_ARRAY_BUFFER, sizeof(vertices), vertices, GL_STATIC_DRAW);

    // Position attribute
    //glVertexAttribPointer(0, 3, GL_FLOAT, GL_FALSE, 6 * sizeof(GLfloat), (GLvoid*)0);
    glVertexAttribPointer(0, 3, GL_FLOAT, GL_FALSE, 3 * sizeof(GLfloat), (GLvoid*)0);
    glEnableVertexAttribArray(0);
    // Color attribute
    //glVertexAttribPointer(1, 3, GL_FLOAT, GL_FALSE, 6 * sizeof(GLfloat), (GLvoid*)(3 * sizeof(GLfloat)));
    //glEnableVertexAttribArray(1);

    glBindVertexArray(0); // Unbind VAO
    */
    GLuint VBO, VAO;
    // Game loop
    while (!glfwWindowShouldClose(window))
    {
    int pt = 1000;
    GLfloat vertices[pt*6];
    // Make the ellipse
    //ellipse(pt, vertices);
    ellipse2(pt, vertices, inc, raan, argp);
    glGenVertexArrays(1, &VAO);
    glGenBuffers(1, &VBO);
    // Bind the Vertex Array Object first, then bind and set vertex buffer(s) and attribute pointer(s).
    glBindVertexArray(VAO);

    glBindBuffer(GL_ARRAY_BUFFER, VBO);
    glBufferData(GL_ARRAY_BUFFER, sizeof(vertices), vertices, GL_STATIC_DRAW);

    // Position attribute
    //glVertexAttribPointer(0, 3, GL_FLOAT, GL_FALSE, 6 * sizeof(GLfloat), (GLvoid*)0);
    glVertexAttribPointer(0, 3, GL_FLOAT, GL_FALSE, 3 * sizeof(GLfloat), (GLvoid*)0);
    glEnableVertexAttribArray(0);
    // Color attribute
    //glVertexAttribPointer(1, 3, GL_FLOAT, GL_FALSE, 6 * sizeof(GLfloat), (GLvoid*)(3 * sizeof(GLfloat)));
    //glEnableVertexAttribArray(1);

    glBindVertexArray(0); // Unbind VAO


        // Check if any events have been activiated (key pressed, mouse moved etc.) and call corresponding response functions
        glfwPollEvents();
        Do_Movement();
        printf("%f, %f, %f\n", inc, raan, argp);

        // Render
        // Clear the colorbuffer
        glClearColor(0.2f, 0.3f, 0.3f, 1.0f);
        glClear(GL_COLOR_BUFFER_BIT);

        // Draw the triangle
        ourShader.Use();
        glBindVertexArray(VAO);
        glm::mat4 trans;
        trans = glm::rotate(trans, 0.0f, glm::vec3(1.0, 1.0, 0.0));
        GLuint transformLoc = glGetUniformLocation(ourShader.Program, "transform");
        glUniformMatrix4fv(transformLoc, 1, GL_FALSE, glm::value_ptr(trans));
        glDrawArrays(GL_LINE_LOOP, 0, pt);
        glBindVertexArray(0);

        // Swap the screen buffers
        glfwSwapBuffers(window);
    }
    // Properly de-allocate all resources once they've outlived their purpose
    glDeleteVertexArrays(1, &VAO);
    glDeleteBuffers(1, &VBO);
    // Terminate GLFW, clearing any resources allocated by GLFW.
    glfwTerminate();
    return 0;
}

/* Is called whenever a key is pressed/released via GLFW
void key_callback(GLFWwindow* window, int key, int scancode, int action, int mode)
{
    if (key == GLFW_KEY_ESCAPE && action == GLFW_PRESS)
        glfwSetWindowShouldClose(window, GL_TRUE);
}
*/
void Do_Movement()
{
    // Camera controls
    if(keys[GLFW_KEY_W])
        raan += .5;
    if(keys[GLFW_KEY_S])
        raan -= .5;
    if(keys[GLFW_KEY_A])
        inc += .5;
    if(keys[GLFW_KEY_D])
        inc -= .5;
    if(keys[GLFW_KEY_Q])
        argp += .5;
    if(keys[GLFW_KEY_E])
        argp -= .5;
}

// Is called whenever a key is pressed/released via GLFW
void key_callback(GLFWwindow* window, int key, int scancode, int action, int mode)
{
    //cout << key << endl;
    if(key == GLFW_KEY_ESCAPE && action == GLFW_PRESS)
        glfwSetWindowShouldClose(window, GL_TRUE);

    if(action == GLFW_PRESS)
        keys[key] = true;
    else if(action == GLFW_RELEASE)
        keys[key] = false;
}


