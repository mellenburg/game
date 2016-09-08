# Requirements
* OpenGL
* GLFW
* GLEW
* Assimp
* SOIL
* GLM
* FreeType

# Goals
* DONE: Make a basic orbital physics simlutation in 3D
* DONE: Refactor src/ with classes such that an arbitrary number of orbits may be added by user
* DONE: Figure out how to do transparent textures of assimp imported models
* Ship spites - sprites are harder than models... I'll just stick with cubes for simplicity for now
* DONE: allow selection of a single ship, selection will cause the orbit and cube marker to change color. All other orbits will be colored homogeneously
* Fix infinite loop hang in tgammma function during orbit calculation
* add handler for press and release keys
* once an oribt is selected, draw a line from the ship to every other ship and color that line one color if the line intersects Earth or another color if it does not
* DONE: for each of the other ("targeted") ships, display distance from selected ship and relative velocity beteen the two
* DONE: Consistently tick time. E.G. if a ship moves in a time period, don't propogate it
* create interface for calculated application of thrust. I.E. 0: display pitch, yaw, DV, DT 1: define unit vector of thrust 2: define delta V of thrust 3. define duration 4. execute
* Refactor orbit.cpp such that every orbital param is only derived once per R-V. Then an arbitrary number of calls will not repeat calculations
* Create object for the orbital system such that I can clone the current set of orbits and selectively display elements of that set propogated at the same time as "reality"
* create a planning mode where I can queue up a number of orbital maneuvers and see what their affect would be from the current orbital position
* refactor camera to snap to locations
* refactor camera to provide only pitch/yaw in a view
* add galactic plane mapped to sphere for background
* different color/style for projection data
* make time resolution a part of orbit.cpp so that way predicted orbits are not glaringly inaccurate

# Gameplay Ideas
* Model gamplay on [Ogre](http://www.sjgames.com/ogre/). E.G. Asymmetrical unit distribution pitting dozens of smaller, more nimble units vs one giant behemoth.
* Use kinetic weapons:
1. By radically adjusting your foes momentum, you will force them to expend fuel to make up the delta V and rectify their flight path
2. By using the weapon offensively, your own unit will have it's momentum changed an equal amount, so depending on the direction of the target and the position of your ship in orbit, firing can be potentially disasterous or advantageous.
