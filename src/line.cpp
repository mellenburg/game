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

#include "line.h"

Line::Line()
{
    glGenVertexArrays(1, &VAO);
    glGenBuffers(1, &VBO);
}

Line::~Line()
{
    glDeleteBuffers(1, &VBO);
    glDeleteVertexArrays(1, &VAO);
}

void Line::Update(glm::vec3 start, glm::vec3 end)
{
    vertices_[0] = start.x;
    vertices_[1] = start.y;
    vertices_[2] = start.z;
    vertices_[3] = end.x;
    vertices_[4] = end.y;
    vertices_[5] = end.z;
    glBindVertexArray(VAO);
    glBindBuffer(GL_ARRAY_BUFFER, VBO);
    glBufferData(GL_ARRAY_BUFFER, sizeof(vertices_), vertices_, GL_STATIC_DRAW);
    glVertexAttribPointer(0, 3, GL_FLOAT, GL_FALSE, 3 * sizeof(GLfloat), (GLvoid*)0);
    glEnableVertexAttribArray(0);
    glBindVertexArray(0);
}

void Line::Draw(Shader shader)
{
    shader.Use();
    glBindVertexArray(VAO);
    glDrawArrays(GL_LINES, 0, 2);
    glBindVertexArray(0);

}
