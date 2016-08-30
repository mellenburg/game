#ifndef GAME_ELLPISE_3D_H
#define GAME_ELLIPSE_3D_H_
// GLEW
#define GLEW_STATIC
#include <GL/glew.h>

// GLFW
#include <GLFW/glfw3.h>

// GL includes
#include "shader.h"

// GLM Mathemtics
#include <glm/glm.hpp>
#include <glm/gtc/matrix_transform.hpp>
#include <glm/gtc/type_ptr.hpp>

#include "orbit.h"
#define PI 3.14

void ellipse3(GLfloat out[], float a, float ecc, float r_p, float inc, float raan, float argp) {
    int points = 1000;
    float b = a * sqrt(1 - pow(ecc, 2));
    glm::vec4 U = {a, 0.0f, 0.0f, 1.0f};
    glm::vec4 V = {0.0f, b, 0.0f, 1.0f};
    glm::mat4 trans_argp;
    //Translate so pnet is in center
    trans_argp = glm::translate(trans_argp, glm::vec3((r_p-a), 0.0f, 0.0f));
    //Rotate out of plane for inclination
    glm::mat4 rot_inc;
    rot_inc = glm::rotate(rot_inc, inc, glm::vec3(0.0f, -1.0f, 0.0f));
    //Rotate around Y axis for RAAN
    float foo;
    if( inc <= PI){
        foo = 1;
    } else {
        foo = -1;
    }
    glm::mat4 rot_raan;
    rot_raan = glm::rotate(rot_raan, float(raan + foo*(PI/2.0f)), glm::vec3(0.0f, 0.0f, 1.0f));
    // Find normal axis to current U and V to define how to rotate argp
    glm::vec3 U_t = glm::vec3(rot_raan * rot_inc * trans_argp * U);
    glm::vec3 V_t = glm::vec3(rot_raan * rot_inc * trans_argp * V);
    glm::vec3 argp_axis = glm::normalize(glm::cross(U_t, V_t));
    // Do argp rotation
    glm::mat4 rot_argp;
    rot_argp = glm::rotate(rot_argp, argp-foo*float(PI/2.0f), argp_axis);
    // Finish transformation
    U = rot_argp * rot_raan * rot_inc * trans_argp * U;
    V = rot_argp * rot_raan * rot_inc * trans_argp * V;
    //Find displacement vector
    glm::vec3 A = a*glm::normalize(glm::vec3(U));
    glm::vec3 delta = glm::vec3(U) - A;
    glm::vec3 B = b*glm::normalize(glm::vec3(V) - delta);
    //Finally step throuh a circle of the unit vectors and translate
    float div = 2*PI/points;
    for (int i = 0; i<points; i++) {
        glm::vec3 res_a = glm::cos(div*float(i))*A;
        glm::vec3 res_b = glm::sin(div*float(i))*B;
        int j = i*3;
        out[j] = (GLfloat) res_a.x + res_b.x + delta.x;
        out[j+1] = (GLfloat) res_a.y + res_b.y + delta.y;
        out[j+2] = (GLfloat) res_a.z + res_b.z + delta.z;
    }
}

class Ellipse3d {
    private:
        Shader shader_ ;
        GLuint eVBO, eVAO;
        GLfloat vertices_[6000];
        float a, ecc, r_p, inc, raan, argp;
        GLfloat scale_ = 6371.;
    public:
        Ellipse3d(EarthOrbit&, glm::mat4);
        void Update(EarthOrbit&);
        void Render(glm::mat4);
};


Ellipse3d::Ellipse3d(EarthOrbit& orbit, glm::mat4 projection): shader_("shaders/basic.vs", "shaders/basic.frag") {
    this->Update(orbit);
    shader_.Use();
    glUniformMatrix4fv(glGetUniformLocation(shader_.Program, "projection"), 1, GL_FALSE, glm::value_ptr(projection));
    glGenVertexArrays(1, &eVAO);
    glGenBuffers(1, &eVBO);
}

void Ellipse3d::Update(EarthOrbit& update) {
    a = update.a;
    ecc = update.ecc;
    r_p = update.r_p;
    inc = update.inc;
    raan = update.raan;
    argp = update.argp;
}

void Ellipse3d::Render(glm::mat4 view) {
    GLfloat vertices[6000];
    ellipse3(vertices, a/scale_, ecc, r_p/scale_, inc, raan, argp);
    glBindVertexArray(eVAO);
    glBindBuffer(GL_ARRAY_BUFFER, eVBO);
    glBufferData(GL_ARRAY_BUFFER, sizeof(vertices), vertices, GL_STATIC_DRAW);
    glVertexAttribPointer(0, 3, GL_FLOAT, GL_FALSE, 3 * sizeof(GLfloat), (GLvoid*)0);
    glEnableVertexAttribArray(0);
    glBindVertexArray(0); // Unbind VAO
    shader_.Use();
    glUniformMatrix4fv(glGetUniformLocation(shader_.Program, "view"), 1, GL_FALSE, glm::value_ptr(view));
    glm::mat4 model2;
    glBindVertexArray(eVAO);
    glUniformMatrix4fv(glGetUniformLocation(shader_.Program, "model"), 1, GL_FALSE, glm::value_ptr(model2));
    glDrawArrays(GL_LINE_LOOP, 0, 1000);
    glBindVertexArray(0);
}
#endif // GAME_ELLIPSE_3D_H_
