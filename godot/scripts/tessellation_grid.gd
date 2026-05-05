class_name TessellationGrid
extends Control
## Triangular-tessellation overlay that replaces the bottom-left enemy
## status boxes. Lays down 8 rows of vertices with every other row
## offset horizontally by half the in-row spacing; each vertex is
## connected to its 2-6 nearest neighbours so the resulting edges
## describe an equilateral-triangle mesh. Cells (vertices) are labelled
## with their (col, row) grid coordinates so they can be referenced
## individually when grouping cells into a higher-level pattern.
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
const LABEL_COLOR := Color(0.85, 0.95, 1.00, 0.85)
const VERTEX_RADIUS: float = 2.5
const EDGE_WIDTH: float = 1.0
const LABEL_FONT_SIZE: int = 8
const LABEL_OFFSET := Vector2(4.0, -4.0)

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
			var p: Vector2 = row[c]
			draw_circle(p, VERTEX_RADIUS, VERTEX_COLOR)
			if _font != null:
				draw_string(
					_font,
					p + LABEL_OFFSET,
					"%d,%d" % [c, r],
					HORIZONTAL_ALIGNMENT_LEFT,
					-1.0,
					LABEL_FONT_SIZE,
					LABEL_COLOR,
				)
