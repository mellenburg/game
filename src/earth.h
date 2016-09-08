#ifndef GAME_EARTH_H_
#define GAME_EARTH_H_
// GLEW
#define GLEW_STATIC
#include <GL/glew.h>

// GLFW
#include <GLFW/glfw3.h>

// GL includes
#include "shader.h"
#include "model.h"

// GLM Mathemtics
#define GLM_FORCE_RADIANS
#include <glm/glm.hpp>
#include <glm/gtc/matrix_transform.hpp>

// My stuff
#include "writer.h"
#include "orbital_set.h"
#include "hud.h"

void key_callback(GLFWwindow*, int, int, int, int);
void mouse_callback(GLFWwindow*, double, double);

class EarthSystem
{
    private:
        bool planning_mode_ = true;
        int selected_ship_ = 0;
        glm::mat4 projection_;
        Shader line_shader_;
        Shader planet_shader_;
        Model planet_model_;
        OrbitalSet real_set_;
        OrbitalSet planning_set_;
        GLuint width_, height_;
        float earth_phase_ = 0.0;
        GameScreen game_screen_;
    public:
        EarthSystem(GLuint, GLuint);
        void processKeys(GLfloat);
        void step();
        void UpdateEarthPhase();
};
#endif // EARTH_H_
