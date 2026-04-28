# Source layout
SIM_SRCS    = $(wildcard src/sim/*.cpp)
RENDER_SRCS = $(wildcard src/render/*.cpp)
APP_SRCS    = $(wildcard src/app/*.cpp)
TEST_SRCS   = $(wildcard tests/*.cpp)

# Game (full build) sources
OBJS = $(SIM_SRCS) $(RENDER_SRCS) $(APP_SRCS)

CC = g++

# Game build needs OpenGL, freetype, etc. and links tcmalloc.
COMPILER_FLAGS = -g -Wall -Isrc -I/usr/local/include -I/usr/include/freetype2 -I/usr/include/libpng16 -L/usr/local/lib -L/usr/lib64 -std=c++14 -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free
LINKER_FLAGS   = -lGLEW -lSOIL -lglfw -lGL -lX11 -lpthread -lXrandr -lXi -lXxf86vm -ldl -lXinerama -lXcursor -lassimp -ltcmalloc -lfreetype -lz

# Tests need only the sim sources and glm (header-only). They are GL-free
# so CI can run them without any graphics libraries / display server.
TEST_FLAGS = -g -Wall -Isrc -I. -std=c++14

OBJ_NAME = test
TEST_BIN = run_tests

all : $(OBJS)
	$(CC) $(OBJS) $(COMPILER_FLAGS) -o $(OBJ_NAME) $(LINKER_FLAGS)

# Build the GL-free unit tests. Run with `make check`.
$(TEST_BIN) : $(SIM_SRCS) $(TEST_SRCS)
	$(CC) $(SIM_SRCS) $(TEST_SRCS) $(TEST_FLAGS) -o $(TEST_BIN)

tests : $(TEST_BIN)

check : $(TEST_BIN)
	./$(TEST_BIN)

clean :
	rm -f $(OBJ_NAME) $(TEST_BIN)

.PHONY : all tests check clean
