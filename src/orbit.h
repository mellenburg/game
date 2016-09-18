#ifndef ORBIT_H
#define ORBIT_H
#define GLEW_STATIC
#include <GL/glew.h>
#define GLM_FORCE_RADIANS
#include <glm/glm.hpp>
#include <glm/gtc/matrix_transform.hpp>
#include <glm/gtc/type_ptr.hpp>

#include <cmath>

class EarthOrbit
{
    int numiter = 35;
    GLfloat rtol = 1e-10;
    GLfloat k = 398600.4415;

  public:
    void rv2coe();
    glm::vec3 r;
    glm::vec3 v;
    GLfloat r_p;
    GLfloat r_a;
    GLfloat ecc;
    GLfloat p;
    GLfloat a;
    GLfloat b;
    GLfloat inc;
    GLfloat raan;
    GLfloat argp;
    GLfloat nu;
    GLfloat period;
    EarthOrbit(glm::vec3&, glm::vec3&);
    ~EarthOrbit();
    void clone(EarthOrbit&);
    void propagate(GLfloat);
    void maneuver(glm::vec4&);
    void relative_maneuver(glm::vec3, GLfloat);
};
#endif
