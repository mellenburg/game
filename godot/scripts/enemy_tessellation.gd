class_name EnemyTessellation
extends Control
## Bottom-left enemy roster rendered as a triangle/hexagon tessellation.
## One tile per live enemy unit, sized by mass class:
##   * SMALL  -> equilateral triangle
##   * MEDIUM -> pointy-top hexagon
##   * LARGE  -> central hexagon + 6 inner triangles + 12 outer triangles
##              (a star-shaped composite)
##   * BOSS   -> LARGE composite plus an adjacent medium hexagon and a
##              pair of bridging triangles, so the silhouette reads as
##              "irregular bigger thing".
##
## Tiles are ordered by impact ETA — most urgent in the bottom-left
## corner, filling rightward and wrapping into rows above. The roster
## anchors to the bottom-left of the screen so the most urgent threat
## is closest to where the player's attention sits during combat.
##
## Per-tile rendering draws two layers:
##   1. A faint full-size "lost-HP" backplate showing the tile's
##      original footprint (analogous to the old ColorRect's 30%-alpha
##      red layer).
##   2. The live polygons scaled inward toward each subshape's
##      centroid — the linear scale equals sqrt(hp/max_hp) so the
##      drawn area tracks HP linearly. Hit flashes paint the live
##      polygons red for the same wall-clock window the old box used.
##
## Click handling: a click inside any subshape selects that tile's
## satellite for the upper-right status panel. Selection is local to
## the tessellation (does not change the player's selected_ship). The
## inspected enemy is exposed via a property the HUD wires to the
## status panel.
##
## Computational profile: tile geometries are precomputed once at
## script load (build_geometries()); per-frame work is one polygon
## draw per subshape, at most ~30 subshapes per tile (BOSS) and a
## couple of dozen tiles in dense waves. No per-frame allocations
## beyond the scaled-vertex array, which reuses a PackedVector2Array.

const Satellite = preload("res://scripts/satellite.gd")
const MeteorPhysics = preload("res://scripts/meteor_physics.gd")

signal enemy_clicked(sat: Satellite)

# Visual tuning
const EDGE_PX: float = 12.0                 # base unit edge length
const SQRT3: float = 1.7320508075688772

# Tile spacing within a row and between rows. Small enough that the
# tessellation reads as a tight cluster, large enough that triangle
# corners don't visually merge across tiles.
const TILE_PAD_X: float = 6.0
const TILE_PAD_Y: float = 6.0

# Faint backplate showing the tile's full footprint — the area the
# live polygon shrinks against. Translucent red so it reads as "lost
# HP" without competing with the live fill.
const LOST_HP_COLOR: Color = Color(1.0, 0.3, 0.3, 0.30)

# Live-fill alpha — the per-tile color comes from
# Satellite.enemy_path_gradient_color so the bottom-strip and 3D ribbon
# read off the same yellow→red ETA gradient.
const FILL_ALPHA: float = 0.95

# Roster box flash on hit. Same red the old square-box HUD used so the
# damage cue stays consistent across the redesign.
const HIT_FLASH_COLOR: Color = Color(0.95, 0.15, 0.15, 0.95)

# Selected-tile fill — bright green, matches the player-roster
# selection tint so the HUD's "this is the unit you're inspecting"
# signal is uniform across both rosters.
const SELECTED_COLOR: Color = Color(0.20, 1.00, 0.20, 1.0)

# Border around each subshape — a thin dark outline that disambiguates
# overlapping tiles when the tessellation packs tightly. Drawn at the
# full footprint so it stays put while the live fill shrinks.
const OUTLINE_COLOR: Color = Color(0.0, 0.0, 0.0, 0.55)
const OUTLINE_WIDTH: float = 1.0

# Mass-class tile size scales — bigger classes draw with proportionally
# larger polygon edges so the HUD hierarchy reads at a glance.
const SCALE_SMALL: float = 2.4
const SCALE_MEDIUM: float = 1.8
const SCALE_LARGE: float = 1.0
const SCALE_BOSS: float = 1.2

# How aggressively the live polygon shrinks at low HP. Linear scale
# equals sqrt(hp/max) so the *area* of the polygon tracks HP linearly
# (matches the old square-box convention where the fill height
# tracked HP linearly, area = width * height).
static func _hp_to_scale(frac: float) -> float:
	return sqrt(clampf(frac, 0.0, 1.0))


