class_name TessellationGrid
extends Control
## Triangular-tessellation overlay that replaces the bottom-left enemy
## status boxes. Lays down 8 rows of vertices with every other row
## offset horizontally by half the in-row spacing; each vertex is
## connected to its 2-6 nearest neighbours so the resulting edges
## describe an equilateral-triangle mesh.
##
## Cells (the triangular faces, not the vertices) are labelled "s.t":
## strip s is the gap between vertex rows s and s+1 (s=0 is the
## topmost strip, s=ROWS-2 the bottom one); index t walks left to
## right within the strip, alternating between up- and down-pointing
## triangles. Labels can be referenced individually when grouping
## cells into a higher-level pattern.
##
## Geometry: rows are vertically separated by VERTICAL_SPACING px; the
## in-row horizontal step is 2*tan(30°)*VERTICAL_SPACING, which is
## 2/sqrt(3) — the exact spacing that makes every triangle equilateral.
## Even rows (r % 2 == 0) start at x=0; odd rows are offset right by
## half the horizontal step. Row 0 is at the top of the grid; the grid
## is bottom-anchored within its own Control so it sits where the old
## enemy roster did.

const ROWS: int = 8

# Pixel gap between consecutive rows. Picked so 8 rows comfortably fit
# in the bottom-left HUD slot vacated by the enemy roster.
const VERTICAL_SPACING: float = 30.0

# 2*tan(30°) == 2/sqrt(3). Cached as a constant so _draw doesn't
# re-evaluate the trig identity each frame.
const HORIZONTAL_SPACING: float = 2.0 * VERTICAL_SPACING / 1.7320508075688772

const VERTEX_COLOR := Color(0.55, 0.85, 0.95, 0.95)
const EDGE_COLOR := Color(0.35, 0.55, 0.70, 0.70)
const LABEL_COLOR := Color(0.85, 0.95, 1.00, 0.90)
const VERTEX_RADIUS: float = 2.5
const EDGE_WIDTH: float = 1.0
# Triangle labels live inside the cell so they need to be small enough
# to fit; 7pt is the largest that doesn't routinely clip on a 4-char
# "s.tt" string at the chosen 30 px row spacing.
const LABEL_FONT_SIZE: int = 7

var _font: Font


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = ThemeDB.fallback_font
	resized.connect(queue_redraw)


