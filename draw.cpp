/*This source code copyrighted by Lazy Foo' Productions (2004-2015)
and may not be redistributed without written permission.*/

//Using SDL, SDL_image, standard IO, math, and strings
#include <SDL2/SDL.h>
#include <SDL2/SDL_image.h>
#include <SDL2/SDL2_gfxPrimitives.h>
#include <stdio.h>
#include <string>
#include <vector>
#include <math.h>
#include "orbit.h"
#include "axis.h"

#define PI 3.14159265

//Screen dimension constants
const int SCREEN_WIDTH = 600;
const int SCREEN_HEIGHT = 600;

//Starts up SDL and creates window
bool init();

//Frees media and shuts down SDL
void close();

//The window we'll be rendering to
SDL_Window* gWindow = NULL;

//The window renderer
SDL_Renderer* gRenderer = NULL;
//
//Current displayed texture
SDL_Texture* gTexture = NULL;

const double DV = .05;
const double DT = 10.0;
double angle_degrees;
short int sat_x, sat_y;

bool init()
{
	//Initialization flag
	bool success = true;

	//Initialize SDL
	if( SDL_Init( SDL_INIT_VIDEO ) < 0 )
	{
		printf( "SDL could not initialize! SDL Error: %s\n", SDL_GetError() );
		success = false;
	}
	else
	{
		//Set texture filtering to linear
		if( !SDL_SetHint( SDL_HINT_RENDER_SCALE_QUALITY, "1" ) )
		{
			printf( "Warning: Linear texture filtering not enabled!" );
		}

		//Create window
		gWindow = SDL_CreateWindow( "Oribital Simulation", SDL_WINDOWPOS_UNDEFINED, SDL_WINDOWPOS_UNDEFINED, SCREEN_WIDTH, SCREEN_HEIGHT, SDL_WINDOW_SHOWN );
		if( gWindow == NULL )
		{
			printf( "Window could not be created! SDL Error: %s\n", SDL_GetError() );
			success = false;
		}
		else
		{
			//Create renderer for window
			gRenderer = SDL_CreateRenderer( gWindow, -1, SDL_RENDERER_ACCELERATED );
			if( gRenderer == NULL )
			{
				printf( "Renderer could not be created! SDL Error: %s\n", SDL_GetError() );
				success = false;
			}
			else
			{
				//Initialize renderer color
				SDL_SetRenderDrawColor( gRenderer, 0xFF, 0xFF, 0xFF, 0xFF );

				//Initialize PNG loading
				int imgFlags = IMG_INIT_PNG;
				if( !( IMG_Init( imgFlags ) & imgFlags ) )
				{
					printf( "SDL_image could not initialize! SDL_image Error: %s\n", IMG_GetError() );
					success = false;
				}
			}
		}
	}

	return success;
}

void close()
{
	//Destroy window
	SDL_DestroyRenderer( gRenderer );
	SDL_DestroyWindow( gWindow );
	gWindow = NULL;
	gRenderer = NULL;

	//Quit SDL subsystems
	IMG_Quit();
	SDL_Quit();
}

int main( int argc, char* args[] )
{
	//Start up SDL and create window
	if( !init() )
	{
		printf( "Failed to initialize!\n" );
	}
	else
	{
            vector<double> forward = {DV, 0, 0, DT};
            vector<double> backward = {-1.0*DV, 0, 0, DT};
            vector<double> left = {0, DV, 0, DT};
            vector<double> right = {0, -1.0*DV, 0, DT};
            //vector<double> r = {6754, 0.0, 0.0};
            //vector<double> v = {0.0, 7.66, 0.0};
            vector<double> r = {-6045, -3490, 2500};
            vector<double> v = {-3.56, 6.618, 2.533};
            EarthOrbit orbit (r, v);

            Axis xAxis (50, SCREEN_WIDTH-50, -1.0*orbit.r_a, orbit.r_a);
            Axis yAxis (50, SCREEN_HEIGHT-50, -1.0*orbit.r_a, orbit.r_a);

			//Main loop flag
			bool quit = false;

			//Event handler
			SDL_Event e;

            //Point Render at off screen texture
            gTexture = SDL_CreateTexture(gRenderer, SDL_PIXELFORMAT_RGBA8888, SDL_TEXTUREACCESS_TARGET, SCREEN_WIDTH, SCREEN_HEIGHT);

			//While application is running
			while( !quit )
			{
				//Handle events on queue
				while( SDL_PollEvent( &e ) != 0 )
				{
					//User requests quit
					if( e.type == SDL_QUIT )
					{
						quit = true;
					} else if( e.type == SDL_KEYDOWN )
					{
						switch( e.key.keysym.sym )
						{
							case SDLK_UP:
                            orbit.relative_maneuver(forward);
							break;

							case SDLK_DOWN:
                            orbit.relative_maneuver(backward);
							break;

							case SDLK_LEFT:
                            orbit.relative_maneuver(left);
							break;

							case SDLK_RIGHT:
                            orbit.relative_maneuver(right);
							break;

                            case SDLK_RETURN:
                            orbit.propagate(DT);
                            break;

                            case SDLK_SPACE:
                            orbit.dump_state();
                            break;
						}
					}
				}

                SDL_SetRenderTarget(gRenderer, gTexture);
				//Clear screen
				SDL_SetRenderDrawColor( gRenderer, 0xFF, 0xFF, 0xFF, 0xFF );
				SDL_RenderClear( gRenderer );


                //Render Earth in Center
                filledCircleColor(gRenderer, xAxis.center, yAxis.center, xAxis.scale(6371.), 0xFF0000FF);
                //Render ellipse with semimajor axis parallel to X
                //Render ellipse center offset so that argp point at x->0
                aaellipseColor(gRenderer, xAxis.center+xAxis.scale(orbit.a-orbit.r_p), yAxis.center, xAxis.scale(orbit.a), yAxis.scale(orbit.b), 0xFF0000FF);

                //Find satellite position
                sat_x = xAxis.center-xAxis.scale(cos(orbit.nu)*orbit.norm_r);
                sat_y = yAxis.center+xAxis.scale(sin(orbit.nu)*orbit.norm_r);

                //Render satellite
                filledCircleColor(gRenderer, sat_x, sat_y, 20, 0xFF0000FF);

                SDL_SetRenderTarget(gRenderer, NULL);
                angle_degrees = orbit.argp*180.0/PI;
	            SDL_RenderCopyEx( gRenderer, gTexture, NULL, NULL, angle_degrees, NULL, SDL_FLIP_NONE);
				//Update screen
				SDL_RenderPresent( gRenderer );
		}
	}

	//Free resources and close SDL
	close();

	return 0;
}
