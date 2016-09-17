#ifndef GAME_SATELLITE_H_
#define GAME_SATELLITE_H_
// GLEW
#define GLEW_STATIC
#include <GL/glew.h>

// GLFW
#include <GLFW/glfw3.h>

// GLM Mathemtics
#define GLM_FORCE_RADIANS
#include <glm/glm.hpp>
#include <glm/gtc/matrix_transform.hpp>
#include <glm/gtc/type_ptr.hpp>

#include "cube.h"
#include "ellipse_3d.h"
#include "orbit.h"

class Satellite {
    private:
        //glm::vec3 r_ = {-6045., -3490., 2500.};
        //glm::vec3 v_ = {-3.56, 6.618, 2.533};
        // Geosynchronous Orbit?
        glm::vec3 r_ = {42164., 0., 0.};
        glm::vec3 v_ = {0, 3.0646981, 0.};
        Cube cube_;
        Ellipse3d ellipse_;
        bool did_maneuver_;
        glm::vec3 raw_current_maneuver_ = {0.0f, 0.0f, 0.0f};
    public:
        Satellite();
        glm::vec3 GetCurrentManeuver();
        void AdvanceTime(GLfloat);
        void AdjustManeuver(glm::vec3);
        void SetManeuver(glm::vec3);
        GLfloat delta_v_ = .050f;
        bool selected_ = false;
        EarthOrbit orbit_;
        void Render(Shader, bool);
        glm::vec3 GetR();
        glm::vec3 GetV();
        void Select();
        void Unselect();
};
#endif // GAME_SATELLITE_H_
