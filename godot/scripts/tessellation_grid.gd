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

const ROWS: int = 9

# Pixel gap between consecutive rows. Picked so 8 rows comfortably fit
# in the bottom-left HUD slot vacated by the enemy roster.
const VERTICAL_SPACING: float = 30.0

# 2*tan(30°) == 2/sqrt(3). Cached as a constant so _draw doesn't
# re-evaluate the trig identity each frame.
const HORIZONTAL_SPACING: float = 2.0 * VERTICAL_SPACING / 1.7320508075688772

const EDGE_COLOR := Color(0.35, 0.55, 0.70, 0.70)
const LABEL_COLOR := Color(0.85, 0.95, 1.00, 0.90)
const TRIANGLE_COLOR := Color(0.85, 0.20, 0.25, 0.85)
const HEX_COLOR := Color(0.95, 0.55, 0.15, 0.95)
const EDGE_WIDTH: float = 1.0
const EMPTY_COLOR := Color(0.0, 0.0, 0.0, 0.0)

var _enemies: Array = []
var _current_sim_time: float = 0.0

var _final_polys: Array[Dictionary] = []
var _hex_groups: Dictionary = {}
var _poly_centers: Dictionary = {}
var _sorted_hex_ids: Array = []
var _remaining_tris_sorted: Array = []

var _xl_groups: Dictionary = {}
var _sorted_xl_hex_ids: Array = []
var _medium_groups: Array = []

var _assigned_geometry: Dictionary = {}
var _known_enemies: Dictionary = {}
var _highlighted_sat_id: int = 0
# Reference to the currently highlighted satellite (or null). Kept
# alongside _highlighted_sat_id so the click handler can flip the
# satellite's `highlighted` flag without a second lookup, and so the
# HUD can render its status panel without re-resolving the id every
# tick. Cleared automatically when the body dies / despawns.
var highlighted_sat: Satellite = null

const Satellite = preload("res://scripts/satellite.gd")

func update_enemies(satellites: Array, sim_time: float) -> void:
	var enemies = []
	var has_new = false
	var alive_ids = {}
	for sat in satellites:
		if sat.alive and sat.team == 1: # TEAM_ENEMY
			enemies.append(sat)
			var sat_id = sat.get_instance_id()
			alive_ids[sat_id] = true
			if not _known_enemies.has(sat_id):
				has_new = true
				_known_enemies[sat_id] = true
				
	var keys_to_remove = []
	for sat_id in _known_enemies:
		if not alive_ids.has(sat_id):
			keys_to_remove.append(sat_id)
	for sat_id in keys_to_remove:
		_known_enemies.erase(sat_id)
		_assigned_geometry.erase(sat_id)
		# Drop the highlight when its target dies / despawns so the HUD
		# stops claiming a destroyed body is still selected and the orbit
		# tint releases back to the team / ETA gradient.
		if sat_id == _highlighted_sat_id:
			_highlighted_sat_id = 0
			highlighted_sat = null
			
	enemies.sort_custom(func(a, b):
		var get_mass_class = func(mass: float) -> int:
			if mass >= 99000000000.0: return 3
			if mass >= 9900000000.0: return 2
			if mass >= 10000000.0: return 1
			return 0
			
		var class_a = get_mass_class.call(a.mass)
		var class_b = get_mass_class.call(b.mass)
		
		# 1. Strict priority to larger shape classes so they don't get fragmented
		if class_a != class_b:
			return class_a > class_b
			
		var eta_a = a.predict_impact_sim_time(sim_time) - sim_time
		var eta_b = b.predict_impact_sim_time(sim_time) - sim_time
		if not is_finite(eta_a) or eta_a <= 0: eta_a = 99999999.0
		if not is_finite(eta_b) or eta_b <= 0: eta_b = 99999999.0
		
		# 2. Within a shape class, put closest (red) on the left, farthest (yellow) on the right
		return eta_a < eta_b
	)
	_enemies = enemies
	_current_sim_time = sim_time
	
	if has_new:
		_recalculate_allocation()
		
	queue_redraw()

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	resized.connect(_on_resized)
	_on_resized()

