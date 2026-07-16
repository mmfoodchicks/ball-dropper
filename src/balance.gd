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
		"innate": {},
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
		"innate": {},
	},
	"bastion":
	{
		"name": "BASTION",
		"blurb": "Slow, armored, hits like a truck.",
		"hp": 145.0,
		"speed": 148.0,
		"dmg": 14.0,
		"fire_rate": 2.2,
		"crit": 0.04,
		"unlock": "char_bastion",
		"innate": {"dmg_taken_mult": 0.88},
	},
	"jinx":
	{
		"name": "JINX",
		"blurb": "Crit-happy gambler. Gates love her.",
		"hp": 85.0,
		"speed": 172.0,
		"dmg": 9.0,
		"fire_rate": 3.2,
		"crit": 0.15,
		"unlock": "char_jinx",
		"innate": {"lucky_gates": 1, "golden_touch": 0.1},
	},
	"volt":
	{
		"name": "VOLT",
		"blurb": "Innate piercing arc rounds.",
		"hp": 95.0,
		"speed": 165.0,
		"dmg": 11.0,
		"fire_rate": 2.6,
		"crit": 0.06,
		"unlock": "char_volt",
		"innate": {"pierce": 1},
	},
}

# ---------------------------------------------------------------- biomes

## One biome per 5-wave segment; the order is shuffled per run. Each biome
## themes the arena and defines which enemy kinds its waves cycle through.
const BIOMES := {
	"foundry":
	{
		"name": "THE FOUNDRY",
		"tint": Color(1.0, 0.62, 0.3),
		"bg": Color(0.075, 0.055, 0.045),
		"peons": ["scrapper", "sparker", "sentry"],
		"elites": ["crusher", "forgemaster"],
	},
	"mire":
	{
		"name": "THE MIRE",
		"tint": Color(0.55, 0.92, 0.45),
		"bg": Color(0.045, 0.075, 0.05),
		"peons": ["sporeling", "croaker", "mite"],
		"elites": ["spitter", "broodmother"],
	},
	"void":
	{
		"name": "THE VOID",
		"tint": Color(0.62, 0.55, 1.0),
		"bg": Color(0.055, 0.05, 0.095),
		"peons": ["wisp", "blinker", "husk"],
		"elites": ["detonant", "oracle"],
	},
}

