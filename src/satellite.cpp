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

#include "orbit.h"
#include "satellite.h"

Satellite::Satellite(): orbit_(r_, v_), cube_(orbit_), ellipse_(orbit_) {
}

void Satellite::Render(Shader shader) {

    if(selected_) {
        cube_.SetColor(glm::vec3(0.0f, 1.0f, 0.0f));
        ellipse_.SetColor(glm::vec3(0.0f, 1.0f, 0.0f));
    } else {
        cube_.SetColor(glm::vec3(0.0f, 0.0f, 1.0f));
        ellipse_.SetColor(glm::vec3(0.0f, 0.0f, 1.0f));
    }
    //Cube update and render
    cube_.Update(orbit_);
    cube_.Render(shader);

    // Draw Orbit
    ellipse_.Update(orbit_);
    ellipse_.Render(shader);
}

void Satellite::AdjustManeuver(glm::vec3 input_maneuver)
{
    raw_current_maneuver_ = raw_current_maneuver_ + input_maneuver;
}

void Satellite::SetManeuver(glm::vec3 input_maneuver)
{
    did_maneuver_ = true;
    raw_current_maneuver_ = input_maneuver;
}

glm::vec3 Satellite::GetCurrentManeuver()
{
    return delta_v_*glm::normalize(raw_current_maneuver_);
}

void Satellite::Select() {
    this->selected_ = true;
}

void Satellite::Unselect() {
    this->selected_ = false;
}

glm::vec3 Satellite::GetR() {
    return glm::vec3(orbit_.r.i, orbit_.r.j, orbit_.r.k);
}

glm::vec3 Satellite::GetV() {
    return glm::vec3(orbit_.v.i, orbit_.v.j, orbit_.v.k);
}

void Satellite::AdvanceTime(GLfloat delta_time)
{
    if (did_maneuver_ && glm::length(raw_current_maneuver_) == 0.0f)
    {
        did_maneuver_ = false;
    }
    if (did_maneuver_)
    {
        orbit_.relative_maneuver(GetCurrentManeuver(), (double) delta_time);
    } else {
        orbit_.propagate(delta_time);
    }
    // Reset
    did_maneuver_ = false;
}
