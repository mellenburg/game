#ifndef GAME_SATELLITE_H_
#define GAME_SATELLITE_H__
// GLEW
#define GLEW_STATIC
#include <GL/glew.h>

// GLFW
#include <GLFW/glfw3.h>

// GLM Mathemtics
#include <glm/glm.hpp>
#include <glm/gtc/matrix_transform.hpp>
#include <glm/gtc/type_ptr.hpp>

#include "orbit.h"

class Satellite {
    private:
        vec3D r_ = {-6045., -3490., 2500.};
        vec3D v_ = {-3.56, 6.618, 2.533};
        Cube cube_;
        Ellipse3d ellipse_;
    public:
        EarthOrbit orbit_;
        Satellite(glm::mat4);
        void thrustUp(int time){orbit_.goUp(time);}
        void thrustDown(int time){orbit_.goDown(time);}
        void thrustLeft(int time){orbit_.goLeft(time);}
        void thrustRight(int time){orbit_.goRight(time);}
        void thrustForward(int time){orbit_.goForward(time);}
        void thrustBackward(int time){orbit_.goBackward(time);}
        void Render(glm::mat4);
};

Satellite::Satellite(glm::mat4 proj): orbit_(r_, v_), cube_(orbit_, proj), ellipse_(orbit_, proj) {
}

void Satellite::Render(glm::mat4 view) {

    //Cube update and render
    cube_.Update(orbit_);
    cube_.Render(view);

   // Draw Orbit
    ellipse_.Update(orbit_);
    ellipse_.Render(view);
}
#endif // GAME_SATELLITE_H_
