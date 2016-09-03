#ifndef GAME_CUBE_H_
#define GAME_CUBE_H_
// GLEW
#define GLEW_STATIC
#include <GL/glew.h>

// GL includes
#include "shader.h"

// GLM Mathemtics
#define GLM_FORCE_RADIANS
#include <glm/glm.hpp>
#include <glm/gtc/matrix_transform.hpp>

#include "orbit.h"

class Cube {
    private:
        GLfloat vertices_[180];
        GLfloat ideal_vertices_[180] = {
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

        GLuint VBO, VAO;
        glm::vec3 position_;
        glm::vec3 color_;
    public:
        Cube(EarthOrbit&);
        void Update(EarthOrbit&);
        void Render(Shader);
        void SetColor(glm::vec3);
};
#endif //GAME_CUBE_H_
