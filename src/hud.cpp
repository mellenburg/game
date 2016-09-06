// GLEW
#define GLEW_STATIC
#include <GL/glew.h>

// GLM Mathemtics
#define GLM_FORCE_RADIANS
#include <glm/glm.hpp>
#include <glm/gtc/matrix_transform.hpp>
#include <glm/gtc/type_ptr.hpp>

// My stuff
#include <vector>
#include <iostream>
#include <iomanip> //setw and setprecion
#include <sstream>

#include "shader.h"
#include "satellite.h"
#include "writer.h"
#include "line.h"
#include "hud.h"

bool solveQuadratic(const GLfloat &a, const GLfloat &b, const GLfloat &c, GLfloat &x0, GLfloat &x1)
{
    float discr = b * b - 4 * a * c;
    if (discr < 0) return false;
    else if (discr == 0) x0 = x1 = - 0.5 * b / a;
    else {
        float q = (b > 0) ?
            -0.5 * (b + sqrt(discr)) :
            -0.5 * (b - sqrt(discr));
        x0 = q / a;
        x1 = c / q;
    }
    if (x0 > x1) std::swap(x0, x1);

    return true;
}

bool intersect(glm::vec3 &start, glm::vec3 &end)
{
    GLfloat t0, t1;
    GLfloat radius2 = 40589641;
    glm::vec3 dir = end - start;
    GLfloat a = glm::dot(dir, dir);
    GLfloat b = 2 * glm::dot(dir, start);
    GLfloat c = glm::dot(start, start) - radius2;
    if (!solveQuadratic(a, b, c, t0, t1)) return false;
    if (t0>t1) std::swap(t0, t1);
    if (t0 < 0) {
        t0 = t1;
        if (t0 < 0) return false;
    }
    if (t0 > 1) return false;
    return true;
}


GameScreen::GameScreen(GLuint x, GLuint y, GLuint w, GLuint h, glm::mat4 proj): text_writer_(w, h)
{
    projection_ = proj;
    screen_dim_ = glm::vec4(x, y, w, h);
}

glm::vec3 GameScreen::ScreenPosition(glm::vec3 real_position, glm::mat4 view)
{
    glm::vec3 view_position = glm::vec3(view*glm::vec4(real_position, 1));
    return glm::project(view_position, glm::mat4(), projection_, screen_dim_);
}

void GameScreen::RenderHud(Shader shader, std::vector<Satellite>& satellites, int selected, glm::mat4 view)
{
    glm::vec3 main_position = satellites[selected].GetR();
    glm::vec3 main_velocity = satellites[selected].GetV();
    for( int i = 0; i < int(satellites.size()); i++)
    {
        if (i==selected)
        {
            continue;
        }
        glm::vec3 other_position = satellites[i].GetR();
        glm::vec3 other_velocity = satellites[i].GetV();
        Line targeting;
        shader.Use();
        if (intersect(main_position, other_position)){
            glUniform3f(glGetUniformLocation(shader.Program, "setColor"), 1.0f, 1.0f, 0.0f);
        } else {
            glUniform3f(glGetUniformLocation(shader.Program, "setColor"), 1.0f, 0.0f, 0.0f);
        }
        targeting.Update(main_position, other_position);
        targeting.Draw(shader);
        float distance = glm::distance(main_position, other_position);
        std::stringstream s;
        s<<"Distance: "<<std::fixed<<std::setprecision(0)<<distance<<" km";
        glm::vec3 tex_pos = ScreenPosition(other_position, view);
        text_writer_.RenderText(s.str(), tex_pos.x, tex_pos.y, 1.0f, glm::vec3(0.5, 0.8f, 0.2f));
        s.str("");
        float velocity = glm::distance(main_velocity, other_velocity);
        s<<"delta-V: "<<std::fixed<<std::setprecision(2)<<velocity<<" km/s";
        tex_pos = ScreenPosition(other_position, view);
        text_writer_.RenderText(s.str(), tex_pos.x, tex_pos.y-28, 1.0f, glm::vec3(0.5, 0.8f, 0.2f));
    }
}