func _on_resized() -> void:
	_rebuild_mesh()
	_recalculate_allocation()
	queue_redraw()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var mpos = event.position
		var clicked_sat: Satellite = null
		var clicked_sat_id: int = 0
		for sat in _enemies:
			if not is_instance_valid(sat):
				continue
			var sid: int = sat.get_instance_id()
			if not _assigned_geometry.has(sid):
				continue
			var polys = _assigned_geometry[sid]
			for p in polys:
				if Geometry2D.is_point_in_polygon(mpos, p.pts):
					clicked_sat = sat
					clicked_sat_id = sid
					break
			if clicked_sat != null:
				break

		if clicked_sat_id != _highlighted_sat_id:
			# Clear the previous highlight (if the body is still around).
			if highlighted_sat != null and is_instance_valid(highlighted_sat):
				highlighted_sat.unhighlight()
			highlighted_sat = clicked_sat
			_highlighted_sat_id = clicked_sat_id
			if highlighted_sat != null:
				highlighted_sat.highlight()
			queue_redraw()

func _rebuild_mesh() -> void:
	var avail_w: float = size.x
	if avail_w <= 0.0: return
	var y_bottom: float = size.y - 15.0
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

	var polys_to_draw: Array[Dictionary] = []
	for s in range(ROWS - 1):
		var top_row: Array[Vector2] = verts[s]
		var bot_row: Array[Vector2] = verts[s + 1]
		var t_idx: int = 0
		var max_c: int = maxi(top_row.size(), bot_row.size())
		if s % 2 == 0:
			for c in range(max_c):
				if c >= 1 and c < top_row.size() and c < bot_row.size():
					var pts = PackedVector2Array([top_row[c], bot_row[c - 1], bot_row[c]])
					polys_to_draw.append({"pts": pts, "s": s, "t": t_idx})
					t_idx += 1
				if c + 1 < top_row.size() and c < bot_row.size():
					var pts = PackedVector2Array([top_row[c], top_row[c + 1], bot_row[c]])
					polys_to_draw.append({"pts": pts, "s": s, "t": t_idx})
					t_idx += 1
		else:
			for c in range(max_c):
				if c < top_row.size() and c + 1 < bot_row.size():
					var pts = PackedVector2Array([top_row[c], bot_row[c], bot_row[c + 1]])
					polys_to_draw.append({"pts": pts, "s": s, "t": t_idx})
					t_idx += 1
				if c + 1 < top_row.size() and c + 1 < bot_row.size():
					var pts = PackedVector2Array([top_row[c], top_row[c + 1], bot_row[c + 1]])
					polys_to_draw.append({"pts": pts, "s": s, "t": t_idx})
					t_idx += 1

	var grid_cells = {}
	for poly in polys_to_draw:
		grid_cells[Vector2i(poly.s, poly.t)] = true

	_final_polys.clear()
	for poly in polys_to_draw:
		var hex_id = _get_hex_id(poly.s, poly.t)
		if hex_id == Vector2i(-1, -1):
			_final_polys.append(poly)
		else:
			var is_full = true
			for hs in range(hex_id.x, hex_id.x + 2):
				for ht in range(hex_id.y, hex_id.y + 3):
					if not grid_cells.has(Vector2i(hs, ht)):
						is_full = false
						break
				if not is_full: break
			if is_full:
				_final_polys.append(poly)

	_hex_groups.clear()
	for poly in _final_polys:
		var hex_id = _get_hex_id(poly.s, poly.t)
		if hex_id != Vector2i(-1, -1):
			var is_full = true
			for hs in range(hex_id.x, hex_id.x + 2):
				for ht in range(hex_id.y, hex_id.y + 3):
					if not grid_cells.has(Vector2i(hs, ht)):
						is_full = false
						break
				if not is_full: break
			if is_full:
				if not _hex_groups.has(hex_id):
					_hex_groups[hex_id] = []
				_hex_groups[hex_id].append(poly)

	_poly_centers.clear()
	for poly in _final_polys:
		var cent = (poly.pts[0] + poly.pts[1] + poly.pts[2]) / 3.0
		_poly_centers[Vector2i(poly.s, poly.t)] = cent

	_sorted_hex_ids = _hex_groups.keys()
	_sorted_hex_ids.sort_custom(func(a, b):
		var cx_a = 0.0
		for p in _hex_groups[a]: cx_a += _poly_centers[Vector2i(p.s, p.t)].x
		var cx_b = 0.0
		for p in _hex_groups[b]: cx_b += _poly_centers[Vector2i(p.s, p.t)].x
		return cx_a < cx_b
	)

	_xl_groups.clear()
	for hex_id in _sorted_hex_ids:
		var base_polys = _hex_groups[hex_id]
		var xl_polys = []
		xl_polys.append_array(base_polys)
		for p in _final_polys:
			var is_base = false
			for bp in base_polys:
				if p.s == bp.s and p.t == bp.t:
					is_base = true
					break
			if is_base: continue
			
			var shares = false
			for bp in base_polys:
				var shares_vert = false
				for pt1 in p.pts:
					for pt2 in bp.pts:
						if pt1.distance_squared_to(pt2) < 2.0:
							shares_vert = true
							break
					if shares_vert: break
				if shares_vert:
					shares = true
					break
			if shares:
				xl_polys.append(p)
		
		if xl_polys.size() == 24:
			_xl_groups[hex_id] = xl_polys

	_sorted_xl_hex_ids = _xl_groups.keys()
	_sorted_xl_hex_ids.sort_custom(func(a, b):
		var cx_a = 0.0
		for p in _xl_groups[a]: cx_a += _poly_centers[Vector2i(p.s, p.t)].x
		var cx_b = 0.0
		for p in _xl_groups[b]: cx_b += _poly_centers[Vector2i(p.s, p.t)].x
		return cx_a < cx_b
	)

	_medium_groups.clear()
	for p in _final_polys:
		var neighbors = []
		for cand in _final_polys:
			if cand.s == p.s and cand.t == p.t: continue
			if _is_neighbor(p, cand):
				neighbors.append(cand)
		if neighbors.size() == 3:
			var group = [p]
			group.append_array(neighbors)
			_medium_groups.append(group)
			
	_medium_groups.sort_custom(func(a, b):
		var cx_a = 0.0
		for p in a: cx_a += _poly_centers[Vector2i(p.s, p.t)].x
		var cx_b = 0.0
		for p in b: cx_b += _poly_centers[Vector2i(p.s, p.t)].x
		return cx_a < cx_b
	)

	_remaining_tris_sorted.clear()
	for p in _final_polys:
		_remaining_tris_sorted.append({"poly": p, "x": _poly_centers[Vector2i(p.s, p.t)].x, "y": _poly_centers[Vector2i(p.s, p.t)].y})
	var col_sort = func(a, b):
		if abs(a.x - b.x) < 20.0: return a.y < b.y
		return a.x < b.x
	_remaining_tris_sorted.sort_custom(col_sort)

