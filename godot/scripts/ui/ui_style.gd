class_name UIStyle
extends RefCounted
## Shared design tokens for the 2D HUD, lifted from the GUI mockup at
## design/mockups/orbital_defense_gui.html (the "GRAVITY/WELL" amber-on-
## near-black palette). Centralises colour, typography, and panel
## construction so individual HUD scripts don't redefine ad-hoc shades.
##
## Only visuals live here. Layout, gameplay flow, and 3D marker colours
## are deliberately left to their owning scripts — the mockup informs
## *appearance*, not behaviour.

# Background ramp. bg_0 is the page; bg_1 fills panel bodies; bg_2
# raises a header strip a half-step; bg_3 is the deepest "well" used
# under bar tracks.
const BG_0 := Color("#06080b")
const BG_1 := Color("#0c1014")
const BG_2 := Color("#131820")
const BG_3 := Color("#1c2330")

# Borders. LINE is the standard 1px panel edge; LINE_SOFT is the
# dashed inner divider used between key/value rows.
const LINE := Color("#2a3442")
const LINE_SOFT := Color("#1a2230")

# Foreground ramp, brightest first. fg_0 = primary readouts; fg_3 =
# tiny uppercase labels above values.
const FG_0 := Color("#e8eef5")
const FG_1 := Color("#aab4c2")
const FG_2 := Color("#6c7686")
const FG_3 := Color("#3f4856")

# Brand accent — a warm amber, used on active nav, panel-title dots,
# selection brackets, and primary-button fills.
const ACCENT := Color("#ffb454")
const ACCENT_DIM := Color("#b8803c")
const ACCENT_SOFT := Color(1.0, 0.706, 0.329, 0.12)  # rgba(255,180,84,0.12)

# Status palette. Used both for chips and as the fill colour of HUD
# bars (energy, weapon cooldown, ready), so the same green that signals
# "good" on a chip also signals "ready to fire" on a laser bar.
const GOOD := Color("#6ee7a8")
const WARN := Color("#ffcc66")
const BAD := Color("#ff5c5c")
const INFO := Color("#6dd0ff")

# Bar track — the dark sliver behind a fill. Slightly translucent so
# the panel below shows through without losing contrast.
const BAR_TRACK := Color(0.04, 0.04, 0.06, 0.85)

# Panel-on-3D-scene tint. The HUD floats over the orbital view, so
# panel bodies fade through to the world rather than reading as opaque
# slabs.
const PANEL_TRANSPARENT := Color(0.047, 0.063, 0.078, 0.85)

# Type ramp (px). Mirrors the mockup's tight scale: tiny uppercase
# labels (LABEL_XS), per-bar readouts (BODY_SM), readouts in panel
# bodies (BODY), titles (TITLE), oversized hero readouts (DISPLAY).
const FONT_LABEL_XS: int = 9
const FONT_BODY_SM: int = 10
const FONT_BODY: int = 11
const FONT_TITLE: int = 12
const FONT_DISPLAY: int = 18


## Build the standard 1px-bordered panel stylebox: sharp corners, deep
## background, hairline edge in --line. The mockup never rounds panel
## corners — sharpness is part of the language.
static func make_panel_stylebox(opaque: bool = false) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = BG_1 if opaque else PANEL_TRANSPARENT
	sb.set_corner_radius_all(0)
	sb.set_border_width_all(1)
	sb.border_color = LINE
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	return sb


## Stylebox for a small "card" — the player roster slot. Same hairline
## border in --line; selected state swaps to ACCENT and brightens the
## fill via ACCENT_SOFT, mirroring the mockup's `.mission-card.selected`.
static func make_card_stylebox(selected: bool, hit: bool = false) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(0)
	sb.set_border_width_all(1)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	if hit:
		sb.bg_color = Color(BAD.r, BAD.g, BAD.b, 0.45)
		sb.border_color = BAD
	elif selected:
		sb.bg_color = ACCENT_SOFT
		sb.border_color = ACCENT
	else:
		sb.bg_color = BG_2
		sb.border_color = LINE
	return sb


## Format a small uppercase label string the way the mockup does
## (`.label-xs`, `.section-h`): all caps, wide tracking. Godot Labels
## don't natively letter-space, so we fake it by inserting a thin space
## between glyphs when `track` is true. Used sparingly — the spacing
## hack costs legibility on tight strings.
static func uppercase_track(s: String) -> String:
	return s.to_upper()