# A precomputed tile shape: list of subshape polygons (PackedVector2Array,
# math-y-up coords), centroid per subshape, bounding rect of the
# composite (in math-y-up coords).
class TileGeometry:
	var subshapes: Array  # Array[PackedVector2Array]
	var centroids: PackedVector2Array
	var bounds: Rect2

	func _init(polys: Array) -> void:
		subshapes = polys
		centroids = PackedVector2Array()
		var lo := Vector2(INF, INF)
		var hi := Vector2(-INF, -INF)
		for poly: PackedVector2Array in polys:
			var c := Vector2.ZERO
			for v: Vector2 in poly:
				c += v
				lo.x = minf(lo.x, v.x)
				lo.y = minf(lo.y, v.y)
				hi.x = maxf(hi.x, v.x)
				hi.y = maxf(hi.y, v.y)
			if poly.size() > 0:
				c /= float(poly.size())
			centroids.append(c)
		bounds = Rect2(lo, hi - lo)


# Cache: one TileGeometry per mass class. Built once on script load.
static var _GEOM_CACHE: Dictionary = {}

static func geom_for_class(cls: int) -> TileGeometry:
	if _GEOM_CACHE.is_empty():
		_GEOM_CACHE[MeteorPhysics.MASS_CLASS_SMALL] = TileGeometry.new(_build_small())
		_GEOM_CACHE[MeteorPhysics.MASS_CLASS_MEDIUM] = TileGeometry.new(_build_medium())
		_GEOM_CACHE[MeteorPhysics.MASS_CLASS_LARGE] = TileGeometry.new(_build_large())
		_GEOM_CACHE[MeteorPhysics.MASS_CLASS_BOSS] = TileGeometry.new(_build_boss())
	var key: int = cls
	if not _GEOM_CACHE.has(key):
		key = MeteorPhysics.MASS_CLASS_SMALL
	var entry: TileGeometry = _GEOM_CACHE[key]
	return entry


# --- Polygon builders -------------------------------------------------

# Pointy-top hexagon, side s, centered at origin.
static func _hex(s: float) -> PackedVector2Array:
	var h := s * SQRT3 / 2.0
	return PackedVector2Array([
		Vector2(0.0, -s),
		Vector2(h, -s / 2.0),
		Vector2(h, s / 2.0),
		Vector2(0.0, s),
		Vector2(-h, s / 2.0),
		Vector2(-h, -s / 2.0),
	])


# Equilateral triangle of side s, with apex pointing in direction
# `apex_angle` (radians; angle measured in math-y-up coords from +x).
static func _tri(cx: float, cy: float, s: float, apex_angle: float) -> PackedVector2Array:
	# Canonical (apex pointing toward +y): vertices below.
	var apex := Vector2(0.0, s * SQRT3 / 3.0)
	var base_r := Vector2(s / 2.0, -s * SQRT3 / 6.0)
	var base_l := Vector2(-s / 2.0, -s * SQRT3 / 6.0)
	# Canonical apex points along +y (angle = π/2 in math coords); rotate
	# by apex_angle - π/2 so the requested direction lands.
	var rot := apex_angle - PI / 2.0
	var c := cos(rot)
	var sn := sin(rot)
	return PackedVector2Array([
		Vector2(apex.x * c - apex.y * sn + cx, apex.x * sn + apex.y * c + cy),
		Vector2(base_r.x * c - base_r.y * sn + cx, base_r.x * sn + base_r.y * c + cy),
		Vector2(base_l.x * c - base_l.y * sn + cx, base_l.x * sn + base_l.y * c + cy),
	])


# Reflect point p across the line through a and b.
static func _reflect(p: Vector2, a: Vector2, b: Vector2) -> Vector2:
	var d := b - a
	var l2 := d.length_squared()
	if l2 == 0.0:
		return p
	var t := d.dot(p - a) / l2
	var foot := a + d * t
	return foot * 2.0 - p


static func _build_small() -> Array:
	var s := EDGE_PX * SCALE_SMALL
	# Apex up (math y-up means +y). One triangle.
	return [_tri(0.0, 0.0, s, PI / 2.0)]


