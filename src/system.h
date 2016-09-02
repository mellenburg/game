#ifndef GAME_SYSTEM_H_
#define GAME_SYSTEM_H_
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
#include <vector>

#include "satellite.h"
#include "writer.h"

void key_callback(GLFWwindow*, int, int, int, int);
void mouse_callback(GLFWwindow*, double, double);

class GameSystem
{
    private:
        int selected_ship_ = 0;
        glm::mat4 projection_;
        Shader planet_shader_;
        Model planet_model_;
        FtWriter text_writer_;
        vector<Satellite> satellite_pool_;
        GLuint width_, height_;
        float earth_phase_ = 0.0;
    public:
        GameSystem(GLuint, GLuint);
        void processKeys(GLfloat);
        void step();
        void AddSatellite();
        void RemoveSatellite();
        Satellite& GetSelectedShip();
        void SelectNextShip();
        void UpdateEarthPhase();
};
#endif // GAME_SYSTEM_H_
