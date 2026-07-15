class_name Balance
extends RefCounted
## Every tuning knob in the game lives here so design iteration is one-file.
## Formulas follow the GDD scaling targets: balls per elite go from dozens
## (early waves) to hundreds (mid) to thousands+ (late).

# ---------------------------------------------------------------- arena / waves

const DESIGN_W := 480.0
const DESIGN_H := 854.0
const ARENA_RECT := Rect2(14.0, 84.0, 452.0, 756.0)

const WAVE_COUNT := 15
const BOSS_WAVE := 15
const DROPPER_WAVES: Array[int] = [5, 10]
const WAVE_HEAL_PCT := 0.15
const WAVE_BANNER_TIME := 1.8
const ALIVE_CAP := 30
const SPAWN_INTERVAL := 1.1
const SPAWN_BATCH := 4
const SPAWN_INITIAL_FRAC := 0.35

# ---------------------------------------------------------------- characters

const CHARACTERS := {
	"ranger":
	{
		"name": "RANGER",
		"blurb": "Balanced all-rounder.",
		"hp": 100.0,
		"speed": 170.0,
		"dmg": 10.0,
		"fire_rate": 3.0,
		"crit": 0.05,
		"unlock": "",
	},
	"blitz":
	{
		"name": "BLITZ",
		"blurb": "Fast and fragile. Sprays bullets.",
		"hp": 80.0,
		"speed": 195.0,
		"dmg": 6.0,
		"fire_rate": 5.5,
		"crit": 0.08,
		"unlock": "char_blitz",
	},
}

const CRIT_MULT := 2.0
const BULLET_SPEED := 430.0
const BULLET_RADIUS := 4.0
const HERO_RADIUS := 12.0
const HERO_IFRAMES := 0.35
const CONTACT_COOLDOWN := 0.8
const SECOND_WIND_HP_FRAC := 0.3

# ---------------------------------------------------------------- enemies


static func peon_count(wave: int) -> int:
	return int(round(6.0 + 2.4 * wave))


static func elite_count(wave: int) -> int:
	if wave >= BOSS_WAVE:
		return 0
	return mini(6, 1 + int(floor((wave - 1) / 3.0)))


static func peon_hp(wave: int) -> float:
	return 8.0 * (1.0 + 0.26 * (wave - 1))


static func peon_speed(wave: int) -> float:
	return minf(105.0, 58.0 + 1.8 * wave)


static func brute_hp(wave: int) -> float:
	return 70.0 * (1.0 + 0.32 * (wave - 1))


static func spitter_hp(wave: int) -> float:
	return 55.0 * (1.0 + 0.30 * (wave - 1))


static func spitter_shot_dmg(wave: int) -> float:
	return 8.0 + 0.5 * wave


const PEON_DMG := 6.0
const BRUTE_DMG := 12.0
const SPITTER_CONTACT_DMG := 8.0
const ENEMY_BULLET_SPEED := 210.0


## Balls dropped by one elite. GDD: dozens early, hundreds mid, thousands late
## (per wave in aggregate). Scales with wave number.
static func elite_ball_drop(wave: int, bounty_mult: float) -> int:
	return int(round((8.0 + 2.0 * wave) * pow(float(wave), 1.15) * bounty_mult))


# ---------------------------------------------------------------- boss

const BOSS_HP := 1900.0
const BOSS_RADIUS := 34.0
const BOSS_SPEED := 55.0
const BOSS_CONTACT_DMG := 18.0
const BOSS_BULLET_DMG := 10.0
const BOSS_BALL_DROP := 6000
const BOSS_PHASE2_FRAC := 0.7
const BOSS_PHASE3_FRAC := 0.35
const HAZARD_RADIUS := 64.0
const HAZARD_WARN_TIME := 1.0
const HAZARD_ACTIVE_TIME := 2.5
const HAZARD_DPS := 14.0

# ---------------------------------------------------------------- dropper board

const BOARD_LEFT := 16.0
const BOARD_RIGHT := 464.0
const BOARD_TOP := 100.0
const BOARD_EXIT_Y := 812.0
const DROP_Y := 118.0
const BALL_RADIUS := 5.0
const GRAVITY := 1500.0
const WALL_RESTITUTION := 0.6
const LINE_RESTITUTION := 0.55
const MAX_BALL_SPEED := 900.0
const MAX_SIM_BALLS := 420
const DROP_RATE := 38.0
const BOARD_TIMEOUT := 40.0
const GATE_W := 74.0
const GATE_H := 26.0

## value -> weight. Higher multipliers are rarer (and boards place them in
## riskier spots). x1 is a deliberate dud.
const MULT_WEIGHTS := [
	[1, 8], [2, 26], [3, 22], [4, 14], [5, 10], [6, 8], [7, 4], [8, 4], [9, 2], [10, 2]
]