static func _build_medium() -> Array:
	var s := EDGE_PX * SCALE_MEDIUM
	return [_hex(s)]


# Hexagon (side s) + 6 inner triangles touching its edges + 12 outer
# triangles reflected across each inner triangle's outward edges.
# Total: 1 + 6 + 12 = 19 polygons (1 hex, 18 triangles).
static func _build_large() -> Array:
	var s := EDGE_PX * SCALE_LARGE
	var polys: Array = []
	polys.append(_hex(s))
	var apothem := s * SQRT3 / 2.0
	# Inner triangles: centers at distance apothem + tri_apothem,
	# apex pointing outward at angle k*60°.
	for k in range(6):
		var angle := float(k) * PI / 3.0
		var dirv := Vector2(cos(angle), sin(angle))
		var tri_apothem := s * SQRT3 / 6.0
		var center := dirv * (apothem + tri_apothem)
		polys.append(_tri(center.x, center.y, s, angle))
	# Outer triangles: 2 per inner triangle, sharing the inner tri's
	# outward edges (base-vertex -> apex).
	for k in range(6):
		var angle := float(k) * PI / 3.0
		var dirv := Vector2(cos(angle), sin(angle))
		var perp := Vector2(-sin(angle), cos(angle))
		var base_l := dirv * apothem + perp * (s / 2.0)
		var base_r := dirv * apothem - perp * (s / 2.0)
		var apex := dirv * (s * SQRT3)
		# Reflect the unused base vertex across each outward edge.
		var third_l := _reflect(base_r, base_l, apex)
		var third_r := _reflect(base_l, base_r, apex)
		polys.append(PackedVector2Array([base_l, apex, third_l]))
		polys.append(PackedVector2Array([base_r, apex, third_r]))
	return polys


# Boss = LARGE composite + a MEDIUM hexagon offset to the right + 2
# small triangles bridging them. Asymmetric on purpose — the
# silhouette is meant to read as "irregular bigger thing", not as a
# regular larger polygon.
static func _build_boss() -> Array:
	var polys: Array = _build_large()
	# Scale up the LARGE composite slightly so the boss's bulk reads
	# as a step above LARGE before we add the asymmetric piece.
	for i in range(polys.size()):
		var poly: PackedVector2Array = polys[i]
		var scaled := PackedVector2Array()
		for v: Vector2 in poly:
			scaled.append(v * SCALE_BOSS)
		polys[i] = scaled
	# Right-hand attachment: a medium hex with two flanking triangles
	# bridging the gap. Offset placed past the LARGE composite's
	# outermost reach so the two clusters touch but don't overlap.
	var s_med := EDGE_PX * SCALE_MEDIUM * 0.85
	var large_radius := EDGE_PX * SCALE_LARGE * SQRT3 * SCALE_BOSS  # outermost reach of LARGE
	var hex_offset := Vector2(large_radius + s_med * SQRT3 / 2.0 + 2.0, 0.0)
	var hex_poly := _hex(s_med)
	var translated := PackedVector2Array()
	for v: Vector2 in hex_poly:
		translated.append(v + hex_offset)
	polys.append(translated)
	# Two bridging triangles above and below the gap, pointing inward
	# so they read as connective tissue rather than an extra burst.
	var bridge_size := EDGE_PX * SCALE_MEDIUM * 0.65
	polys.append(_tri(
		hex_offset.x - s_med * SQRT3 / 2.0 - bridge_size * 0.4,
		-bridge_size * 0.6,
		bridge_size,
		-PI / 2.0,
	))
	polys.append(_tri(
		hex_offset.x - s_med * SQRT3 / 2.0 - bridge_size * 0.4,
		bridge_size * 0.6,
		bridge_size,
		PI / 2.0,
	))
	return polys


# --- Tile state -------------------------------------------------------

# Per-tile placement data: which satellite, where to draw it (origin
# in screen-control coords), which geometry, current color and
# fraction. Recomputed each layout pass; reused across draws within a
# pass.
class PlacedTile:
	var sat: Satellite
	var origin: Vector2     # placement point in control-local screen coords
	var geom: TileGeometry
	var fill: Color
	var hp_frac: float
	var hit_flash: bool
	var selected: bool


