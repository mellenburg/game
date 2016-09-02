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
        vec3D r_ = {-6045., -3490., 2500.};
        vec3D v_ = {-3.56, 6.618, 2.533};
        Cube cube_;
        Ellipse3d ellipse_;
    public:
        bool selected_ = false;

        EarthOrbit orbit_;
        Satellite(glm::mat4);
        void thrustUp(int time){orbit_.goUp(time);}
        void thrustDown(int time){orbit_.goDown(time);}
        void thrustLeft(int time){orbit_.goLeft(time);}
        void thrustRight(int time){orbit_.goRight(time);}
        void thrustForward(int time){orbit_.goForward(time);}
        void thrustBackward(int time){orbit_.goBackward(time);}
        void Render(glm::mat4);
        glm::vec3 GetR();
        glm::vec3 GetV();
        void Select();
        void Unselect();
};
#endif // GAME_SATELLITE_H_
