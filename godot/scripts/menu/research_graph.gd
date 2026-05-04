extends Control
## Visualises the Research catalog as a stack of 1D chain graphs.
## Every chain renders as a horizontal strip of polygon nodes connected
## by line segments; nodes light up (filled) when unlocked, outline-only
## when available, and dim when locked behind a missing prereq. Clicking
## a node emits `node_selected(node_id)` so the menu can populate its
## description panel.
##
## Pure visual + click-routing; the menu owns the description panel and
## the actual unlock action. The view re-reads Research state in
## `refresh()` (called after every unlock) — chains are short, so the
## brute-force rebuild keeps the per-node state cheap and trivially
## consistent with the underlying dictionary.

signal node_selected(node_id: String)

# Layout constants. NODE_SIZE is the polygon's bounding box; SPACING is
# the centre-to-centre distance between consecutive nodes; ROW_HEIGHT
# allows room for the polygon plus the label below it.
const NODE_SIZE: float = 84.0
const NODE_SPACING: float = 170.0
const ROW_HEIGHT: float = 130.0
const HEADER_PAD_LEFT: float = 12.0
const NODES_PAD_LEFT: float = 168.0
const ROW_TOP_PAD: float = 12.0
const TIER_LABEL_HEIGHT: float = 18.0

# Per-category accent colour. Drives the node fill (when unlocked), the
# outline (when available / hovered), the connector line, and the
# category label on the left edge.
const CATEGORY_COLORS: Dictionary = {
	"Lasers": Color(1.0, 0.42, 0.45),
	"Railguns": Color(1.0, 0.72, 0.30),
	"Cooling Systems": Color(0.55, 0.85, 1.0),
	"Energy Storage": Color(0.85, 1.0, 0.50),
	"Reactors": Color(1.0, 0.55, 1.0),
	"Launch Capacity": Color(0.50, 1.0, 0.78),
	"Ground Defense": Color(0.85, 0.85, 0.95),
}

const COLOR_LOCKED := Color(0.32, 0.34, 0.40)
const COLOR_FG_DIM := Color(0.55, 0.58, 0.64)
const COLOR_FG := Color(0.86, 0.88, 0.92)

var _selected_id: String = ""
var _chains_cache: Array = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	_rebuild()


func refresh() -> void:
	_rebuild()


# Highlight a node id (drawn with a thicker outline) so the operator
# can see which entry the description panel is currently describing.
# Pass "" to clear the highlight.
func set_selected(node_id: String) -> void:
	_selected_id = node_id
	for child in get_children():
		if child is _ResearchNode:
			(child as _ResearchNode).selected = (child.node_id == node_id)
			(child as _ResearchNode).queue_redraw()
	queue_redraw()


# Drop child nodes, re-read the catalog, and rebuild the per-tier
# polygon controls. The connector lines are drawn in `_draw` directly
# off `_chains_cache`, so they refresh on the next paint.
func _rebuild() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_chains_cache = Research.all_chains()

	var min_height: float = _chains_cache.size() * ROW_HEIGHT + ROW_TOP_PAD * 2
	custom_minimum_size = Vector2(900.0, min_height)

	for row_idx in range(_chains_cache.size()):
		var chain: Dictionary = _chains_cache[row_idx]
		var color: Color = CATEGORY_COLORS.get(
			chain["category"], COLOR_FG,
		)
		var y_top: float = ROW_TOP_PAD + row_idx * ROW_HEIGHT
		var y_center: float = y_top + (ROW_HEIGHT - TIER_LABEL_HEIGHT) * 0.5

		var category_label := Label.new()
		category_label.text = String(chain["category"]).to_upper()
		category_label.add_theme_color_override("font_color", color)
		category_label.add_theme_font_size_override("font_size", 12)
		category_label.position = Vector2(
			HEADER_PAD_LEFT, y_center - 9.0,
		)
		category_label.size = Vector2(NODES_PAD_LEFT - HEADER_PAD_LEFT - 8.0, 18.0)
		add_child(category_label)

		var tiers: Array = chain["tiers"]
		var shape: String = String(chain.get("shape", "hex"))
		for tier_idx in range(tiers.size()):
			var tier: Dictionary = tiers[tier_idx]
			var node_id := String(tier["id"])
			var x_center := _node_x_center(tier_idx)

			var node := _ResearchNode.new()
			node.node_id = node_id
			node.shape = shape
			node.category_color = color
			node.state = _state_for(node_id)
			node.selected = node_id == _selected_id
			node.position = Vector2(
				x_center - NODE_SIZE * 0.5, y_center - NODE_SIZE * 0.5,
			)
			node.size = Vector2(NODE_SIZE, NODE_SIZE)
			node.clicked.connect(_on_node_clicked)
			add_child(node)

			var tier_label := Label.new()
			tier_label.text = String(tier["label"])
			tier_label.add_theme_font_size_override("font_size", 11)
			var label_color := COLOR_FG if node.state == "unlocked" else COLOR_FG_DIM
			tier_label.add_theme_color_override("font_color", label_color)
			tier_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			tier_label.position = Vector2(
				x_center - NODE_SPACING * 0.5,
				y_center + NODE_SIZE * 0.5 + 4.0,
			)
			tier_label.size = Vector2(NODE_SPACING, TIER_LABEL_HEIGHT)
			add_child(tier_label)

	queue_redraw()


