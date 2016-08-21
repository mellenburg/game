/*This source code copyrighted by Lazy Foo' Productions (2004-2015)
and may not be redistributed without written permission.*/

//Using SDL, SDL_image, standard IO, math, and strings
#include <SDL2/SDL.h>
#include <SDL2/SDL_image.h>
#include <SDL2/SDL2_gfxPrimitives.h>
#include <stdio.h>
#include <string>
#include <math.h>
#include "orbit.h"

#define PI 3.14159265

//Screen dimension constants
const int SCREEN_WIDTH = 800;
const int SCREEN_HEIGHT = 800;

double DV = .05;
double DT = 10.0;

//Starts up SDL and creates window
bool init();

//Frees media and shuts down SDL
void close();

//The window we'll be rendering to
SDL_Window* gWindow = NULL;

//The window renderer
SDL_Renderer* gRenderer = NULL;

class Background {
    public:
        Background();
        ~Background();
        void render();
	private:
		SDL_Texture* mTexture;
};


Background::Background()
{
    //mTexture = SDL_CreateTexture(gRenderer, SDL_PIXELFORMAT_RGBA8888, SDL_TEXTUREACCESS_TARGET, SCREEN_WIDTH, SCREEN_HEIGHT);
    //The final texture
	SDL_Texture* newTexture = NULL;

    std::string path = "bg.bmp";
	//Load image at specified path
	SDL_Surface* loadedSurface = SDL_LoadBMP( path.c_str() );
	if( loadedSurface == NULL )
	{
		printf( "Unable to load image %s! SDL_image Error: %s\n", path.c_str(), IMG_GetError() );
	}
	else
	{
		//Create texture from surface pixels
        newTexture = SDL_CreateTextureFromSurface( gRenderer, loadedSurface );
		if( newTexture == NULL )
		{
			printf( "Unable to create texture from %s! SDL Error: %s\n", path.c_str(), SDL_GetError() );
		}
		//Get rid of old loaded surface
		SDL_FreeSurface( loadedSurface );
	}

	//Return success
	mTexture = newTexture;
}

Background::~Background()
{
    //Free texture if it exists
	if( mTexture != NULL )
	{
		SDL_DestroyTexture( mTexture );
		mTexture = NULL;
	}
}

void Background::render(){
    SDL_SetRenderTarget(gRenderer, mTexture);
    SDL_SetRenderDrawColor( gRenderer, 0x00, 0x00, 0x00, 0xFF );
    SDL_RenderClear( gRenderer );
    SDL_RenderCopy( gRenderer, mTexture, NULL, NULL);
}

class OrbitTexture {
    private:
        short int viewStartX = 50;
        short int viewStartY = 50;
        short int viewEndX = SCREEN_WIDTH-50;
        short int viewEndY = SCREEN_HEIGHT-50;
        short int viewXLength = viewEndX - viewStartX;
        short int viewYLength = viewEndY - viewStartY;
        short int centerX = (viewXLength/2) + viewStartX;
        short int centerY = (viewYLength/2) + viewStartY;
		SDL_Texture* mTexture;
        double angle_degrees;
        short int sat_x, sat_y;
        double xLow, xHigh, yLow, yHigh, xRange, yRange;
    public:
        EarthOrbit* mOrbit;
        OrbitTexture();
        ~OrbitTexture();
        short int scaleX(double);
        short int scaleY(double);
        void render();
        void setViewRange();
};

OrbitTexture mainOrbit;

short int OrbitTexture::scaleX(double x){
    return (short int)(x/xRange*double(viewXLength));
}

short int OrbitTexture::scaleY(double x){
    return (short int)(x/yRange*double(viewYLength));
}

void OrbitTexture::setViewRange(){
    xLow = -1.0*mOrbit->r_a;
    xHigh = mOrbit->r_a;
    yLow = -1.0*mOrbit->r_a;
    yHigh = mOrbit->r_a;
    xRange = xHigh - xLow;
    yRange = yHigh - yLow;
}

OrbitTexture::OrbitTexture()
{
   mTexture = SDL_CreateTexture(gRenderer, SDL_PIXELFORMAT_RGBA8888, SDL_TEXTUREACCESS_TARGET, SCREEN_WIDTH, SCREEN_HEIGHT);
   vec3D r = {-6045, -3490, 2500};
   vec3D v = {-3.56, 6.618, 2.533};
   mOrbit = new EarthOrbit(r, v);
   setViewRange();
}

OrbitTexture::~OrbitTexture()
{
    //Free texture if it exists
	if( mTexture != NULL )
	{
		SDL_DestroyTexture( mTexture );
		mTexture = NULL;
	}
    free(mOrbit);
}

void OrbitTexture::render(){
    SDL_SetRenderTarget(gRenderer, mTexture);
	//SDL_SetRenderDrawColor( gRenderer, 0xFF, 0x00, 0x00, 0xFF );
	//SDL_RenderClear( gRenderer );

    //Render Earth in Center
    filledCircleRGBA(gRenderer, centerX, centerY, scaleX(6371.), 0x00, 0x00, 0xFF, 0xFF);
    //Render ellipse with semimajor axis parallel to X
    //Render ellipse center offset so that argp point at x->0
    aaellipseRGBA(gRenderer, centerX+scaleX(mOrbit->a-mOrbit->r_p), centerY, scaleX(mOrbit->a), scaleY(mOrbit->b), 0xFF, 0xFF, 0xFF, 0xFF);

    //Find satellite position
    sat_x = centerX-scaleX(cos(mOrbit->nu)*mOrbit->norm_r);
    sat_y = centerY+scaleY(sin(mOrbit->nu)*mOrbit->norm_r);

    //Render satellite
    filledCircleRGBA(gRenderer, sat_x, sat_y, 20, 0x00, 0xFF, 0x00, 0xFF);

    SDL_SetRenderTarget(gRenderer, NULL);
    angle_degrees = mOrbit->argp*180.0/PI;
    SDL_RenderCopyEx( gRenderer, mTexture, NULL, NULL, angle_degrees, NULL, SDL_FLIP_NONE);
}

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

            Background bg;
            vec4D forward = {DV, 0, 0, DT};
            vec4D backward = {-1.0*DV, 0, 0, DT};
            vec4D left = {0, DV, 0, DT};
            vec4D right = {0, -1.0*DV, 0, DT};

			//Main loop flag
			bool quit = false;

			//Event handler
			SDL_Event e;

            bool planningMode = false;
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
                            mainOrbit.mOrbit->relative_maneuver(forward);
							break;

							case SDLK_DOWN:
                            mainOrbit.mOrbit->relative_maneuver(backward);
							break;

							case SDLK_LEFT:
                            mainOrbit.mOrbit->relative_maneuver(left);
							break;

							case SDLK_RIGHT:
                            mainOrbit.mOrbit->relative_maneuver(right);
							break;

							case SDLK_p:
                            if(planningMode){
                                planningMode = false;
                            } else {
                                planningMode = true;
                            }
							break;

                            case SDLK_RETURN:
                            mainOrbit.mOrbit->propagate(DT);
                            break;

                            case SDLK_RSHIFT:
                            mainOrbit.mOrbit->propagate(50*DT);
                            break;

                            case SDLK_SPACE:
                            mainOrbit.mOrbit->dump_state();
                            break;
						}

                    mainOrbit.setViewRange();
                    }
				}

                bg.render();
                mainOrbit.render();
                //Update screen
				SDL_RenderPresent( gRenderer );
		}
	}

	//Free resources and close SDL
	close();

	return 0;
}
