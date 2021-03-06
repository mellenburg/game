#ifndef ORBIT_DRAW_H
#define ORBIT_DRAW_H
#include <SDL2/SDL.h>
#include <SDL2/SDL_image.h>
#include <SDL2/SDL2_gfxPrimitives.h>
#include <stdio.h>
#include <string>
#include <math.h>
#include "orbit.h"

const int SCREEN_WIDTH = 800;
const int SCREEN_HEIGHT = 800;

SDL_Texture* loadTexture(std::string);

class Background {
    private:
        SDL_Texture* mTexture;
    public:
        Background();
        ~Background();
        void render();
};

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
        SDL_Texture* mSatTexture;
        double argp_degrees;
        double nu_degrees;
        short int sat_x, sat_y;
        double xLow, xHigh, yLow, yHigh, xRange, yRange;
    public:
        EarthOrbit* mOrbit;
        OrbitTexture(vec3D r = {-6045, -3490, 2500}, vec3D v = {-3.56, 6.618, 2.533});
        ~OrbitTexture();
        short int scaleX(double);
        short int scaleY(double);
        void render(bool);
        void setViewRange();
        void setViewRange(double);
};

bool drawInit();
void drawClose();
void drawUpdate();

class EarthTexture {
    private:
        short int viewStartX = 50;
        short int viewStartY = 50;
        short int viewEndX = SCREEN_WIDTH-50;
        short int viewEndY = SCREEN_HEIGHT-50;
        short int viewXLength = viewEndX - viewStartX;
        short int viewYLength = viewEndY - viewStartY;
        short int centerX = (viewXLength/2) + viewStartX;
        short int centerY = (viewYLength/2) + viewStartY;
        short int mTextHeight;
        short int mTextWidth;
        int mTimeRatio = 0;
        SDL_Texture* mTexture;
        SDL_Texture* mTimeTexture;
	    SDL_Rect textQuad;
    public:
        EarthTexture();
        ~EarthTexture();
        void render(short int, int);
        void setRatioTexture(int);
};
#endif
