class_name RunState
extends RefCounted
## All mutable state for a single run: character stats (after meta perks and
## in-run upgrades), the ball bank, and flags set by upgrades.

const BalanceS := preload("res://src/balance.gd")

var character_id := "ranger"

# Combat stats (mutated by upgrades).
var max_hp := 100.0
var hp := 100.0
var dmg := 10.0
var fire_rate := 3.0
var move_speed := 170.0
var crit_chance := 0.05
var crit_mult := BalanceS.CRIT_MULT
var projectiles := 1
var pierce := 0
var bullet_speed := BalanceS.BULLET_SPEED
var bullet_radius := BalanceS.BULLET_RADIUS
var dmg_taken_mult := 1.0
var regen := 0.0

# One-shot / synergy flags.
var second_wind_ready := false
var second_wind_frac := 0.3
var frenzy := false
var frenzy_mult := 1.3
var frenzy_time := 4.0
var momentum := false
var executioner := false
var executioner_mult := 1.25

# Weapon / defense modifiers.
var ricochet := false
var splitshot := false
var hollow_points := false
var thorns := 0.0
var slow_field := false
var kinetic_shield := false

# Dropper / economy modifiers.
var elite_ball_mult := 1.0
var lucky_gates := 0
var gate_hacker := false
var mystery_guaranteed := false
var golden_touch := 0.0
var ball_gravity_mult := 1.0
var ball_restitution_mult := 1.0
var magnet_strength := 0.0

# Discovered synergies (names, prefixed +/- for polarity).
var synergies: Array = []
# Synergies triggered by the latest pick, consumed by the next arena banner.
var pending_synergies: Array = []

# Biome order for this run: one biome per 5-wave segment.
var biomes: Array = ["foundry", "mire", "void"]

# Progress.
var wave := 1
var balls := 0
var bonus_gold := 0
var kills := 0
var elite_kills := 0
var rerolls_this_phase := 0
var picked_upgrades: Array = []
var boss_flawless := true
var autoplay := false


static func build(char_id: String, meta_levels: Dictionary, unlocks: Dictionary) -> RunState:
	## meta_levels: {upgrade_id: level}, unlocks: {unlock_id: true}.
	var run := RunState.new()
	run.character_id = char_id
	var cfg: Dictionary = BalanceS.CHARACTERS.get(char_id, BalanceS.CHARACTERS["ranger"])
	run.max_hp = cfg["hp"]
	run.dmg = cfg["dmg"]
	run.fire_rate = cfg["fire_rate"]
	run.move_speed = cfg["speed"]
	run.crit_chance = cfg["crit"]

	for def: Dictionary in BalanceS.META_UPGRADES:
		var lvl: int = int(meta_levels.get(def["id"], 0))
		if lvl <= 0:
			continue
		var bonus: float = def["per"] * lvl
		match def["id"]:
			"vital":
				run.max_hp += bonus
			"power":
				run.dmg *= 1.0 + bonus
			"rapid":
				run.fire_rate *= 1.0 + bonus
			"swift":
				run.move_speed *= 1.0 + bonus
			"headstart":
				run.balls += int(bonus)
			"bounty":
				run.elite_ball_mult += bonus

	# Character innate perks.
	var innate: Dictionary = cfg.get("innate", {})
	for key: String in innate:
		match key:
			"dmg_taken_mult":
				run.dmg_taken_mult *= float(innate[key])
			"lucky_gates":
				run.lucky_gates += int(innate[key])
			"golden_touch":
				run.golden_touch += float(innate[key])
			"pierce":
				run.pierce += int(innate[key])

	if unlocks.get("mystery", false):
		run.mystery_guaranteed = true
	run.biomes = BalanceS.BIOMES.keys()
	run.biomes.shuffle()
	run.hp = run.max_hp
	return run


func heal_fraction(frac: float) -> void:
	hp = minf(max_hp, hp + max_hp * frac)


func hp_frac() -> float:
	return clampf(hp / maxf(1.0, max_hp), 0.0, 1.0)
