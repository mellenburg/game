# Requirements
* OpenGL
* GLFW
* GLEW
* Assimp
* SOIL
* GLM

# Goals
* DONE: Make a basic orbital physics simlutation in 3D
* DONE: Refactor src/ with classes such that an arbitrary number of orbits may be added by user
* DONE: Figure out how to do transparent textures of assimp imported models
* Ship spites - sprites are harder than models... I'll just stick with cubes for simplicity for now
* add handler for press and release keys
* allow selection of a single ship, selection will cause the orbit and cube marker to change color. All other orbits will be colored homogeneously
* once an oribt is selected, draw a line from the ship to every other ship and color that line one color if the line intersects Earth or another color if it does not
* for each of the other ("targeted") ships, display distance from selected ship and relative velocity beteen the two
