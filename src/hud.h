#ifndef GAME_HUD_H_
#define GAME_HUD_H_
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

#include "satellite.h"
#include "writer.h"

class GameScreen
{
    private:
        glm::vec4 screen_dim_;
        FtWriter text_writer_;
    public:
        glm::mat4 projection_;
        GameScreen(GLuint, GLuint, GLuint, GLuint, glm::mat4);
        glm::vec3 ScreenPosition(glm::vec3, glm::mat4);
        void RenderHud(std::vector<Satellite>&, int, glm::mat4);
};


#endif // GAME_HUD_H_