func _recalculate_allocation() -> void:
	if _final_polys.is_empty():
		_rebuild_mesh()
	if _final_polys.is_empty():
		return
		
	var used_polys = {}
	_assigned_geometry.clear()
	
	for sat in _enemies:
		var assigned_polys = []
		
		if sat.mass >= 99000000000.0: # Extra Large
			for hex_id in _sorted_xl_hex_ids:
				var xl_polys = _xl_groups[hex_id]
				var can_form = true
				for p in xl_polys:
					if used_polys.has(Vector2i(p.s, p.t)):
						can_form = false
						break
				if can_form:
					assigned_polys.append_array(xl_polys)
					break
			
			if assigned_polys.is_empty():
				# Fallback to Large if no perfect 24-triangle available
				for hex_id in _sorted_hex_ids:
					var base_polys = _hex_groups[hex_id]
					var can_form = true
					for p in base_polys:
						if used_polys.has(Vector2i(p.s, p.t)):
							can_form = false
							break
					if can_form:
						assigned_polys.append_array(base_polys)
						break
				
		elif sat.mass >= 9900000000.0: # Large
			for hex_id in _sorted_hex_ids:
				var base_polys = _hex_groups[hex_id]
				var can_form = true
				for p in base_polys:
					if used_polys.has(Vector2i(p.s, p.t)):
						can_form = false
						break
				if can_form:
					assigned_polys.append_array(base_polys)
					break
				
		elif sat.mass >= 10000000.0: # Medium
			for group in _medium_groups:
				var can_form = true
				for p in group:
					if used_polys.has(Vector2i(p.s, p.t)):
						can_form = false
						break
				if can_form:
					assigned_polys.append_array(group)
					break
					
			if assigned_polys.is_empty():
				for i in range(_remaining_tris_sorted.size()):
					var cand = _remaining_tris_sorted[i].poly
					if not used_polys.has(Vector2i(cand.s, cand.t)):
						assigned_polys.append(cand)
						break
					
		else: # Small
			for i in range(_remaining_tris_sorted.size()):
				var cand = _remaining_tris_sorted[i].poly
				if not used_polys.has(Vector2i(cand.s, cand.t)):
					assigned_polys.append(cand)
					break
					
		for p in assigned_polys:
			used_polys[Vector2i(p.s, p.t)] = true
			
		if assigned_polys.size() > 0:
			_assigned_geometry[sat.get_instance_id()] = assigned_polys

