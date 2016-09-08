#ifndef GAME_ORBITAL_SET_H_
#define GAME_ORBITAL_SET_H_
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

// My stuff
#include <vector>

#include "satellite.h"

class OrbitalSet
{
    public:
        std::vector<Satellite> satellites_;
        int selected_ship_ = 0;
        OrbitalSet();
        Satellite& GetSelectedShip();
        void SelectNextShip();
        void Clone(OrbitalSet&);
        void AddSatellite();
        void RemoveSatellite();
        void Render(Shader, bool);
        void Advance(float);
};
#endif // GAME_ORBITAL_SET_H_
