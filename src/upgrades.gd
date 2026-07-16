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
	{
		"id": "ricochet",
		"name": "Ricochet",
		"desc": "Bullets bounce off walls once",
		"cat": "weapon",
		"weight": 7,
		"max_stacks": 1,
	},
	{
		"id": "splitshot",
		"name": "Splitshot",
		"desc": "Hits burst into two weak shards",
		"cat": "weapon",
		"weight": 6,
		"max_stacks": 1,
	},
	{
		"id": "cannonball",
		"name": "Cannonball",
		"desc": "+60% damage, -25% fire rate, slower shots",
		"cat": "weapon",
		"weight": 7,
		"max_stacks": 0,
	},
	{
		"id": "hollow_points",
		"name": "Hollow Points",
		"desc": "+30% damage to full-health enemies",
		"cat": "weapon",
		"weight": 7,
		"max_stacks": 1,
	},
	{
		"id": "flak",
		"name": "Flak Loader",
		"desc": "+2 projectiles, -30% damage",
		"cat": "weapon",
		"weight": 5,
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
	{
		"id": "glass_cannon",
		"name": "Glass Cannon",
		"desc": "+50% damage, -30% max HP",
		"cat": "passive",
		"weight": 5,
		"max_stacks": 1,
	},
	{
		"id": "titan_frame",
		"name": "Titan Frame",
		"desc": "+40 max HP, -8% move speed",
		"cat": "passive",
		"weight": 7,
		"max_stacks": 0,
	},
	{
		"id": "overclock",
		"name": "Overclock",
		"desc": "+25% fire rate, take +10% damage",
		"cat": "passive",
		"weight": 6,
		"max_stacks": 2,
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
	{
		"id": "thorns",
		"name": "Thorns",
		"desc": "Attackers take 15 damage on contact",
		"cat": "utility",
		"weight": 7,
		"max_stacks": 2,
	},
	{
		"id": "static_field",
		"name": "Static Field",
		"desc": "Nearby enemies move 25% slower",
		"cat": "utility",
		"weight": 6,
		"max_stacks": 1,
	},
	{
		"id": "kinetic_shield",
		"name": "Kinetic Shield",
		"desc": "Block one hit every 4s undamaged",
		"cat": "utility",
		"weight": 5,
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
	{
		"id": "heavy_balls",
		"name": "Heavy Balls",
		"desc": "Balls fall faster and bounce less",
		"cat": "dropper",
		"weight": 5,
		"max_stacks": 1,
	},
	{
		"id": "rubber_balls",
		"name": "Rubber Balls",
		"desc": "Balls bounce wildly off everything",
		"cat": "dropper",
		"weight": 5,
		"max_stacks": 1,
	},
	{
		"id": "magnet_gates",
		"name": "Magnet Gates",
		"desc": "Gates pull nearby balls toward them",
		"cat": "dropper",
		"weight": 5,
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

## Isaac-style pairwise interactions: owning both upgrades triggers a hidden
## bonus (good) or drawback (bad) the moment the pair completes. Offer cards
## only hint "◆ SYNERGY?" — polarity is discovered by committing.
const SYNERGIES := [
	# -------- positive
	{
		"id": "bullet_storm",
		"a": "multishot",
		"b": "flak",
		"good": true,
		"name": "BULLET STORM",
		"desc": "+1 extra projectile",
	},
	{
		"id": "pinball",
		"a": "pierce",
		"b": "ricochet",
		"good": true,
		"name": "PINBALL WIZARD",
		"desc": "+1 extra pierce",
	},
	{
		"id": "overdrive",
		"a": "frenzy",
		"b": "adrenaline",
		"good": true,
		"name": "OVERDRIVE",
		"desc": "Frenzy lasts 7s",
	},
	{
		"id": "siege",
		"a": "heavy",
		"b": "cannonball",
		"good": true,
		"name": "SIEGE MODE",
		"desc": "+20% more damage",
	},
	{
		"id": "deadeye",
		"a": "sharpshooter",
		"b": "glass_cannon",
		"good": true,
		"name": "DEADEYE",
		"desc": "+12% crit chance",
	},
	{
		"id": "cull",
		"a": "hollow_points",
		"b": "executioner",
		"good": true,
		"name": "CULL THE STRONG",
		"desc": "Elites take +50% damage",
	},
	{
		"id": "iron_maiden",
		"a": "thorns",
		"b": "bulwark",
		"good": true,
		"name": "IRON MAIDEN",
		"desc": "Thorns damage doubled",
	},
	{
		"id": "jackpot",
		"a": "lucky",
		"b": "rubber_balls",
		"good": true,
		"name": "JACKPOT PHYSICS",
		"desc": "??? gate on every board",
	},
	# -------- negative
	{
		"id": "jammed",
		"a": "cannonball",
		"b": "rapid",
		"good": false,
		"name": "JAMMED MECHANISM",
		"desc": "-10% fire rate",
	},
	{
		"id": "fragile_hope",
		"a": "glass_cannon",
		"b": "second_wind",
		"good": false,
		"name": "FRAGILE HOPE",
		"desc": "Revive at 15% HP instead",
	},
	{
		"id": "confused_physics",
		"a": "heavy_balls",
		"b": "rubber_balls",
		"good": false,
		"name": "CONFUSED PHYSICS",
		"desc": "Both ball mods weakened",
	},
	{
		"id": "shrapnel_chaos",
		"a": "ricochet",
		"b": "splitshot",
		"good": false,
		"name": "SHRAPNEL CHAOS",
		"desc": "-10% damage",
	},
	{
		"id": "overheat",
		"a": "overclock",
		"b": "adrenaline",
		"good": false,
		"name": "OVERHEAT",
		"desc": "Take +8% more damage",
	},
	{
		"id": "power_drain",
		"a": "static_field",
		"b": "frenzy",
		"good": false,
		"name": "POWER DRAIN",
		"desc": "Frenzy bonus weakened",
	},
	{
		"id": "bulky",
		"a": "titan_frame",
		"b": "swift",
		"good": false,
		"name": "BULKY",
		"desc": "-6% move speed",
	},
	{
		"id": "polarity_clash",
		"a": "magnet_gates",
		"b": "hacker",
		"good": false,
		"name": "POLARITY CLASH",
		"desc": "Magnet pull halved",
	},
]


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


static func would_synergize(run, id: String) -> bool:
	## True if picking `id` would complete any not-yet-triggered synergy pair.
	for rule: Dictionary in SYNERGIES:
		var a := str(rule["a"])
		var b := str(rule["b"])
		var completes: bool = (
			(id == a and b in run.picked_upgrades) or (id == b and a in run.picked_upgrades)
		)
		if completes and not _synergy_tag(rule) in run.synergies:
			return true
	return false


static func _synergy_tag(rule: Dictionary) -> String:
	return ("+" if rule["good"] else "-") + str(rule["name"])


static func apply(run, id: String) -> Array:
	## Applies the upgrade, then resolves any synergy pairs it completes.
	## Returns the triggered synergy rules (empty most of the time).
	run.picked_upgrades.append(id)
	_apply_effect(run, id)
	var triggered: Array = []
	for rule: Dictionary in SYNERGIES:
		var a := str(rule["a"])
		var b := str(rule["b"])
		var completes: bool = (
			(id == a and b in run.picked_upgrades) or (id == b and a in run.picked_upgrades)
		)
		if not completes:
			continue
		var tag := _synergy_tag(rule)
		if tag in run.synergies:
			continue
		run.synergies.append(tag)
		_apply_synergy(run, str(rule["id"]))
		triggered.append(rule)
	return triggered


static func _apply_synergy(run, rule_id: String) -> void:
	match rule_id:
		"bullet_storm":
			run.projectiles += 1
		"pinball":
			run.pierce += 1
		"overdrive":
			run.frenzy_time = 7.0
		"siege":
			run.dmg *= 1.2
		"deadeye":
			run.crit_chance += 0.12
		"cull":
			run.executioner_mult = 1.5
		"iron_maiden":
			run.thorns *= 2.0
		"jackpot":
			run.mystery_guaranteed = true
		"jammed":
			run.fire_rate *= 0.9
		"fragile_hope":
			run.second_wind_frac = 0.15
		"confused_physics":
			run.ball_gravity_mult = lerpf(run.ball_gravity_mult, 1.0, 0.5)
			run.ball_restitution_mult = lerpf(run.ball_restitution_mult, 1.0, 0.5)
		"shrapnel_chaos":
			run.dmg *= 0.9
		"overheat":
			run.dmg_taken_mult *= 1.08
		"power_drain":
			run.frenzy_mult = 1.15
		"bulky":
			run.move_speed *= 0.94
		"polarity_clash":
			run.magnet_strength *= 0.5


static func _apply_effect(run, id: String) -> void:
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
		"ricochet":
			run.ricochet = true
		"splitshot":
			run.splitshot = true
		"cannonball":
			run.dmg *= 1.6
			run.fire_rate *= 0.75
			run.bullet_speed *= 0.8
		"hollow_points":
			run.hollow_points = true
		"flak":
			run.projectiles += 2
			run.dmg *= 0.7
		"glass_cannon":
			run.dmg *= 1.5
			run.max_hp *= 0.7
			run.hp = minf(run.hp, run.max_hp)
		"titan_frame":
			run.max_hp += 40.0
			run.hp = minf(run.max_hp, run.hp + 40.0)
			run.move_speed *= 0.92
		"overclock":
			run.fire_rate *= 1.25
			run.dmg_taken_mult *= 1.1
		"thorns":
			run.thorns += 15.0
		"static_field":
			run.slow_field = true
		"kinetic_shield":
			run.kinetic_shield = true
		"heavy_balls":
			run.ball_gravity_mult *= 1.25
			run.ball_restitution_mult *= 0.7
		"rubber_balls":
			run.ball_restitution_mult *= 1.35
		"magnet_gates":
			run.magnet_strength += 140.0