func _draw() -> void:
	if _final_polys.is_empty(): return
	
	for sat in _enemies:
		var sat_id = sat.get_instance_id()
		if not _assigned_geometry.has(sat_id): continue
		var polys = _assigned_geometry[sat_id]
		if polys.size() == 0: continue
		
		var color = sat.enemy_path_gradient_color(_current_sim_time)
		var is_highlighted = (sat_id == _highlighted_sat_id)
		var is_flashing = false
		if sat.get("_flash_until") != null and sat._flash_until > 0.0 and sat._wall_now() < sat._flash_until:
			is_flashing = true
		
		var hp_ratio = clamp(sat.hp / max(sat.max_hp, 1.0), 0.0, 1.0)
		var bg_color = color
		bg_color.a = 0.25
		
		var center = Vector2.ZERO
		var total_pts = 0
		for poly in polys:
			for pt in poly.pts:
				center += pt
				total_pts += 1
		if total_pts > 0:
			center /= float(total_pts)
		
		for poly in polys:
			if is_highlighted:
				var fill_col = bg_color.lightened(0.5)
				draw_polygon(poly.pts, PackedColorArray([fill_col, fill_col, fill_col]))
			else:
				draw_polygon(poly.pts, PackedColorArray([bg_color, bg_color, bg_color]))
				
			if hp_ratio > 0.05:
				var scaled_pts = PackedVector2Array()
				for pt in poly.pts:
					scaled_pts.append(center + (pt - center) * hp_ratio)
				
				if is_highlighted:
					var fill_col = color.lightened(0.5)
					draw_polygon(scaled_pts, PackedColorArray([fill_col, fill_col, fill_col]))
				else:
					draw_polygon(scaled_pts, PackedColorArray([color, color, color]))
				
		var edge_counts = {}
		for poly in polys:
			for i in range(3):
				var p1 = poly.pts[i]
				var p2 = poly.pts[(i + 1) % 3]
				var p1r = Vector2i(round(p1.x * 10.0), round(p1.y * 10.0))
				var p2r = Vector2i(round(p2.x * 10.0), round(p2.y * 10.0))
				var key = ""
				if p1r.x < p2r.x or (p1r.x == p2r.x and p1r.y < p2r.y):
					key = str(p1r) + "_" + str(p2r)
				else:
					key = str(p2r) + "_" + str(p1r)
				
				if not edge_counts.has(key):
					edge_counts[key] = {"count": 1, "p1": p1, "p2": p2}
				else:
					edge_counts[key].count += 1
					
		for key in edge_counts:
			if edge_counts[key].count == 1:
				var edge_color = Color.BLACK
				var width = 2.0
				
				if is_highlighted:
					edge_color = Color.WHITE
					width = 4.0
				elif is_flashing:
					edge_color = Color(1.0, 0.2, 0.2) # Bright red border
					width = 4.0
					
				draw_line(edge_counts[key].p1, edge_counts[key].p2, edge_color, width)

func _is_neighbor(p1: Dictionary, p2: Dictionary) -> bool:
	var shared_verts = 0
	for pt1 in p1.pts:
		for pt2 in p2.pts:
			if pt1.distance_squared_to(pt2) < 2.0:
				shared_verts += 1
				break
	return shared_verts == 2


func _get_hex_id(s: int, t: int) -> Vector2i:
	var a = t - 1 - 5 * s
	var rem_a = (a % 14 + 14) % 14
	if rem_a == 0 or rem_a == 1 or rem_a == 2:
		return Vector2i(s, t - rem_a)
		
	var b = t + 4 - 5 * s
	var rem_b = (b % 14 + 14) % 14
	if rem_b == 0 or rem_b == 1 or rem_b == 2:
		return Vector2i(s - 1, t - rem_b)
		
	return Vector2i(-1, -1)
