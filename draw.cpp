#include <SDL2/SDL.h>
#include <SDL2/SDL_image.h>
#include <SDL2/SDL2_gfxPrimitives.h>
#include <stdio.h>
#include <string>
#include <math.h>
#include "orbit.h"
#include "draw.h"

#define PI 3.14159265

SDL_Window* gWindow = NULL;
SDL_Renderer* gRenderer = NULL;

bool drawInit()
{
	bool success = true;
	//Initialize SDL
	if( SDL_Init( SDL_INIT_VIDEO ) < 0 ) {
		printf( "SDL could not initialize! SDL Error: %s\n", SDL_GetError() );
		success = false;
	}
	else {
		//Set texture filtering to linear
		if( !SDL_SetHint( SDL_HINT_RENDER_SCALE_QUALITY, "1" ) ){
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

void drawClose(){
	SDL_DestroyRenderer( gRenderer );
	SDL_DestroyWindow( gWindow );
	gWindow = NULL;
	gRenderer = NULL;
	//Quit SDL subsystems
	IMG_Quit();
	SDL_Quit();
}

SDL_Texture* loadTexture(std::string path)
{
	SDL_Texture* newTexture = NULL;
    //SDL_Surface* loadedSurface = SDL_LoadBMP( path.c_str() );
	SDL_Surface* loadedSurface = IMG_Load( path.c_str() );
	if( loadedSurface == NULL ) {
		printf( "Unable to load image %s! SDL_image Error: %s\n", path.c_str(), IMG_GetError() );
	}
	else {
        newTexture = SDL_CreateTextureFromSurface( gRenderer, loadedSurface );
		if( newTexture == NULL ) {
			printf( "Unable to create texture from %s! SDL Error: %s\n", path.c_str(), SDL_GetError() );
		}
		SDL_FreeSurface( loadedSurface );
	}
	return newTexture;
}

Background::Background(){
    mTexture = loadTexture("bg.png");
}

Background::~Background()
{
	if( mTexture != NULL )
	{
		SDL_DestroyTexture( mTexture );
		mTexture = NULL;
	}
}

void Background::render(){
    SDL_RenderCopy( gRenderer, mTexture, NULL, NULL);
}

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

void OrbitTexture::setViewRange(double r_a){
    xLow = -1.0*r_a;
    xHigh = r_a;
    yLow = -1.0*r_a;
    yHigh = r_a;
    xRange = xHigh - xLow;
    yRange = yHigh - yLow;
}

OrbitTexture::OrbitTexture() {
    //Instantiate with "normal" orbit
   mSatTexture = loadTexture("redfighter.png");
   mTexture = SDL_CreateTexture(gRenderer, SDL_PIXELFORMAT_RGBA8888, SDL_TEXTUREACCESS_TARGET, SCREEN_WIDTH, SCREEN_HEIGHT);
   SDL_SetTextureBlendMode(mSatTexture, SDL_BLENDMODE_BLEND);
   SDL_SetTextureBlendMode(mTexture, SDL_BLENDMODE_BLEND);
   vec3D r = {-6045, -3490, 2500};
   vec3D v = {-3.56, 6.618, 2.533};
   mOrbit = new EarthOrbit(r, v);
   setViewRange();
}

OrbitTexture::~OrbitTexture() {
	if( mTexture != NULL )
	{
		SDL_DestroyTexture( mTexture );
		mTexture = NULL;
	}
    free(mOrbit);
}

void OrbitTexture::render(){
    SDL_SetRenderTarget(gRenderer, mTexture);
	SDL_SetRenderDrawColor( gRenderer, 0x00, 0x00, 0x00, 0x00 );
	SDL_RenderClear( gRenderer );

    //Render ellipse with semimajor axis parallel to X
    //Render ellipse center offset so that argp point at x->0
    aaellipseRGBA(gRenderer, centerX+scaleX(mOrbit->a-mOrbit->r_p), centerY, scaleX(mOrbit->a), scaleY(mOrbit->b), 0x00, 0xFF, 0x00, 0xFF);

    //Find satellite position
    sat_x = centerX-scaleX(cos(mOrbit->nu)*mOrbit->norm_r);
    sat_y = centerY+scaleY(sin(mOrbit->nu)*mOrbit->norm_r);
    short int shipH = 40;
    short int shipW = 38;
    SDL_Rect src = {0, 20, 343, 363};
    SDL_Rect dest = {sat_x-(shipW/2), sat_y-(shipH/2), shipW, shipH};
    //Render satellite
    //Circle for debugging
    //filledCircleRGBA(gRenderer, sat_x, sat_y, 20, 0xFF, 0xD0, 0x00, 0xFF);
    argp_degrees = mOrbit->argp*180.0/PI;
    nu_degrees = mOrbit->nu*-180.0/PI;
    double adj_degrees = acos(dot_product(mOrbit->r, mOrbit->v)/(mOrbit->norm_r*mOrbit->norm_v))*180.0/PI - 90.;
    //SDL_SetRenderTarget(gRenderer, mTexture);
    SDL_RenderCopyEx( gRenderer, mSatTexture, &src, &dest, nu_degrees-adj_degrees, NULL, SDL_FLIP_VERTICAL);
    SDL_SetRenderTarget(gRenderer, NULL);
    SDL_RenderCopyEx( gRenderer, mTexture, NULL, NULL, argp_degrees, NULL, SDL_FLIP_NONE);
}

void drawUpdate(){
    SDL_RenderPresent( gRenderer );
}

EarthTexture::EarthTexture() {
    mTexture = SDL_CreateTexture(gRenderer, SDL_PIXELFORMAT_RGBA8888, SDL_TEXTUREACCESS_TARGET, SCREEN_WIDTH, SCREEN_HEIGHT);
    SDL_SetTextureBlendMode(mTexture, SDL_BLENDMODE_BLEND);
}

EarthTexture::~EarthTexture() {
	if( mTexture != NULL )
	{
		SDL_DestroyTexture( mTexture );
		mTexture = NULL;
	}
}

void EarthTexture::render(short int r){
    SDL_SetRenderTarget(gRenderer, mTexture);
	SDL_SetRenderDrawColor( gRenderer, 0x00, 0x00, 0x00, 0x00 );
	SDL_RenderClear( gRenderer );

    //Render Earth in Center
    filledCircleRGBA(gRenderer, centerX, centerY, r, 0x00, 0x00, 0xFF, 0xFF);
    SDL_SetRenderTarget(gRenderer, NULL);
    SDL_RenderCopy( gRenderer, mTexture, NULL, NULL);
}
