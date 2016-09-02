#ifndef GAME_MODEL_H_
#define GAME_MODEL_H_
// Std. Includes
#include <string>
#include <vector>
using namespace std;
// GL Includes
#include <GL/glew.h> // Contains all the necessery OpenGL includes
#define GLM_FORCE_RADIANS
#include <glm/glm.hpp>
#include <glm/gtc/matrix_transform.hpp>
#include <SOIL/SOIL.h>
#include <assimp/Importer.hpp>
#include <assimp/scene.h>
#include <assimp/postprocess.h>

#include "shader.h"
#include "mesh.h"

GLint TextureFromFile(const char*, string, bool gamma = false);

class Model
{
public:
    vector<Texture> textures_loaded;
    vector<Mesh> meshes;
    string directory;
    bool gammaCorrection;
    Model(string const & path, bool gamma = false);
    void Draw(Shader);

private:
    void loadModel(string path);
    void processNode(aiNode*, const aiScene*);
    Mesh processMesh(aiMesh*, const aiScene*);
    vector<Texture> loadMaterialTextures(aiMaterial*, aiTextureType, string);
};
#endif // GAME_MODEL_H_
