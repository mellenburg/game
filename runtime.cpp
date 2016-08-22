#include <SDL2/SDL.h>
#include <stdio.h>
#include <string>
#include <vector>
#include "draw.h"

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
        void render();
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

void EarthSystem::removeOrbit(int i) {
    free(currentOrbits[i]);
    currentOrbits.erase(currentOrbits.begin()+i);
    idx--;
}

void EarthSystem::render() {
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
        currentOrbits[i]->setViewRange(max_r);
        currentOrbits[i]->render();
    }
    earth->render(currentOrbits[0]->scaleX(6371.));
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
        earthSys.addOrbit();
        int orbit_select = 0;
        int porbitIndex;
        OrbitTexture* targetOrbit = earthSys.currentOrbits[orbit_select];
        bool quit = false;
        SDL_Event e;

        bool planningMode = false;
        while( !quit ) {
            while( SDL_PollEvent( &e ) != 0 ) {
                if( e.type == SDL_QUIT ) {
                    quit = true;
                } else if( e.type == SDL_KEYDOWN ) {
                    switch( e.key.keysym.sym ) {
                        case SDLK_UP:
                        targetOrbit->mOrbit->goForward();
                        break;

                        case SDLK_DOWN:
                        targetOrbit->mOrbit->goBackward();
                        break;

                        case SDLK_LEFT:
                        targetOrbit->mOrbit->goLeft();
                        break;

                        case SDLK_RIGHT:
                        targetOrbit->mOrbit->goRight();
                        break;

                        case SDLK_p:
                        if (planningMode) {
                            planningMode = false;
                            earthSys.removeOrbit(porbitIndex);
                            targetOrbit = earthSys.currentOrbits[orbit_select];
                        } else {
                            planningMode = true;
                            // make orbit from current target
                            porbitIndex = earthSys.addOrbit(targetOrbit);
                            // set the new orbit as a target
                            targetOrbit = earthSys.currentOrbits[porbitIndex];
                        }
                        break;

                        case SDLK_RETURN:
                        targetOrbit->mOrbit->propagate(10.0);
                        break;

                        case SDLK_RSHIFT:
                        targetOrbit->mOrbit->propagate(500.0);
                        break;

                        case SDLK_SPACE:
                        targetOrbit->mOrbit->dump_state();
                        break;

                        case SDLK_TAB:
                        if (orbit_select == 1 && not planningMode) {
                            orbit_select = 0;
                        } else if (not planningMode) {
                            orbit_select = 1;
                        }
                        targetOrbit = earthSys.currentOrbits[orbit_select];
                        break;
                    }
                }
            }
            earthSys.render();
            drawUpdate();
        }
    }

    close();

    return 0;
}
