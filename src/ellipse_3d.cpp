// GLEW
#define GLEW_STATIC
#include <GL/glew.h>

// GLFW
#include <GLFW/glfw3.h>

// GL includes
#include "shader.h"

// GLM Mathemtics
#define GLM_FORCE_RADIANS
#include <glm/glm.hpp>
#include <glm/gtc/matrix_transform.hpp>
#include <glm/gtc/type_ptr.hpp>

#include "orbit.h"
#include "line.h"
#include "ellipse_3d.h"
#define PI 3.14159265

Ellipse3d::Ellipse3d(EarthOrbit& orbit): orbit_line_() {
    this->Update(orbit);
    glGenVertexArrays(1, &eVAO);
    glGenBuffers(1, &eVBO);
}

void Ellipse3d::SetColor(glm::vec3 color) {
    color_ = color;
}

void Ellipse3d::Update(EarthOrbit& update) {
    update.rv2coe();
    a_ = update.a;
    ecc_ = update.ecc;
    r_p_ = update.r_p;
    inc_ = update.inc;
    raan_ = update.raan;
    argp_ = update.argp;
}

void Ellipse3d::Render(Shader shader) {
    GenerateEllipse();
    glBindVertexArray(eVAO);
    glBindBuffer(GL_ARRAY_BUFFER, eVBO);
    glBufferData(GL_ARRAY_BUFFER, sizeof(vertices_), vertices_, GL_STATIC_DRAW);
    glVertexAttribPointer(0, 3, GL_FLOAT, GL_FALSE, 3 * sizeof(GLfloat), (GLvoid*)0);
    glEnableVertexAttribArray(0);
    shader.Use();
    glUniform3f(glGetUniformLocation(shader.Program, "setColor"), color_.x, color_.y, color_.z);
    glDrawArrays(GL_LINE_LOOP, 0, points_);
    glBindVertexArray(0);
    //Draw orbit line also
    orbit_line_.Update(x2_, x1_);
    orbit_line_.Draw(shader);
}

void Ellipse3d::GenerateEllipse() {
    float b = a_ * sqrt(1 - pow(ecc_, 2));
    glm::vec4 U = {a_, 0.0f, 0.0f, 1.0f};
    glm::vec4 V = {0.0f, b, 0.0f, 1.0f};
    glm::mat4 trans_argp;
    //Translate so pnet is in center
    trans_argp = glm::translate(trans_argp, glm::vec3((r_p_-a_), 0.0f, 0.0f));
    //Rotate out of plane for inclination
    glm::mat4 rot_inc;
    rot_inc = glm::rotate(rot_inc, inc_, glm::vec3(0.0f, -1.0f, 0.0f));
    //Rotate around Y axis for RAAN
    float foo;
    if( inc_ <= PI){
        foo = 1;
    } else {
        foo = -1;
    }
    glm::mat4 rot_raan;
    rot_raan = glm::rotate(rot_raan, float(raan_ + foo*(PI/2.0f)), glm::vec3(0.0f, 0.0f, 1.0f));
    // Find normal axis to current U and V to define how to rotate argp
    glm::vec3 U_t = glm::vec3(rot_raan * rot_inc * trans_argp * U);
    glm::vec3 V_t = glm::vec3(rot_raan * rot_inc * trans_argp * V);
    glm::vec3 argp_axis = glm::normalize(glm::cross(U_t, V_t));
    // Do argp rotation
    glm::mat4 rot_argp;
    rot_argp = glm::rotate(rot_argp, argp_-foo*float(PI/2.0f), argp_axis);
    // Finish transformation
    U = rot_argp * rot_raan * rot_inc * trans_argp * U;
    V = rot_argp * rot_raan * rot_inc * trans_argp * V;
    //Find displacement vector
    glm::vec3 A = a_*glm::normalize(glm::vec3(U));
    glm::vec3 delta = glm::vec3(U) - A;
    glm::vec3 B = b*glm::normalize(glm::vec3(V) - delta);
    //Finally step throuh a circle of the unit vectors and translate
    float div = 2*PI/points_;
    //Circle always starts being draw at periapsis or apoapsis
    for (int i = 0; i<points_; i++) {
        glm::vec3 res_a = glm::cos(div*float(i))*A;
        glm::vec3 res_b = glm::sin(div*float(i))*B;
        int j = i*3;
        vertices_[j] = (GLfloat) res_a.x + res_b.x + delta.x;
        vertices_[j+1] = (GLfloat) res_a.y + res_b.y + delta.y;
        vertices_[j+2] = (GLfloat) res_a.z + res_b.z + delta.z;
        if ( i == 0){
            x1_ = glm::vec3( vertices_[j], vertices_[j+1], vertices_[j+2]);
        }
        if ( i == int(points_/2)) {
            x2_ = glm::vec3( vertices_[j], vertices_[j+1], vertices_[j+2]);
        }
    }
}
