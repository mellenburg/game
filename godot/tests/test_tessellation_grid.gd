extends "res://tests/framework.gd"
## TessellationGrid hex-grouping tests. The grid script bins every
## cell `(s, t)` into a hex cluster id via _get_hex_id; this test
## locks down the cell→hex mapping for the canonical anchor cases so
## a future refactor can't silently regroup the pattern. We only
## exercise hexes whose six cells all live inside the 9-row grid —
## edge hexes that would extend above row 0 or below row ROWS-1
## return a hex id that doesn't fully resolve and aren't covered.
##
## TessellationGrid extends Control, so each test instantiates a
## fresh node and queue_frees it once the assertions are done. The
## hex-binning path doesn't touch the SceneTree, so a bare new()
## without a tree parent works.

const TessellationGrid = preload("res://scripts/tessellation_grid.gd")


func _grid() -> TessellationGrid:
	return TessellationGrid.new()


func test_rows_constant_is_nine() -> void:
	# Bumping ROWS reshapes the entire pattern. Pin the value so
	# anyone changing it has to retune the hex layout deliberately.
	assert_eq(TessellationGrid.ROWS, 9)


func test_horizontal_spacing_yields_equilateral_triangles() -> void:
	# horizontal = 2 * tan(30°) * vertical, which equals 2 / sqrt(3).
	# That ratio is what makes every emitted triangle equilateral —
	# any other ratio skews the lattice.
	var ratio := TessellationGrid.HORIZONTAL_SPACING / TessellationGrid.VERTICAL_SPACING
	assert_close(ratio, 2.0 / sqrt(3.0), 1.0e-9)


func test_first_hex_groups_six_cells_under_one_id() -> void:
	# Cells spelled out in the original layout spec: s=0..1, t=1..3.
	# All six must resolve to the same hex id; any deviation means
	# the binning function has drifted.
	var g := _grid()
	var expected := Vector2i(0, 1)
	for s: int in [0, 1]:
		for t: int in [1, 2, 3]:
			assert_eq(g._get_hex_id(s, t), expected,
				"cell (%d,%d) misbinned" % [s, t])
	g.queue_free()


func test_second_hex_groups_six_cells_under_one_id() -> void:
	# Spec hex 2: s=1..2, t=6..8 → hex id (1, 6). Exercises the
	# branch-b path of _get_hex_id (the one that walks back a strip).
	var g := _grid()
	var expected := Vector2i(1, 6)
	for s: int in [1, 2]:
		for t: int in [6, 7, 8]:
			assert_eq(g._get_hex_id(s, t), expected,
				"cell (%d,%d) misbinned" % [s, t])
	g.queue_free()


func test_third_hex_groups_six_cells_under_one_id() -> void:
	# Spec hex 3: s=3..4, t=2..4 → hex id (3, 2). Exercises the
	# negative-modulo path on the row-stride wrap.
	var g := _grid()
	var expected := Vector2i(3, 2)
	for s: int in [3, 4]:
		for t: int in [2, 3, 4]:
			assert_eq(g._get_hex_id(s, t), expected,
				"cell (%d,%d) misbinned" % [s, t])
	g.queue_free()


func test_unbinned_cells_return_sentinel() -> void:
	# Cells that aren't a member of any full hex must return the
	# Vector2i(-1, -1) sentinel so the renderer's full-hex filter
	# can drop them. The (s=0, t=0) corner is a leftmost down-tri
	# that's known to fall outside every hex.
	var g := _grid()
	assert_eq(g._get_hex_id(0, 0), Vector2i(-1, -1))
	g.queue_free()
