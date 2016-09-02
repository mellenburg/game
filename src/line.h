#ifndef GAME_LINE_H_
#define GAME_LINE_H_
// GLEW
#define GLEW_STATIC
#include <GL/glew.h>

// GL includes
#include "shader.h"

// GLM Mathemtics
#define GLM_FORCE_RADIANS
#include <glm/glm.hpp>
#include <glm/gtc/matrix_transform.hpp>
#include <glm/gtc/type_ptr.hpp>


class Line {
    private:
        Shader shader_ ;
        GLuint VBO, VAO;
        GLfloat vertices_[6];
    public:
        Line(glm::mat4);
        void Draw(glm::vec3, glm::mat4);
        void Update(glm::vec3, glm::vec3);
};
#endif // GAME_LINE_H
