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
* DONE: Split Earth, ship, and orbit into unique layers
* DONE: Create viewer module that creates consistency between render layers
* DONE: Multiple controllable satellites
* DONE: Use icon for space ship that is oriented with direction of motion
* DONE: Create orbit predictor
* DONE: Create controllable game clock
* DONE: Add a line for periapsis and apoasis
* Add label to denote which line is periapsis and which is apoasis
* Add period to info dump
* Render a tone of textual detail
* Create texture for thick ellipse
* Add astrodynamics tests, LOL

# Notes
* [Free Awesome Sprites] (http://millionthvector.blogspot.com/p/free-sprites_12.html) Thanks MillionthVector!
