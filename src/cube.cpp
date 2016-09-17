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

#include "orbit.h"
#include "cube.h"

void Cube::SetColor(glm::vec3 color)
{
    color_ = color;
}

void Cube::Update(EarthOrbit& orbit)
{
    position_ = orbit.r;
}

Cube::Cube(EarthOrbit& orbit)
{
    this->Update(orbit);
    glGenVertexArrays(1, &VAO);
    glGenBuffers(1, &VBO);
}

void Cube::Render(Shader shader) {
    GLfloat scale = 100.f;
    for (int i = 0; i < 36; i++) {
        int j = i*5;
        vertices_[j] = (scale*ideal_vertices_[j])+position_.x;
        vertices_[j+1] = (scale*ideal_vertices_[j+1])+position_.y;
        vertices_[j+2] = (scale*ideal_vertices_[j+2])+position_.z;
        vertices_[j+3] = ideal_vertices_[j+3];
        vertices_[j+4] = ideal_vertices_[j+4];
    }
    glBindVertexArray(VAO);
    glBindBuffer(GL_ARRAY_BUFFER, VBO);
    glBufferData(GL_ARRAY_BUFFER, sizeof(vertices_), vertices_, GL_STATIC_DRAW);
    glVertexAttribPointer(0, 3, GL_FLOAT, GL_FALSE, 5 * sizeof(GLfloat), (GLvoid*)0);
    glEnableVertexAttribArray(0);
    shader.Use();
    glUniform3f(glGetUniformLocation(shader.Program, "setColor"), color_.x, color_.y, color_.z);
    glDrawArrays(GL_TRIANGLES, 0, 36);
    glBindVertexArray(0);
}
