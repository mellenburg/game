#OBJS specifies which files to compile as part of the project
OBJS = $(wildcard src/sim/*.cpp src/render/*.cpp src/app/*.cpp)

#CC specifies which compiler we're using
CC = g++

#COMPILER_FLAGS specifies the additional compilation options we're using
COMPILER_FLAGS = -g -Wall -Isrc -I/usr/local/include -I/usr/include/freetype2 -I/usr/include/libpng16 -L/usr/local/lib -L/usr/lib64 -std=c++14 -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free

#LINKER_FLAGS specifies the libraries we're linking against
LINKER_FLAGS = -lGLEW -lSOIL -lglfw -lGL -lX11 -lpthread -lXrandr -lXi -lXxf86vm -ldl -lXinerama -lXcursor -lassimp -ltcmalloc -lfreetype -lz

#OBJ_NAME specifies the name of our exectuable
OBJ_NAME = test

#This is the target that compiles our executable
all : $(OBJS)
		$(CC) $(OBJS) $(COMPILER_FLAGS) -o $(OBJ_NAME) $(LINKER_FLAGS)

clean :
		rm -f $(OBJ_NAME)
