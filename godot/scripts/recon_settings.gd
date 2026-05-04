class_name ReconSettings
extends Resource
## Player-editable wave configuration. The Recon tab in the pre-game
## menu and the Settings panel in the in-game pause menu both bind to
## one ReconSettings instance held on PlayerLoadout; Mission.start
## consumes it once per run, so edits made while a mission is in
## progress queue for the next launch rather than rerolling the live
## schedule.
##
## Three wave-unit class presets — alpha / beta / gamma — drive
## per-wave-unit sampling. The Greek labels disambiguate them from
## the *object* mass bands (small / medium / large) that govern
## composition inside one wave-unit; without that split, the same
## "small" word would mean two different things on the same screen.
##
## `waves` is the ordered list of mission waves, each picking some
## number of wave-units of each class.

const WaveUnitClass = preload("res://scripts/wave_unit_class.gd")
const WaveComposition = preload("res://scripts/wave_composition.gd")

const SIZE_ALPHA: int = 0
const SIZE_BETA: int = 1
const SIZE_GAMMA: int = 2

# `@export var foo = StaticFn.call()` fails at parse time in Godot 4
# because the default expression is evaluated before the preloaded
# const's static methods resolve; populate in _init instead so the
# fields still come up filled when a fresh ReconSettings is `.new()`'d.
@export var alpha_class: WaveUnitClass
@export var beta_class: WaveUnitClass
@export var gamma_class: WaveUnitClass
@export var waves: Array[WaveComposition] = []


func _init() -> void:
	if alpha_class == null:
		alpha_class = WaveUnitClass.default_alpha()
	if beta_class == null:
		beta_class = WaveUnitClass.default_beta()
	if gamma_class == null:
		gamma_class = WaveUnitClass.default_gamma()


# Look up the class config for a size-class id. Mission emissions tag
# their target class; the spawn director resolves it through this so
# the dispatch site doesn't switch on int constants.
func class_for(size_class: int) -> WaveUnitClass:
	match size_class:
		SIZE_ALPHA:
			return alpha_class
		SIZE_BETA:
			return beta_class
		_:
			return gamma_class


# Default mission cribbed from the previous hardcoded brief — five
# waves, escalating class mix, last wave randomised. Players can add /
# remove / re-tune waves from here via the Recon editor; this is just
# the "first run after you've never opened the editor" baseline.
static func default_settings() -> ReconSettings:
	var s := ReconSettings.new()
	s.alpha_class = WaveUnitClass.default_alpha()
	s.beta_class = WaveUnitClass.default_beta()
	s.gamma_class = WaveUnitClass.default_gamma()
	# Defaults expressed in game-time hours — at the default time_factor
	# the first wave fires ~30 min in, with subsequent waves spaced ~3 h
	# apart. Comparable feel to the legacy realtime values (3 / 25 / 25
	# / 30 / 30 sec at TF=500 ⇒ ~0.4 h / 3.5 h / 3.5 h / 4.2 h / 4.2 h).
	s.waves = [
		_make_wave(3, 0, 0, 0.25, false, 0.5),
		_make_wave(5, 0, 0, 0.50, false, 3.0),
		_make_wave(4, 4, 0, 0.50, false, 3.0),
		_make_wave(5, 3, 2, 0.60, false, 4.0),
		_make_wave(3, 4, 3, 0.50, true, 4.0),
	]
	return s


# Build a wave with min==max ranges so the default schedule is
# deterministic; the editor gives those ranges a default spread when
# the user first interacts with them. `duration` and `delay` are in
# game-time hours — see WaveComposition for the unit conversion rule.
static func _make_wave(
	alpha_n: int,
	beta_n: int,
	gamma_n: int,
	duration: float,
	randomized: bool,
	delay: float,
) -> WaveComposition:
	var w := WaveComposition.new()
	w.alpha_units = alpha_n
	w.beta_units = beta_n
	w.gamma_units = gamma_n
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
		seed = _make_wave(3, 0, 0, 0.5, false, 3.0)
	else:
		seed = waves[waves.size() - 1].duplicate_composition()
		# Fresh wave starts with a single alpha wave-unit so the row
		# represents a definite addition rather than a duplicate of
		# the previous wave's full composition.
		seed.alpha_units = 1
		seed.beta_units = 0
		seed.gamma_units = 0
	waves.append(seed)
	return seed


func remove_wave_at(idx: int) -> void:
	if idx < 0 or idx >= waves.size():
		return
	waves.remove_at(idx)


func duplicate_settings() -> ReconSettings:
	var s := ReconSettings.new()
	s.alpha_class = alpha_class.duplicate_class()
	s.beta_class = beta_class.duplicate_class()
	s.gamma_class = gamma_class.duplicate_class()
	var copy: Array[WaveComposition] = []
	for w in waves:
		copy.append(w.duplicate_composition())
	s.waves = copy
	return s
