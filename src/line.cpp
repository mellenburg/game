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

Line::Line(glm::mat4 projection): shader_("shaders/basic.vs", "shaders/basic.frag") {
    shader_.Use();
    glUniformMatrix4fv(glGetUniformLocation(shader_.Program, "projection"), 1, GL_FALSE, glm::value_ptr(projection));
    glGenVertexArrays(1, &VAO);
    glGenBuffers(1, &VBO);
}

void Line::Update(glm::vec3 start, glm::vec3 end) {
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

void Line::Draw(glm::vec3 color, glm::mat4 view) {
    shader_.Use();
    glUniformMatrix4fv(glGetUniformLocation(shader_.Program, "view"), 1, GL_FALSE, glm::value_ptr(view));
    glm::mat4 model3;
    glBindVertexArray(VAO);
    glUniformMatrix4fv(glGetUniformLocation(shader_.Program, "model"), 1, GL_FALSE, glm::value_ptr(model3));
    glUniform3f(glGetUniformLocation(shader_.Program, "setColor"), color.x, color.y, color.z);
    glDrawArrays(GL_LINES, 0, 2);
    glBindVertexArray(0);

}
