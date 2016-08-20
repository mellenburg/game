# Requirements
* SDL2, SDL2-image
* [SDL\_gfx] (http://www.ferzkopp.net/wordpress/2016/01/02/sdl_gfx-sdl2_gfx/)
* poliastro for inspiration

# V1 Objectives
* create a dynamic oribital simulation capable of supporting at least 2 satellites
* user should be able to adjust all objects with in-plan manuevers napped to keys

# Tasks:
* DONE: Write classical orbital coefficient equations from poliastro in C++
* DONE: Implement keplerian propogation
* DONE: Implement orbital maneuvers in
* Render an ellipse derived from \<R,V\>
* Render the orbit with the planet from an inertial reference frame
* Make the orbital parameters settable by user input
