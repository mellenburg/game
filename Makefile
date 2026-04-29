# Makefile for the Godot 4 orbital mechanics simulator.
# Override GODOT if your Godot 4.3 binary isn't on PATH:
#   GODOT=~/godot/godot make godot-run

GODOT ?= godot
GODOT_PROJECT = godot

.PHONY: all import test run edit clean

all: test

# Prime the .godot/ import cache. Idempotent — fast no-op when nothing
# is stale. Other targets depend on this so first-run users get the
# compiled .ctex textures generated automatically.
import:
	$(GODOT) --headless --path $(GODOT_PROJECT) --import

# Headless GDScript test suite. CI runs this same command.
test: import
	$(GODOT) --headless --path $(GODOT_PROJECT) --quit --script res://tests/run_tests.gd

# Run the game (main scene).
run: import
	$(GODOT) --path $(GODOT_PROJECT)

# Open the Godot editor on the project.
edit: import
	$(GODOT) -e --path $(GODOT_PROJECT)

# Drop the editor's import cache. Forces full reimport on next build.
clean:
	rm -rf $(GODOT_PROJECT)/.godot
