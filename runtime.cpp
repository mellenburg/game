#include <SDL2/SDL.h>
#include <stdio.h>
#include <string>
#include "draw.h"

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
            OrbitTexture mainOrbit;
            Background bg;
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
                            mainOrbit.mOrbit->goForward();
							break;

							case SDLK_DOWN:
                            mainOrbit.mOrbit->goBackward();
							break;

							case SDLK_LEFT:
                            mainOrbit.mOrbit->goLeft();
							break;

							case SDLK_RIGHT:
                            mainOrbit.mOrbit->goRight();
							break;

							case SDLK_p:
                            if(planningMode){
                                planningMode = false;
                            } else {
                                planningMode = true;
                            }
							break;

                            case SDLK_RETURN:
                            mainOrbit.mOrbit->propagate(10.0);
                            break;

                            case SDLK_RSHIFT:
                            mainOrbit.mOrbit->propagate(500.0);
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
                drawUpdate();
		}
	}

	close();

	return 0;
}
