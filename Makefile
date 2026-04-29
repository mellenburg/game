#OBJS specifies which files to compile as part of the project
#OBJS = rotate-ellipse.cpp
OBJS = src/*.cpp

#CC specifies which compiler we're using
CC = g++

#COMPILER_FLAGS specifies the additional compilation options we're using
# -w suppresses all warnings
COMPILER_FLAGS = -g -Wall -I/usr/local/include -I/usr/include/freetype2 -I/usr/include/libpng16 -L/usr/local/lib -L/usr/lib64 -std=c++11 -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free

#LINKER_FLAGS specifies the libraries we're linking against
LINKER_FLAGS = -lGLEW -lSOIL -lglfw -lGL -lX11 -lpthread -lXrandr -lXi -lXxf86vm -ldl -lXinerama -lXcursor -lassimp -ltcmalloc -lfreetype -lz

#OBJ_NAME specifies the name of our exectuable
OBJ_NAME = test

#This is the target that compiles our executable
all : $(OBJS)
		$(CC) $(OBJS) $(COMPILER_FLAGS) -o $(OBJ_NAME) $(LINKER_FLAGS)

# Godot targets. Override GODOT if not on PATH (e.g. GODOT=~/godot/godot).
GODOT ?= godot
GODOT_PROJECT = godot

.PHONY: godot-import godot-test godot-run godot-edit

godot-import:
		$(GODOT) --headless --path $(GODOT_PROJECT) --import

godot-test: godot-import
		$(GODOT) --headless --path $(GODOT_PROJECT) --quit --script res://tests/run_tests.gd

# Run the game (main scene). Depends on godot-import so the .ctex
# texture cache exists; --import is fast/no-op when nothing's stale.
godot-run: godot-import
		$(GODOT) --path $(GODOT_PROJECT)

# Open the Godot editor on the project.
godot-edit: godot-import
		$(GODOT) -e --path $(GODOT_PROJECT)
