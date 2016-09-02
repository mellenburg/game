#ifndef GAME_WRITER_H_
#define GAME_WRITER_H_
#include <iostream>
#include <map>
#include <string>
// GLEW
#define GLEW_STATIC
#include <GL/glew.h>
// GLFW
#include <GLFW/glfw3.h>
// GLM
#define GLM_FORCE_RADIANS
#include <glm/glm.hpp>
#include <glm/gtc/matrix_transform.hpp>
#include <glm/gtc/type_ptr.hpp>
// GL includes
#include "shader.h"

struct Character {
    GLuint TextureID;   // ID handle of the glyph texture
    glm::ivec2 Size;    // Size of glyph
    glm::ivec2 Bearing;  // Offset from baseline to left/top of glyph
    GLuint Advance;    // Horizontal offset to advance to next glyph
 };


class FtWriter {
    private:
        Shader shader_;
        std::map<GLchar, Character> Characters;
        GLuint VAO, VBO;
    public:
        FtWriter(GLuint, GLuint);
        void RenderText(std::string, GLfloat, GLfloat, GLfloat, glm::vec3);
};

#endif // GAME_WRITER_H_
