class_name ReconSettings
extends Resource
## Player-editable wave configuration. The Recon tab in the pre-game
## menu and the in-game pause-menu Settings panel both bind to one
## ReconSettings instance held on PlayerLoadout; Mission.start consumes
## it once per run, so edits made while a mission is in progress queue
## for the next launch rather than rerolling the live schedule.
##
## Three wave-unit "size class" presets (small / medium / large) drive
## per-wave-unit composition; `waves` is the ordered list of mission
## waves, each picking some number of wave-units from each class.

const WaveUnitClass = preload("res://scripts/wave_unit_class.gd")
const WaveComposition = preload("res://scripts/wave_composition.gd")

const SIZE_SMALL: int = 0
const SIZE_MEDIUM: int = 1
const SIZE_LARGE: int = 2

# `@export var foo = StaticFn.call()` fails at parse time in Godot 4
# because the default expression is evaluated before the preloaded
# const's static methods resolve; populate in _init instead so the
# fields still come up filled when a fresh ReconSettings is `.new()`'d.
@export var small_class: WaveUnitClass
@export var medium_class: WaveUnitClass
@export var large_class: WaveUnitClass
@export var waves: Array[WaveComposition] = []


func _init() -> void:
	if small_class == null:
		small_class = WaveUnitClass.default_small()
	if medium_class == null:
		medium_class = WaveUnitClass.default_medium()
	if large_class == null:
		large_class = WaveUnitClass.default_large()


# Look up the class config for a size-class id. Mission emissions tag
# their target class; the spawn director resolves it through this so
# the dispatch site doesn't switch on int constants.
func class_for(size_class: int) -> WaveUnitClass:
	match size_class:
		SIZE_SMALL:
			return small_class
		SIZE_MEDIUM:
			return medium_class
		_:
			return large_class


# Default mission cribbed from the previous hardcoded brief — five
# waves, escalating size-class mix, last wave randomised. Players can
# add / remove / re-tune waves from here via the Recon editor; this is
# just the "first run after you've never opened the editor" baseline.
static func default_settings() -> ReconSettings:
	var s := ReconSettings.new()
	s.small_class = WaveUnitClass.default_small()
	s.medium_class = WaveUnitClass.default_medium()
	s.large_class = WaveUnitClass.default_large()
	s.waves = [
		_make_wave(3, 0, 0, 2.0, false, 3.0),
		_make_wave(5, 0, 0, 4.0, false, 25.0),
		_make_wave(4, 4, 0, 3.5, false, 25.0),
		_make_wave(5, 3, 2, 4.5, false, 30.0),
		_make_wave(3, 4, 3, 4.0, true, 30.0),
	]
	return s


# Build a wave with min==max ranges so the default schedule is
# deterministic; the editor gives those ranges a default spread when
# the user first interacts with them.
static func _make_wave(
	small_n: int,
	medium_n: int,
	large_n: int,
	duration: float,
	randomized: bool,
	delay: float,
) -> WaveComposition:
	var w := WaveComposition.new()
	w.small_units = small_n
	w.medium_units = medium_n
	w.large_units = large_n
	w.duration_min = duration
	w.duration_max = duration
	w.randomized = randomized
	w.delay_min = delay
	w.delay_max = delay
	return w


# Append a fresh wave to the end of the list. The new wave inherits
# the last wave's pacing (duration, delay) so the user can grow the
# mission without re-tuning every field.
func add_wave() -> WaveComposition:
	var seed: WaveComposition
	if waves.is_empty():
		seed = _make_wave(3, 0, 0, 4.0, false, 25.0)
	else:
		seed = waves[waves.size() - 1].duplicate_composition()
		# Fresh wave starts with a single small wave-unit so the row
		# represents a definite addition rather than a duplicate of
		# the previous wave's full composition.
		seed.small_units = 1
		seed.medium_units = 0
		seed.large_units = 0
	waves.append(seed)
	return seed


func remove_wave_at(idx: int) -> void:
	if idx < 0 or idx >= waves.size():
		return
	waves.remove_at(idx)


func duplicate_settings() -> ReconSettings:
	var s := ReconSettings.new()
	s.small_class = small_class.duplicate_class()
	s.medium_class = medium_class.duplicate_class()
	s.large_class = large_class.duplicate_class()
	var copy: Array[WaveComposition] = []
	for w in waves:
		copy.append(w.duplicate_composition())
	s.waves = copy
	return s
