class_name UpgradePool
extends RefCounted
## In-run upgrade pool. GDD categories: weapon modifications, passive stat
## boosts, utility abilities, dropper modifiers, synergy-based upgrades.
## Player is offered 3 (4 with the "Wider Choice" unlock), picks 1, and can
## reroll for an escalating ball cost.

const POOL := [
	# -------- weapon modifications
	{
		"id": "multishot",
		"name": "Multishot",
		"desc": "+1 projectile per shot",
		"cat": "weapon",
		"weight": 6,
		"max_stacks": 3,
	},
	{
		"id": "pierce",
		"name": "Piercing Rounds",
		"desc": "Bullets pierce +1 enemy",
		"cat": "weapon",
		"weight": 8,
		"max_stacks": 3,
	},
	{
		"id": "heavy",
		"name": "Heavy Caliber",
		"desc": "+25% damage, -5% fire rate",
		"cat": "weapon",
		"weight": 10,
		"max_stacks": 0,
	},
	{
		"id": "rapid",
		"name": "Hair Trigger",
		"desc": "+20% fire rate",
		"cat": "weapon",
		"weight": 10,
		"max_stacks": 0,
	},
	{
		"id": "sharpshooter",
		"name": "Sharpshooter",
		"desc": "+12% critical chance",
		"cat": "weapon",
		"weight": 8,
		"max_stacks": 0,
	},
	{
		"id": "big_bullets",
		"name": "Big Bullets",
		"desc": "+40% bullet size, +10% damage",
		"cat": "weapon",
		"weight": 8,
		"max_stacks": 2,
	},
	# -------- passive stat boosts
	{
		"id": "vitality",
		"name": "Vitality",
		"desc": "+25 max HP and heal 25 HP",
		"cat": "passive",
		"weight": 10,
		"max_stacks": 0,
	},
	{
		"id": "swift",
		"name": "Swift Boots",
		"desc": "+12% movement speed",
		"cat": "passive",
		"weight": 9,
		"max_stacks": 0,
	},
	{
		"id": "deadly",
		"name": "Deadly Precision",
		"desc": "Critical hits deal +75% more",
		"cat": "passive",
		"weight": 7,
		"max_stacks": 2,
	},
	{
		"id": "adrenaline",
		"name": "Adrenaline",
		"desc": "+8% fire rate, +6% speed",
		"cat": "passive",
		"weight": 8,
		"max_stacks": 0,
	},
	# -------- utility abilities
	{
		"id": "regen",
		"name": "Regeneration",
		"desc": "Recover 1.5 HP per second",
		"cat": "utility",
		"weight": 7,
		"max_stacks": 2,
	},
	{
		"id": "bulwark",
		"name": "Bulwark",
		"desc": "Take 15% less damage",
		"cat": "utility",
		"weight": 7,
		"max_stacks": 2,
	},
	{
		"id": "second_wind",
		"name": "Second Wind",
		"desc": "Revive once per run at 30% HP",
		"cat": "utility",
		"weight": 4,
		"max_stacks": 1,
	},
	# -------- dropper modifiers
	{
		"id": "hoarder",
		"name": "Ball Hoarder",
		"desc": "Elites drop +30% more balls",
		"cat": "dropper",
		"weight": 9,
		"max_stacks": 0,
	},
	{
		"id": "lucky",
		"name": "Lucky Gates",
		"desc": "Higher multipliers appear more often",
		"cat": "dropper",
		"weight": 6,
		"max_stacks": 2,
	},
	{
		"id": "hacker",
		"name": "Gate Hacker",
		"desc": "Subtractor gate counters are halved",
		"cat": "dropper",
		"weight": 5,
		"max_stacks": 1,
	},
	{
		"id": "mystery_plus",
		"name": "Mystery Magnet",
		"desc": "A ??? gate spawns on every board",
		"cat": "dropper",
		"weight": 4,
		"max_stacks": 1,
	},
	{
		"id": "golden",
		"name": "Golden Touch",
		"desc": "+15% gold from end-of-run balls",
		"cat": "dropper",
		"weight": 6,
		"max_stacks": 2,
	},
	# -------- synergy-based
	{
		"id": "frenzy",
		"name": "Frenzy",
		"desc": "Elite kills: +30% fire rate for 4s",
		"cat": "synergy",
		"weight": 5,
		"max_stacks": 1,
	},
	{
		"id": "momentum",
		"name": "Momentum",
		"desc": "+20% damage while moving",
		"cat": "synergy",
		"weight": 6,
		"max_stacks": 1,
	},
	{
		"id": "executioner",
		"name": "Executioner",
		"desc": "+25% damage to elites; they explode",
		"cat": "synergy",
		"weight": 5,
		"max_stacks": 1,
	},
]

const CATEGORY_NAMES := {
	"weapon": "WEAPON",
	"passive": "PASSIVE",
	"utility": "UTILITY",
	"dropper": "DROPPER",
	"synergy": "SYNERGY",
}


static func find(id: String) -> Dictionary:
	for def: Dictionary in POOL:
		if def["id"] == id:
			return def
	return {}


static func stacks_of(run, id: String) -> int:
	var n := 0
	for picked: String in run.picked_upgrades:
		if picked == id:
			n += 1
	return n


static func eligible(run, def: Dictionary) -> bool:
	var max_stacks := int(def["max_stacks"])
	if max_stacks > 0 and stacks_of(run, str(def["id"])) >= max_stacks:
		return false
	# Redundant offers.
	if def["id"] == "mystery_plus" and run.mystery_guaranteed:
		return false
	if def["id"] == "second_wind" and run.second_wind_ready:
		return false
	return true


static func roll_offer(rng: RandomNumberGenerator, run, count: int) -> Array:
	## Weighted sample without replacement from the eligible pool.
	var candidates: Array = []
	for def: Dictionary in POOL:
		if eligible(run, def):
			candidates.append(def)
	var offer: Array = []
	while offer.size() < count and not candidates.is_empty():
		var total := 0
		for def: Dictionary in candidates:
			total += int(def["weight"])
		var roll := rng.randi_range(1, maxi(1, total))
		for i in candidates.size():
			roll -= int(candidates[i]["weight"])
			if roll <= 0:
				offer.append(candidates[i])
				candidates.remove_at(i)
				break
	return offer


static func apply(run, id: String) -> void:
	run.picked_upgrades.append(id)
	match id:
		"multishot":
			run.projectiles += 1
		"pierce":
			run.pierce += 1
		"heavy":
			run.dmg *= 1.25
			run.fire_rate *= 0.95
		"rapid":
			run.fire_rate *= 1.2
		"sharpshooter":
			run.crit_chance += 0.12
		"big_bullets":
			run.bullet_radius *= 1.4
			run.dmg *= 1.1
		"vitality":
			run.max_hp += 25.0
			run.hp = minf(run.max_hp, run.hp + 25.0)
		"swift":
			run.move_speed *= 1.12
		"deadly":
			run.crit_mult += 0.75
		"adrenaline":
			run.fire_rate *= 1.08
			run.move_speed *= 1.06
		"regen":
			run.regen += 1.5
		"bulwark":
			run.dmg_taken_mult *= 0.85
		"second_wind":
			run.second_wind_ready = true
		"hoarder":
			run.elite_ball_mult += 0.3
		"lucky":
			run.lucky_gates += 1
		"hacker":
			run.gate_hacker = true
		"mystery_plus":
			run.mystery_guaranteed = true
		"golden":
			run.golden_touch += 0.15
		"frenzy":
			run.frenzy = true
		"momentum":
			run.momentum = true
		"executioner":
			run.executioner = true
