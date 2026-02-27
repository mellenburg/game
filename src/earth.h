#ifndef GAME_EARTH_H_
#define GAME_EARTH_H_
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

// My stuff
#include "writer.h"
#include "orbital_set.h"
#include "hud.h"

class EarthSystem
{
    public:
        static constexpr float kEarthRadius = 6371.0f;
        static constexpr float kTimeResolution = 1.0f / 30.0f;

        EarthSystem(GLFWwindow* window, GLuint width, GLuint height);
        void processKeys(GLfloat deltaTime);
        void step();

        void HandleKey(int key, int action);
        void HandleMouseMove(double xpos, double ypos);

    private:
        void UpdateEarthPhase();

        GLFWwindow* window_;
        Camera camera_;
        bool keys_[1024] = {};
        bool was_pressed_[1024] = {};
        GLfloat last_x_ = 400.0f, last_y_ = 300.0f;
        bool first_mouse_ = true;
        int time_factor_ = 500;
        int dt_ = 0;
        bool planning_mode_ = false;
        glm::vec3 planning_maneuver_ = {0.0f, 0.0f, 0.0f};

        glm::mat4 projection_;
        Shader planet_shader_;
        Model planet_model_;
        OrbitalSet real_set_;
        OrbitalSet planning_set_;
        GLuint width_, height_;
        float earth_phase_ = 0.0;
        GameScreen game_screen_;
        Shader line_shader_;
};
#endif // EARTH_H_