## Subtractor counters -1 .. -15, biased to the middle of the range.
const SUB_WEIGHTS := [3, 4, 6, 8, 9, 9, 8, 7, 6, 5, 4, 3, 2, 2, 1]

## ??? gate effect weights.
const MYSTERY_WEIGHTS := {
	"mult": 30, "sub": 15, "split": 20, "teleport": 15, "gold": 10, "buff": 10
}
const MYSTERY_CHANCE := 0.55
const MYSTERY_BUFF_TIME := 4.0

# ---------------------------------------------------------------- economy


static func reroll_cost(wave: int, rerolls_used: int) -> int:
	var base := 30 if wave <= 5 else 150
	return base * int(pow(2.0, rerolls_used))


static func defeat_gold(wave: int, balls: int) -> int:
	return wave * 12 + int(balls * 0.05)


static func victory_gold(balls: int, hp_frac: float, golden_touch: float) -> int:
	var conversion := int(balls * 0.10 * (1.0 + golden_touch))
	var perf := int(round(200.0 * clampf(hp_frac, 0.0, 1.0)))
	return WAVE_COUNT * 12 + 300 + conversion + perf


static func victory_materials(flawless_boss: bool) -> int:
	return 4 if flawless_boss else 3


# ---------------------------------------------------------------- meta shop

const META_UPGRADES := [
	{
		"id": "vital",
		"name": "Vitality",
		"desc": "+12 Max HP per level",
		"max": 10,
		"base_cost": 100,
		"growth": 1.55,
		"per": 12.0,
	},
	{
		"id": "power",
		"name": "Power",
		"desc": "+8% Damage per level",
		"max": 10,
		"base_cost": 120,
		"growth": 1.6,
		"per": 0.08,
	},
	{
		"id": "rapid",
		"name": "Rapid Fire",
		"desc": "+6% Fire Rate per level",
		"max": 8,
		"base_cost": 120,
		"growth": 1.6,
		"per": 0.06,
	},
	{
		"id": "swift",
		"name": "Swiftness",
		"desc": "+4% Move Speed per level",
		"max": 6,
		"base_cost": 90,
		"growth": 1.5,
		"per": 0.04,
	},
	{
		"id": "headstart",
		"name": "Head Start",
		"desc": "+40 starting Balls per level",
		"max": 10,
		"base_cost": 80,
		"growth": 1.5,
		"per": 40.0,
	},
	{
		"id": "bounty",
		"name": "Elite Bounty",
		"desc": "+12% Balls from elites per level",
		"max": 10,
		"base_cost": 110,
		"growth": 1.6,
		"per": 0.12,
	},
]

const META_UNLOCKS := [
	{
		"id": "mystery",
		"name": "Mystery Magnet",
		"desc": "A ??? gate spawns on every dropper board",
		"cost": 3,
	},
	{
		"id": "fourth",
		"name": "Wider Choice",
		"desc": "Upgrade phases offer 4 options instead of 3",
		"cost": 5,
	},
	{
		"id": "char_blitz",
		"name": "Unlock BLITZ",
		"desc": "New playable character: fast, fragile, bullet hose",
		"cost": 8,
	},
]


static func meta_cost(def: Dictionary, level: int) -> int:
	return int(round(def["base_cost"] * pow(def["growth"], level)))


# ---------------------------------------------------------------- helpers


static func fmt(n: int) -> String:
	## Compact number formatting for big ball banks: 1.2K, 3.4M ...
	var neg := n < 0
	var v := absi(n)
	var out: String
	if v < 1000:
		out = str(v)
	elif v < 1000000:
		out = _fmt_scaled(v, 1000.0, "K")
	elif v < 1000000000:
		out = _fmt_scaled(v, 1000000.0, "M")
	else:
		out = _fmt_scaled(v, 1000000000.0, "B")
	return ("-" + out) if neg else out


static func _fmt_scaled(v: int, div: float, suffix: String) -> String:
	var x := v / div
	if x >= 100.0:
		return "%d%s" % [int(round(x)), suffix]
	return "%.1f%s" % [x, suffix]


static func pick_weighted(rng: RandomNumberGenerator, pairs: Array) -> Variant:
	## pairs: Array of [value, weight]. Returns the picked value.
	var total := 0
	for p: Array in pairs:
		total += int(p[1])
	var roll := rng.randi_range(1, maxi(1, total))
	for p: Array in pairs:
		roll -= int(p[1])
		if roll <= 0:
			return p[0]
	return pairs[pairs.size() - 1][0]
