#include <SDL2/SDL.h>
#include <stdio.h>
#include <string>
#include <vector>
#include "draw.h"

#define CLOCK_RATE 30
#define TIME_RESOLUTION 10
int TIME_FACTOR = 1;
const int SCREEN_FPS = 30;
const int SCREEN_TICK_PER_FRAME = 1000 / SCREEN_FPS;

class LTimer
{
    public:
		LTimer();
		void start();
		void stop();
		void pause();
		void unpause();
		Uint32 getTicks();
		bool isStarted();
		bool isPaused();

    private:
		Uint32 mStartTicks;
		Uint32 mPausedTicks;
		bool mPaused;
		bool mStarted;
};

LTimer::LTimer() {
    mStartTicks = 0;
    mPausedTicks = 0;
    mPaused = false;
    mStarted = false;
}

void LTimer::start() {
    mStarted = true;
    mPaused = false;
    mStartTicks = SDL_GetTicks();
	mPausedTicks = 0;
}

void LTimer::stop() {
    mStarted = false;
    mPaused = false;
	mStartTicks = 0;
	mPausedTicks = 0;
}

void LTimer::pause()
{
    if( mStarted && !mPaused ) {
        mPaused = true;
        mPausedTicks = SDL_GetTicks() - mStartTicks;
		mStartTicks = 0;
    }
}

void LTimer::unpause(){
    if( mStarted && mPaused ){
        mPaused = false;
        mStartTicks = SDL_GetTicks() - mPausedTicks;
        mPausedTicks = 0;
    }
}

Uint32 LTimer::getTicks()
{
	Uint32 time = 0;
    if( mStarted ) {
        if( mPaused )
        {
            time = mPausedTicks;
        }
        else
        {
            time = SDL_GetTicks() - mStartTicks;
        }
    }

    return time;
}

bool LTimer::isStarted()
{
    return mStarted;
}

bool LTimer::isPaused()
{
    return mPaused && mStarted;
}

class EarthSystem {
    private:
        EarthTexture* earth = NULL;
        Background* bg = NULL;
    public:
        int idx = 0;
        std::vector<OrbitTexture*> currentOrbits = {};
        EarthSystem();
        ~EarthSystem();
        int addOrbit();
        int addOrbit(OrbitTexture*);
        void removeOrbit(int);
        void render(double, int, int);
};

EarthSystem::EarthSystem () {
    earth = new EarthTexture;
    bg = new Background;
}

EarthSystem::~EarthSystem () {
    for( int i=0; i < idx; i++) {
        free(currentOrbits[i]);
    }
    free(earth);
    free(bg);
}

int EarthSystem::addOrbit() {
    currentOrbits.push_back(new OrbitTexture);
    idx++;
    return idx-1;
}

int EarthSystem::addOrbit(OrbitTexture* target) {
    currentOrbits.push_back(new OrbitTexture(target->mOrbit->r, target->mOrbit->v));
    idx++;
    return idx-1;
}
/*
int EarthSystem::addPlanningOrbit(OrbitTexture& target) {
    currentOrbits.push_back(new OrbitTexture(target->mOrbit->r, target->mOrbit->v));
    idx++;
    return idx-1;
}
*/
void EarthSystem::removeOrbit(int i) {
    free(currentOrbits[i]);
    currentOrbits.erase(currentOrbits.begin()+i);
    idx--;
}

void EarthSystem::render(double time, int excluded, int selected) {
    double max_r = 0;
    double r_i;
    for( int i=0; i < idx; i++) {
        r_i = currentOrbits[i]->mOrbit->r_a;
        if (r_i > max_r) {
            max_r = r_i;
        }
    }
    bg->render();
    for( int i=0; i < idx; i++) {
        if ((time > 0) && (i != excluded)) {
            currentOrbits[i]->mOrbit->propagate(time);
        }
        currentOrbits[i]->setViewRange(max_r);
        if (i == selected ) {
            currentOrbits[i]->render(true);
        }
        else {
            currentOrbits[i]->render(false);
        }
    }
    int timeRatio = SCREEN_FPS*TIME_RESOLUTION*TIME_FACTOR;
    earth->render(currentOrbits[0]->scaleX(6378.), timeRatio);
}

bool init();
void close();

bool init(){
    bool success = true;
    if( !drawInit())
    {
        printf( "Graphics module could not initialize! SDL Error: %s\n", SDL_GetError() );
        success = false;
    }
    return success;
}

void close(){
    drawClose();
}

int main( int argc, char* args[] ) {
    if( !init() ) {
        printf( "Failed to initialize!\n" );
    }
    else {
        EarthSystem earthSys;
        earthSys.addOrbit();
        int orbit_select = 0;
        OrbitTexture* targetOrbit = earthSys.currentOrbits[orbit_select];
        bool quit = false;
        SDL_Event e;
		LTimer capTimer;
        bool propagated;
        double dt;
        int excluded = -1;

        while( !quit ) {
            capTimer.start();
            propagated = false;
            dt = TIME_RESOLUTION*double(TIME_FACTOR);
            while( SDL_PollEvent( &e ) != 0 ) {
                if( e.type == SDL_QUIT ) {
                    quit = true;
                } else if( e.type == SDL_KEYDOWN ) {
                    switch( e.key.keysym.sym ) {
                        case SDLK_UP:
                        targetOrbit->mOrbit->goForward(dt);
                        break;

                        case SDLK_DOWN:
                        targetOrbit->mOrbit->goBackward(dt);
                        break;

                        case SDLK_LEFT:
                        targetOrbit->mOrbit->goLeft(dt);
                        break;

                        case SDLK_RIGHT:
                        targetOrbit->mOrbit->goRight(dt);
                        break;

                        case SDLK_f:
                        TIME_FACTOR++;
                        break;

                        case SDLK_s:
                        if (TIME_FACTOR > 0 ) {TIME_FACTOR--;}
                        break;

                        case SDLK_a:
                        orbit_select = earthSys.addOrbit(targetOrbit);
                        targetOrbit = earthSys.currentOrbits[orbit_select];
                        break;

                        case SDLK_r:
                        earthSys.removeOrbit(orbit_select);
                        orbit_select = 0;
                        break;

                        case SDLK_SPACE:
                        targetOrbit->mOrbit->dump_state();
                        break;

                        case SDLK_TAB:
                        if (orbit_select == int(earthSys.currentOrbits.size()-1)) {
                            orbit_select = 0;
                        } else {
                            orbit_select++;
                        }
                        targetOrbit = earthSys.currentOrbits[orbit_select];
                        break;
                    }
                }
            }
            if (propagated) {
                excluded = orbit_select;
            } else {
                excluded = -1;
            }
            earthSys.render(dt, excluded, orbit_select);
            drawUpdate();
		    int frameTicks = capTimer.getTicks();
			if( frameTicks < SCREEN_TICK_PER_FRAME )
			{
				//Wait remaining time
				SDL_Delay( SCREEN_TICK_PER_FRAME - frameTicks );
			}
        }
    }

    close();

    return 0;
}