# Live state: the placed tiles for the current frame, the inspected
# satellite (for the status panel), and the hit set passed in from the
# HUD each tick.
var _tiles: Array[PlacedTile] = []
var _hit_targets: Array = []   # Array[Satellite] — hit-flashing this frame
var _selected_enemy: Satellite = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	# Make sure draws happen even if the HUD's queue_redraw plumbing is
	# inactive (the existing target-line code calls queue_redraw every
	# frame on the HUD, but the tessellation lives below it as a child,
	# so we drive our own redraws).
	set_process(true)


func _process(_delta: float) -> void:
	# Per-frame redraw — cheap because all tile work is done in update().
	queue_redraw()


# Called by HUD each render tick (~10 Hz). `enemies` is in display
# order (most urgent first); `hit_targets` is the live hit-flash set
# the HUD already maintains.
func update_tiles(
	enemies: Array,
	current_sim_time: float,
	hit_targets: Array,
) -> void:
	_hit_targets = hit_targets
	# Drop any selection whose backing satellite is gone, dead, or no
	# longer in the current display list. Planning-mode entry replaces
	# every Satellite instance with a clone, so a selected real-mode
	# enemy will fail this membership check on toggle and the inspector
	# panel will hide itself rather than drift onto a stale reference.
	if _selected_enemy != null:
		if not is_instance_valid(_selected_enemy) \
				or not (_selected_enemy as Satellite).alive \
				or not enemies.has(_selected_enemy):
			_selected_enemy = null

	var area_w: float = size.x
	if area_w <= 0.0:
		# Control hasn't been laid out yet; defer placement to the next
		# tick rather than packing into a zero-width strip.
		_tiles.clear()
		return

	# Two-pass row pack: assign each enemy to a row first (so we know
	# every row's tallest tile before placing it), then walk rows
	# bottom-up baselining tiles to a common bottom edge. Rows are kept
	# as Array of Array[PlacedTile]; an outer plain Array keeps GDScript
	# typed-array machinery from rejecting the nested-Array shape.
	_tiles.clear()
	var rows: Array = []
	var current_row: Array[PlacedTile] = []
	var row_x: float = TILE_PAD_X
	for sat: Satellite in enemies:
		if not is_instance_valid(sat):
			continue
		if not sat.alive:
			continue
		var cls := MeteorPhysics.mass_class_for(sat.mass)
		var geom := geom_for_class(cls)
		var w: float = geom.bounds.size.x
		# Wrap to next row when the current row would overflow the
		# control width. Allow at least one tile per row so a single
		# very wide BOSS still places.
		if not current_row.is_empty() and row_x + w > area_w - TILE_PAD_X:
			rows.append(current_row)
			current_row = []
			row_x = TILE_PAD_X
		var tile := PlacedTile.new()
		tile.sat = sat
		tile.geom = geom
		tile.fill = _color_for(sat, current_sim_time)
		tile.hp_frac = clampf(sat.hp / maxf(sat.max_hp, 1.0), 0.0, 1.0)
		tile.hit_flash = _is_hit_target(sat)
		tile.selected = (_selected_enemy != null and sat == _selected_enemy)
		# Stash the row-relative left edge in origin.x; the y placement
		# is resolved in the second pass once the row's tallest tile is
		# known.
		tile.origin = Vector2(row_x, 0.0)
		current_row.append(tile)
		row_x += w + TILE_PAD_X
	if not current_row.is_empty():
		rows.append(current_row)

	# Bottom-up placement. cur_bottom is the screen-y of the row's
	# baseline (the screen-y the tile's lowest math vertex maps to).
	# Each row sits above the row below it by (row's max height +
	# TILE_PAD_Y).
	var cur_bottom: float = size.y - TILE_PAD_Y
	for r in range(rows.size()):
		var row: Array = rows[r]
		if row.is_empty():
			continue
		var max_h: float = 0.0
		for tile_var in row:
			var t: PlacedTile = tile_var
			max_h = maxf(max_h, t.geom.bounds.size.y)
		for tile_var2 in row:
			var t2: PlacedTile = tile_var2
			# screen_left = origin.x + bounds.position.x → solve for
			#   origin.x = desired_left - bounds.position.x
			# screen_bottom = origin.y - bounds.position.y (math-y-up
			# bounds.position.y is the min math y, which negates to the
			# largest screen y — the screen bottom of the tile).
			#   → origin.y = cur_bottom + bounds.position.y
			var tx: float = t2.origin.x - t2.geom.bounds.position.x
			var ty: float = cur_bottom + t2.geom.bounds.position.y
			t2.origin = Vector2(tx, ty)
			_tiles.append(t2)
		cur_bottom -= max_h + TILE_PAD_Y

	queue_redraw()


