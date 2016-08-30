#OBJS specifies which files to compile as part of the project
#OBJS = rotate-ellipse.cpp
OBJS = src/*.cpp

#CC specifies which compiler we're using
CC = g++

#COMPILER_FLAGS specifies the additional compilation options we're using
# -w suppresses all warnings
#COMPILER_FLAGS = -g -Wall -I/usr/local/include -L/usr/local/lib -L/usr/lib/x86_64-linux-gnu/ -std=c++11
COMPILER_FLAGS = -g -Wall -I/usr/local/include -L/usr/local/lib -L/usr/lib64 -std=c++11 -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free

#
#  #LINKER_FLAGS specifies the libraries we're linking against
LINKER_FLAGS = -lGLEW -lSOIL -lglfw3 -lGL -lX11 -lpthread -lXrandr -lXi -lXxf86vm -ldl -lXinerama -lXcursor -lassimp -ltcmalloc

#OBJ_NAME specifies the name of our exectuable
OBJ_NAME = test

#This is the target that compiles our executable
all : $(OBJS)
		$(CC) $(OBJS) $(COMPILER_FLAGS) -o $(OBJ_NAME) $(LINKER_FLAGS)