func _draw() -> void:
	# Available width is the control's own width — main.tscn anchors
	# the right edge to the screen midpoint, so this naturally honours
	# the "extend to halfway across the screen" requirement without the
	# script having to know about the viewport.
	var avail_w: float = size.x
	if avail_w <= 0.0:
		return

	# Bottom-anchored: row 0 is at the top of the grid, row ROWS-1 sits
	# on the control's bottom edge. The old enemy boxes grew bottom-up
	# from the same baseline, so the new tessellation occupies the
	# same visual footprint.
	var y_bottom: float = size.y - 1.0
	var verts: Array = []
	for r in range(ROWS):
		var y: float = y_bottom - float(ROWS - 1 - r) * VERTICAL_SPACING
		var x_offset: float = 0.0 if r % 2 == 0 else HORIZONTAL_SPACING * 0.5
		var row_verts: Array[Vector2] = []
		var c: int = 0
		while x_offset + float(c) * HORIZONTAL_SPACING <= avail_w:
			row_verts.append(Vector2(x_offset + float(c) * HORIZONTAL_SPACING, y))
			c += 1
		verts.append(row_verts)

	# Edges first so vertex dots draw on top. For each vertex we emit
	# its right-neighbour edge plus the two edges that descend into the
	# next row — this covers every unique edge of the triangular mesh
	# exactly once without an O(n^2) pair scan.
	for r in range(ROWS):
		var row: Array[Vector2] = verts[r]
		for c in range(row.size()):
			var p: Vector2 = row[c]
			if c + 1 < row.size():
				draw_line(p, row[c + 1], EDGE_COLOR, EDGE_WIDTH)
			if r + 1 < ROWS:
				var lower: Array[Vector2] = verts[r + 1]
				# Even row → next row is offset right by w/2, so the two
				# downward neighbours sit at indices c-1 and c. Odd row
				# → next row sits flush with x=0, so neighbours are at
				# indices c and c+1. This is the standard triangular-
				# lattice adjacency; off-by-one here would skew every
				# triangle into a degenerate pair.
				var ll: int
				var lr: int
				if r % 2 == 0:
					ll = c - 1
					lr = c
				else:
					ll = c
					lr = c + 1
				if ll >= 0 and ll < lower.size():
					draw_line(p, lower[ll], EDGE_COLOR, EDGE_WIDTH)
				if lr >= 0 and lr < lower.size():
					draw_line(p, lower[lr], EDGE_COLOR, EDGE_WIDTH)

	for r in range(ROWS):
		var row: Array[Vector2] = verts[r]
		for c in range(row.size()):
			draw_circle(row[c], VERTEX_RADIUS, VERTEX_COLOR)

	# Triangle labels. For every strip s in [0, ROWS-2] we walk the
	# triangles left to right, alternating up- and down-pointing. The
	# adjacency rule depends on which of the two bounding rows is the
	# offset (odd-indexed) one — handled below in the two branches.
	# Within a strip the index t starts at 0 on the leftmost triangle
	# and increments by 1 for every triangle drawn, so the user can
	# reference any cell as "s.t" without ambiguity.
	if _font == null:
		return
	for s in range(ROWS - 1):
		var top_row: Array[Vector2] = verts[s]
		var bot_row: Array[Vector2] = verts[s + 1]
		var t_idx: int = 0
		var max_c: int = maxi(top_row.size(), bot_row.size())
		if s % 2 == 0:
			# Top row even (offset 0), bottom row odd (offset w/2).
			# At column c the up-pointing triangle uses bottom[c-1] and
			# bottom[c]; the down-pointing one uses top[c+1] and bot[c].
			# Up at c=0 is invalid (would need bottom[-1]), so the
			# leftmost cell is down(0).
			for c in range(max_c):
				if c >= 1 and c < top_row.size() and c < bot_row.size():
					var up_centroid: Vector2 = (
						top_row[c] + bot_row[c - 1] + bot_row[c]
					) / 3.0
					_draw_cell_label(up_centroid, s, t_idx)
					t_idx += 1
				if c + 1 < top_row.size() and c < bot_row.size():
					var down_centroid: Vector2 = (
						top_row[c] + top_row[c + 1] + bot_row[c]
					) / 3.0
					_draw_cell_label(down_centroid, s, t_idx)
					t_idx += 1
		else:
			# Top row odd (offset w/2), bottom row even (offset 0). Up
			# triangle at column c uses bottom[c] and bottom[c+1] and
			# is anchored at top[c]; down triangle at column c uses
			# top[c+1] and bottom[c+1] and is anchored at top[c]. The
			# leftmost cell here is up(0) — both endpoints exist at
			# c=0 because the bottom row starts flush with x=0.
			for c in range(max_c):
				if (
					c < top_row.size()
					and c + 1 < bot_row.size()
				):
					var up_centroid: Vector2 = (
						top_row[c] + bot_row[c] + bot_row[c + 1]
					) / 3.0
					_draw_cell_label(up_centroid, s, t_idx)
					t_idx += 1
				if (
					c + 1 < top_row.size()
					and c + 1 < bot_row.size()
				):
					var down_centroid: Vector2 = (
						top_row[c] + top_row[c + 1] + bot_row[c + 1]
					) / 3.0
					_draw_cell_label(down_centroid, s, t_idx)
					t_idx += 1


# Centred label drawing: draw_string anchors at the baseline left, so
# we offset by half the measured string width and a small upward nudge
# (~1/3 of the font size) to land the label visually on the centroid
# rather than below-and-right of it.
func _draw_cell_label(centroid: Vector2, s: int, t: int) -> void:
	var text := "%d.%d" % [s, t]
	var text_size := _font.get_string_size(
		text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, LABEL_FONT_SIZE
	)
	var pos := centroid - Vector2(text_size.x * 0.5, -text_size.y * 0.3)
	draw_string(
		_font,
		pos,
		text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		LABEL_FONT_SIZE,
		LABEL_COLOR,
	)