# Returns true while `sat` is in the HUD's hit-flash set.
func _is_hit_target(sat: Satellite) -> bool:
	for h in _hit_targets:
		if not is_instance_valid(h):
			continue
		if h == sat:
			return true
	return false


func _color_for(sat: Satellite, current_sim_time: float) -> Color:
	var c: Color = sat.enemy_path_gradient_color(current_sim_time)
	c.a = FILL_ALPHA
	return c


# --- Drawing ----------------------------------------------------------

func _draw() -> void:
	for tile: PlacedTile in _tiles:
		_draw_tile(tile)


func _draw_tile(tile: PlacedTile) -> void:
	var live_color: Color
	if tile.hit_flash:
		live_color = HIT_FLASH_COLOR
	elif tile.selected:
		live_color = SELECTED_COLOR
	else:
		live_color = tile.fill
	var scale_factor := _hp_to_scale(tile.hp_frac)
	var origin := tile.origin

	# Y flip: math-y-up shapes vs. screen-y-down draw coords.
	for i in range(tile.geom.subshapes.size()):
		var poly: PackedVector2Array = tile.geom.subshapes[i]
		var centroid: Vector2 = tile.geom.centroids[i]
		# Lost-HP backplate at full size.
		var bg := PackedVector2Array()
		for v: Vector2 in poly:
			bg.append(Vector2(v.x + origin.x, -v.y + origin.y))
		draw_colored_polygon(bg, LOST_HP_COLOR)
		# Outline at full size — drawn between backplate and live fill
		# so the live fill renders crisp on top.
		_draw_outline(bg)
		# Live polygon scaled inward toward the subshape's centroid.
		var live := PackedVector2Array()
		for v in poly:
			var dv := v - centroid
			var s := centroid + dv * scale_factor
			live.append(Vector2(s.x + origin.x, -s.y + origin.y))
		if scale_factor > 0.0:
			draw_colored_polygon(live, live_color)


func _draw_outline(poly: PackedVector2Array) -> void:
	if poly.size() < 2:
		return
	# Single closed-loop draw — uses the per-frame loop counter for
	# segment count; cheap.
	for i in range(poly.size()):
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		draw_line(a, b, OUTLINE_COLOR, OUTLINE_WIDTH)


# --- Click handling ---------------------------------------------------

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			var p := mb.position
			# Walk tiles in reverse so the topmost (most-recently-placed)
			# tile wins ties — matches the visual stacking when rows
			# overlap at their margins.
			for ti in range(_tiles.size() - 1, -1, -1):
				var tile: PlacedTile = _tiles[ti]
				if _hit_test(tile, p):
					_selected_enemy = tile.sat
					enemy_clicked.emit(tile.sat)
					accept_event()
					queue_redraw()
					return


# Point-in-polygon test for any of the tile's subshapes. Uses
# Geometry2D.is_point_in_polygon, which takes a math-y-down polygon —
# our subshapes are math-y-up so we flip y when transforming to screen
# coords (same as _draw).
func _hit_test(tile: PlacedTile, point: Vector2) -> bool:
	for poly: PackedVector2Array in tile.geom.subshapes:
		var screen_poly := PackedVector2Array()
		for v: Vector2 in poly:
			screen_poly.append(Vector2(v.x + tile.origin.x, -v.y + tile.origin.y))
		if Geometry2D.is_point_in_polygon(point, screen_poly):
			return true
	return false


## Currently-inspected enemy (for the upper-right status panel). null
## when no tile has been clicked or when the inspected sat has died.
func selected_enemy() -> Satellite:
	if _selected_enemy != null and is_instance_valid(_selected_enemy) and _selected_enemy.alive:
		return _selected_enemy
	_selected_enemy = null
	return null


## External clear — used when the HUD wants to dismiss the inspector
## (e.g. on planning-mode entry).
func clear_selection() -> void:
	_selected_enemy = null
	queue_redraw()