## Enemy roster. "class" peon|elite decides ball drops and scaling curve;
## "behavior" picks the AI: chase, weave, hop, turret, blink, charge,
## orbit_ranged, burst_ranged, spawner, shieldcycle, exploder.
const ENEMY_KINDS := {
	# -------- foundry (mechanical)
	"scrapper":
	{
		"class": "peon",
		"behavior": "chase",
		"hp": 8.0,
		"speed": 58.0,
		"dmg": 6.0,
		"radius": 10.0,
		"shape": "circle",
		"color": Color(1.0, 0.45, 0.3),
	},
	"sparker":
	{
		"class": "peon",
		"behavior": "weave",
		"hp": 6.0,
		"speed": 74.0,
		"dmg": 5.0,
		"radius": 8.0,
		"shape": "triangle",
		"color": Color(1.0, 0.8, 0.3),
	},
	"sentry":
	{
		"class": "peon",
		"behavior": "turret",
		"hp": 14.0,
		"speed": 12.0,
		"dmg": 4.0,
		"radius": 11.0,
		"shape": "square",
		"color": Color(0.95, 0.55, 0.25),
		"shot_dmg": 6.0,
		"shot_interval": 2.6,
		"burst": 2,
	},
	"crusher":
	{
		"class": "elite",
		"behavior": "charge",
		"hp": 70.0,
		"speed": 46.0,
		"dmg": 12.0,
		"radius": 16.0,
		"shape": "hex",
		"color": Color(1.0, 0.6, 0.25),
	},
	"forgemaster":
	{
		"class": "elite",
		"behavior": "shieldcycle",
		"hp": 85.0,
		"speed": 40.0,
		"dmg": 14.0,
		"radius": 17.0,
		"shape": "hex",
		"color": Color(0.85, 0.75, 0.65),
		"shield_on": 1.8,
		"shield_off": 3.2,
	},
	# -------- mire (organic)
	"sporeling":
	{
		"class": "peon",
		"behavior": "chase",
		"hp": 9.0,
		"speed": 55.0,
		"dmg": 6.0,
		"radius": 10.0,
		"shape": "circle",
		"color": Color(0.55, 0.9, 0.4),
		"split_into": ["mite", "mite"],
	},
	"mite":
	{
		"class": "peon",
		"behavior": "chase",
		"hp": 3.0,
		"speed": 95.0,
		"dmg": 3.0,
		"radius": 6.0,
		"shape": "circle",
		"color": Color(0.7, 1.0, 0.55),
	},
	"croaker":
	{
		"class": "peon",
		"behavior": "hop",
		"hp": 10.0,
		"speed": 210.0,
		"dmg": 7.0,
		"radius": 11.0,
		"shape": "circle",
		"color": Color(0.35, 0.7, 0.35),
		"hop_time": 0.45,
		"rest_time": 0.75,
	},
	"spitter":
	{
		"class": "elite",
		"behavior": "orbit_ranged",
		"hp": 55.0,
		"speed": 55.0,
		"dmg": 8.0,
		"radius": 13.0,
		"shape": "diamond",
		"color": Color(0.7, 0.55, 0.95),
		"shot_dmg": 8.0,
		"shot_interval": 1.9,
		"burst": 1,
	},
	"broodmother":
	{
		"class": "elite",
		"behavior": "spawner",
		"hp": 95.0,
		"speed": 30.0,
		"dmg": 10.0,
		"radius": 18.0,
		"shape": "hex",
		"color": Color(0.5, 0.8, 0.35),
		"spawn_kind": "mite",
		"spawn_count": 2,
		"spawn_interval": 5.0,
	},
	# -------- void (cosmic)
	"wisp":
	{
		"class": "peon",
		"behavior": "weave",
		"hp": 6.0,
		"speed": 68.0,
		"dmg": 5.0,
		"radius": 8.0,
		"shape": "circle",
		"color": Color(0.6, 0.8, 1.0),
	},
	"blinker":
	{
		"class": "peon",
		"behavior": "blink",
		"hp": 8.0,
		"speed": 30.0,
		"dmg": 6.0,
		"radius": 9.0,
		"shape": "diamond",
		"color": Color(0.75, 0.55, 1.0),
		"blink_interval": 2.2,
		"blink_range": 90.0,
	},
	"husk":
	{
		"class": "peon",
		"behavior": "chase",
		"hp": 18.0,
		"speed": 40.0,
		"dmg": 8.0,
		"radius": 12.0,
		"shape": "square",
		"color": Color(0.45, 0.4, 0.7),
	},
	"detonant":
	{
		"class": "elite",
		"behavior": "exploder",
		"hp": 60.0,
		"speed": 75.0,
		"dmg": 22.0,
		"radius": 14.0,
		"shape": "spike",
		"color": Color(1.0, 0.4, 0.75),
		"fuse_range": 70.0,
		"fuse_time": 0.8,
		"blast_radius": 90.0,
	},
	"oracle":
	{
		"class": "elite",
		"behavior": "burst_ranged",
		"hp": 70.0,
		"speed": 50.0,
		"dmg": 8.0,
		"radius": 14.0,
		"shape": "diamond",
		"color": Color(0.5, 0.7, 1.0),
		"shot_dmg": 8.0,
		"shot_interval": 2.4,
		"burst": 3,
	},
}

const CRIT_MULT := 2.0
const BULLET_SPEED := 430.0
const BULLET_RADIUS := 4.0
const HERO_RADIUS := 12.0
const HERO_IFRAMES := 0.35
const CONTACT_COOLDOWN := 0.8

# ---------------------------------------------------------------- enemies


static func peon_count(wave: int) -> int:
	return int(round(6.0 + 2.4 * wave))


static func elite_count(wave: int) -> int:
	if wave >= BOSS_WAVE:
		return 0
	return mini(6, 1 + int(floor((wave - 1) / 3.0)))


static func enemy_def(kind: String) -> Dictionary:
	return ENEMY_KINDS.get(kind, ENEMY_KINDS["scrapper"])


static func enemy_hp(kind: String, wave: int) -> float:
	var def := enemy_def(kind)
	var growth := 0.32 if def["class"] == "elite" else 0.26
	return float(def["hp"]) * (1.0 + growth * (wave - 1))


static func enemy_speed_scale(wave: int) -> float:
	return minf(1.45, 1.0 + 0.03 * (wave - 1))


static func enemy_shot_dmg(kind: String, wave: int) -> float:
	return float(enemy_def(kind).get("shot_dmg", 8.0)) + 0.5 * wave


static func biome_for_wave(biomes: Array, wave: int) -> Dictionary:
	var idx := clampi(int(floor((wave - 1) / 5.0)), 0, biomes.size() - 1)
	return BIOMES.get(biomes[idx], BIOMES["foundry"])


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
	{
		"id": "char_bastion",
		"name": "Unlock BASTION",
		"desc": "New playable character: armored juggernaut",
		"cost": 6,
	},
	{
		"id": "char_jinx",
		"name": "Unlock JINX",
		"desc": "New playable character: crits, luck and gold",
		"cost": 7,
	},
	{
		"id": "char_volt",
		"name": "Unlock VOLT",
		"desc": "New playable character: innate piercing shots",
		"cost": 9,
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
