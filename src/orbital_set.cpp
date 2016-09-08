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
#include "orbital_set.h"

OrbitalSet::OrbitalSet()
{
}

void OrbitalSet::Clone(OrbitalSet& input_set)
{
    satellites_ = input_set.satellites_;
    selected_ship_ = input_set.selected_ship_;
    GetSelectedShip().Select();
}

Satellite& OrbitalSet::GetSelectedShip()
{
    return satellites_[selected_ship_];
}

void OrbitalSet::SelectNextShip()
{
    GetSelectedShip().Unselect();
    if( (selected_ship_ + 1) == (int) satellites_.size()) {
        selected_ship_ = 0;
    } else {
        selected_ship_++;
    }
    GetSelectedShip().Select();
}

void OrbitalSet::AddSatellite()
{
    Satellite mySat;
    satellites_.push_back(mySat);
    GetSelectedShip().Unselect();
    selected_ship_ = satellites_.size()-1;
    GetSelectedShip().Select();
}

void OrbitalSet::RemoveSatellite()
{
    if( satellites_.size() > 0 ) {
        satellites_.erase(satellites_.begin()+selected_ship_);
        this->selected_ship_ = 0;
        GetSelectedShip().Select();
    }
}

void OrbitalSet::Render(Shader shader, bool planning_mode)
{
    shader.Use();
    for (int i = 0; i<int(satellites_.size()); i++)
    {
        bool sat_only = planning_mode && i!=selected_ship_;
        satellites_[i].Render(shader, sat_only);
    }
}

void OrbitalSet::Advance(float delta_time)
{
    for (int i = 0; i<int(satellites_.size()); i++)
    {
        satellites_[i].AdvanceTime(delta_time);
    }
}