# Compute the centre x of the tier-th node in any row.
func _node_x_center(tier_index: int) -> float:
	return NODES_PAD_LEFT + tier_index * NODE_SPACING + NODE_SPACING * 0.5


func _state_for(node_id: String) -> String:
	if Research.is_unlocked(node_id):
		return "unlocked"
	var prereq := Research.prereq_for(node_id)
	if prereq != "" and not Research.is_unlocked(prereq):
		return "locked"
	return "available"


func _on_node_clicked(node_id: String) -> void:
	set_selected(node_id)
	node_selected.emit(node_id)


# Draw the connector lines between consecutive tiers in each chain.
# A connector is bright (category colour) when its target tier is
# unlocked, dim grey otherwise — the eye reads the unlocked path
# through the chain without needing per-segment markers.
func _draw() -> void:
	for row_idx in range(_chains_cache.size()):
		var chain: Dictionary = _chains_cache[row_idx]
		var color: Color = CATEGORY_COLORS.get(chain["category"], COLOR_FG)
		var y_top: float = ROW_TOP_PAD + row_idx * ROW_HEIGHT
		var y_center: float = y_top + (ROW_HEIGHT - TIER_LABEL_HEIGHT) * 0.5
		var tiers: Array = chain["tiers"]
		for tier_idx in range(tiers.size() - 1):
			var x1 := _node_x_center(tier_idx) + NODE_SIZE * 0.45
			var x2 := _node_x_center(tier_idx + 1) - NODE_SIZE * 0.45
			var next_id := String(tiers[tier_idx + 1]["id"])
			var line_color := color if Research.is_unlocked(next_id) else COLOR_LOCKED
			draw_line(Vector2(x1, y_center), Vector2(x2, y_center), line_color, 2.0)


# Inner Control class for a single research node. Owns its own _draw
# (renders the polygon) and _gui_input (translates clicks into the
# parent's `node_selected` signal). Keeping it here rather than in a
# sibling file avoids polluting the catalog with another tiny script
# and keeps the geometry math next to the layout that places it.
class _ResearchNode extends Control:
	signal clicked(node_id: String)

	var node_id: String = ""
	var shape: String = "hex"
	var state: String = "available"
	var category_color: Color = Color.WHITE
	var selected: bool = false
	var _hovered: bool = false

	func _ready() -> void:
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_entered.connect(func() -> void:
			_hovered = true
			queue_redraw()
		)
		mouse_exited.connect(func() -> void:
			_hovered = false
			queue_redraw()
		)

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton:
			var mb := event as InputEventMouseButton
			if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
				clicked.emit(node_id)
				accept_event()

	func _draw() -> void:
		var center := size * 0.5
		var radius := minf(size.x, size.y) * 0.45
		var pts := _polygon_points(center, radius)
		# Background fill scales with state. Unlocked nodes get a solid
		# accent fill; available ones get a faint accent wash so they
		# read as "ready to go" without dominating the palette; locked
		# nodes stay outline-only against the panel background.
		match state:
			"unlocked":
				draw_colored_polygon(pts, category_color)
			"available":
				var wash := category_color
				wash.a = 0.18
				draw_colored_polygon(pts, wash)
			"locked":
				pass
		var outline_color: Color = category_color
		var outline_width: float = 2.0
		if state == "unlocked":
			outline_width = 3.0
		elif state == "locked":
			outline_color = COLOR_LOCKED
			outline_width = 1.5
		if _hovered or selected:
			outline_width += 1.5
			outline_color = outline_color.lightened(0.25)
		# Polyline closes the polygon (last edge → first vertex). Drawn
		# as line segments so we can vary the width per state without
		# the closed-polyline call's stylistic quirks.
		for i in range(pts.size()):
			var a := pts[i]
			var b := pts[(i + 1) % pts.size()]
			draw_line(a, b, outline_color, outline_width)

	func _polygon_points(
		center: Vector2, radius: float,
	) -> PackedVector2Array:
		var n: int
		match shape:
			"diamond":
				n = 4
			"octagon":
				n = 8
			_:
				n = 6
		var out := PackedVector2Array()
		for i in range(n):
			var angle := -PI * 0.5 + (float(i) / float(n)) * TAU
			out.append(center + Vector2(cos(angle), sin(angle)) * radius)
		return out

	const COLOR_LOCKED := Color(0.32, 0.34, 0.40)
