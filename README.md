# Requirements
* SDL2, SDL2-image
* [SDL\_gfx] (http://www.ferzkopp.net/wordpress/2016/01/02/sdl_gfx-sdl2_gfx/)
* poliastro for inspiration

# V1 Objectives
* create a dynamic oribital simulation capable of supporting at least 2 satellites
* user should be able to adjust all objects with in-plan manuevers mapped to keys

# Tasks:
* DONE: Write classical orbital coefficient equations from poliastro in C++
* DONE: Implement keplerian propogation
* DONE: Implement orbital maneuvers in
* DONE: Render an ellipse derived from \<R,V\>
* DONE: Render the orbit with the planet from an inertial reference frame
* DONE: `Replace vectors with 4Dvector struct
* DONE: Use space picture for background
* DONE: Multiple colors for objects
* Split Earth, ship and orbit into unique layers
* Create viewer module that creates consistency between render layers
* Multiple controllable satellites
* Create orbit predictor
* Use icon for space ship
* Add astrodynamics tests, LOL
