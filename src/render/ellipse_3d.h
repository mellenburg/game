#ifndef GAME_ELLIPSE_3D_H_
#define GAME_ELLIPSE_3D_H_
// GLEW
#define GLEW_STATIC
#include <GL/glew.h>

// GLFW
#include <GLFW/glfw3.h>

// GL includes
#include "render/shader.h"

// GLM Mathemtics
#define GLM_FORCE_RADIANS
#include <glm/glm.hpp>
#include <glm/gtc/matrix_transform.hpp>
#include <glm/gtc/type_ptr.hpp>

#include "sim/orbit.h"
#include "render/line.h"
#define PI 3.14159265

class Ellipse3d {
    private:
        int points_ = 1000;
        GLfloat vertices_[3000];
        GLuint eVBO, eVAO;
        float a_, ecc_, r_p_, inc_, raan_, argp_;
        // periapsis and apoasis
        glm::vec3 x1_, x2_;
        Line orbit_line_;
        void GenerateEllipse(float, float, float, float, float, float);
        glm::vec3 color_ = {0.0f, 1.0f, 0.0f};
    public:
        Ellipse3d(const EarthOrbit&);
        ~Ellipse3d();
        Ellipse3d(const Ellipse3d&) = delete;
        Ellipse3d& operator=(const Ellipse3d&) = delete;
        void Update(const EarthOrbit&);
        void Render(Shader);
        void SetColor(glm::vec3);
};
#endif // GAME_ELLIPSE_3D_H_
