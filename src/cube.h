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
        Shader shader_ ;
        GLuint VBO, VAO;
        glm::vec3 position_;
        glm::vec3 color_;
    public:
        Cube(EarthOrbit&, glm::mat4);
        void Update(EarthOrbit&);
        void Render(glm::mat4);
        void SetColor(glm::vec3);
};
#endif //GAME_CUBE_H_
