extends SceneTree
## Headless verification suite (no rendering, no autoloads needed):
##
##     godot --headless --path . --script res://tests/smoke.gd
##
## Covers the pure-logic layer: balance formulas, board generation +
## fairness validation, ball physics termination, the upgrade pool and the
## meta save. The full game loop (combat -> dropper -> upgrades -> boss ->
## victory) is verified end-to-end with the autoplay bot:
##
##     godot --headless --path . -- --autoplay --god --turbo --quit-on-end
##
## which prints AUTOPLAY_RESULT json and exits 0 on a completed run.

const BalanceS := preload("res://src/balance.gd")
const BoardGenS := preload("res://src/dropper/board_gen.gd")
const UpgradePoolS := preload("res://src/upgrades.gd")
const RunStateS := preload("res://src/run_state.gd")
const MetaS := preload("res://src/autoload/meta.gd")

var checks := 0
var fails := 0


func _init() -> void:
	_test_balance()
	_test_content()
	_test_boards()
	_test_physics()
	_test_upgrades()
	_test_synergies()
	_test_meta()
	print("SMOKE: %d checks, %d failures" % [checks, fails])
	quit(1 if fails > 0 else 0)


func _check(cond: bool, msg: String) -> void:
	checks += 1
	if not cond:
		fails += 1
		printerr("FAIL: %s" % msg)


# ---------------------------------------------------------------- balance


func _test_balance() -> void:
	_check(
		BalanceS.enemy_hp("scrapper", 10) > BalanceS.enemy_hp("scrapper", 1),
		"peon hp scales with wave"
	)
	_check(
		BalanceS.enemy_hp("crusher", 10) > BalanceS.enemy_hp("crusher", 1),
		"elite hp scales with wave"
	)
	_check(BalanceS.peon_count(14) > BalanceS.peon_count(1), "peon count scales")
	_check(BalanceS.elite_count(1) == 1, "wave 1 has one elite (first dropper is funded)")
	_check(BalanceS.elite_count(15) == 0, "boss wave has no regular elites")
	for w in range(1, 15):
		_check(BalanceS.elite_count(w) <= 6, "elite count capped (wave %d)" % w)

	# GDD scaling: dozens early, hundreds mid, thousands late (aggregate).
	var w1 := BalanceS.elite_ball_drop(1, 1.0)
	var w5 := BalanceS.elite_ball_drop(5, 1.0)
	var w10 := BalanceS.elite_ball_drop(10, 1.0)
	var w14 := BalanceS.elite_ball_drop(14, 1.0)
	_check(w1 >= 8 and w1 <= 40, "wave-1 elite drops dozens (%d)" % w1)
	_check(w5 >= 90 and w5 <= 250, "wave-5 elite drops ~hundreds (%d)" % w5)
	_check(w10 >= 300, "wave-10 elite drops hundreds+ (%d)" % w10)
	_check(w14 * 5 >= 3000, "wave-14 wave total is thousands (%d)" % (w14 * 5))
	_check(BalanceS.elite_ball_drop(5, 1.3) > w5, "bounty multiplier increases drops")

	_check(BalanceS.fmt(999) == "999", "fmt small")
	_check(BalanceS.fmt(1200) == "1.2K", "fmt K (%s)" % BalanceS.fmt(1200))
	_check(BalanceS.fmt(2500000) == "2.5M", "fmt M (%s)" % BalanceS.fmt(2500000))
	_check(BalanceS.fmt(150000) == "150K", "fmt 150K (%s)" % BalanceS.fmt(150000))
	_check(BalanceS.fmt(-1200) == "-1.2K", "fmt negative")

	_check(BalanceS.reroll_cost(5, 0) == 30, "reroll base cost wave 5")
	_check(BalanceS.reroll_cost(5, 2) == 120, "reroll cost doubles")
	_check(BalanceS.reroll_cost(10, 1) == 300, "reroll cost wave 10")

	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 200:
		var v := int(BalanceS.pick_weighted(rng, BalanceS.MULT_WEIGHTS))
		_check(v >= 1 and v <= 10, "mult weight pick in range")
		if fails > 0:
			break

	_check(
		BalanceS.victory_gold(1000, 1.0, 0.0) > BalanceS.defeat_gold(14, 1000),
		"victory pays better than defeat"
	)
	for def: Dictionary in BalanceS.META_UPGRADES:
		_check(
			BalanceS.meta_cost(def, 3) > BalanceS.meta_cost(def, 0),
			"meta cost grows: %s" % def["id"]
		)


# ---------------------------------------------------------------- content


func _test_content() -> void:
	# Biomes reference real enemy kinds of the right class.
	_check(BalanceS.BIOMES.size() >= 3, "3+ biomes")
	for biome_id: String in BalanceS.BIOMES:
		var biome: Dictionary = BalanceS.BIOMES[biome_id]
		_check(biome["peons"].size() >= 3, "%s has 3+ peon kinds" % biome_id)
		_check(biome["elites"].size() >= 2, "%s has 2+ elite kinds" % biome_id)
		for k in biome["peons"]:
			_check(BalanceS.ENEMY_KINDS.has(k), "%s: peon kind exists: %s" % [biome_id, k])
			_check(BalanceS.ENEMY_KINDS[k]["class"] == "peon", "%s is peon-class" % k)
		for k in biome["elites"]:
			_check(BalanceS.ENEMY_KINDS.has(k), "%s: elite kind exists: %s" % [biome_id, k])
			_check(BalanceS.ENEMY_KINDS[k]["class"] == "elite", "%s is elite-class" % k)
	_check(BalanceS.ENEMY_KINDS.size() >= 15, "15+ enemy kinds")
	for kind: String in BalanceS.ENEMY_KINDS:
		var d: Dictionary = BalanceS.ENEMY_KINDS[kind]
		_check(d["class"] == "peon" or d["class"] == "elite", "class valid: %s" % kind)
		_check(BalanceS.enemy_hp(kind, 10) > BalanceS.enemy_hp(kind, 1), "hp scales: %s" % kind)
		for c in d.get("split_into", []):
			_check(BalanceS.ENEMY_KINDS.has(c), "split child exists: %s" % c)
		if d.has("spawn_kind"):
			_check(BalanceS.ENEMY_KINDS.has(d["spawn_kind"]), "spawn child exists: %s" % kind)

	# Characters and their unlocks.
	_check(BalanceS.CHARACTERS.size() >= 5, "5+ playable characters")
	var unlock_ids := {}
	for u: Dictionary in BalanceS.META_UNLOCKS:
		unlock_ids[u["id"]] = true
	for cid: String in BalanceS.CHARACTERS:
		var req: String = BalanceS.CHARACTERS[cid]["unlock"]
		_check(req == "" or unlock_ids.has(req), "character unlock purchasable: %s" % cid)
	var volt = RunStateS.build("volt", {}, {})
	_check(volt.pierce == 1, "volt innate pierce")
	var bastion = RunStateS.build("bastion", {}, {})
	_check(bastion.dmg_taken_mult < 1.0, "bastion innate armor")
	var any_run = RunStateS.build("ranger", {}, {})
	_check(any_run.biomes.size() == BalanceS.BIOMES.size(), "run gets a full biome order")
	for b in any_run.biomes:
		_check(BalanceS.BIOMES.has(b), "run biome exists: %s" % b)


# ---------------------------------------------------------------- boards


func _test_boards() -> void:
	var option_sets := [
		{},
		{"lucky": 2},
		{"hacker": true},
		{"mystery": true},
		{"lucky": 1, "hacker": true, "mystery": true},
	]
	for seed_i in 40:
		var opts: Dictionary = option_sets[seed_i % option_sets.size()]
		var rng := RandomNumberGenerator.new()
		rng.seed = 1000 + seed_i
		var board := BoardGenS.generate_validated(rng, opts)
		_board_invariants(board, opts, seed_i)

	# Determinism: same seed + opts -> identical board.
	var rng_a := RandomNumberGenerator.new()
	rng_a.seed = 42
	var rng_b := RandomNumberGenerator.new()
	rng_b.seed = 42
	var a := BoardGenS.generate_validated(rng_a, {})
	var b := BoardGenS.generate_validated(rng_b, {})
	_check(JSON.stringify(a) == JSON.stringify(b), "board generation is seed-deterministic")


func _board_invariants(board: Dictionary, opts: Dictionary, seed_i: int) -> void:
	var tag := "seed %d" % seed_i
	var gates: Array = board["gates"]
	var lines: Array = board["lines"]
	_check(gates.size() >= 8, "%s: at least 8 gates" % tag)

	var mult_n := 0
	var bounce_n := 0
	var myst_n := 0
	for gate: Dictionary in gates:
		match gate["type"]:
			"mult":
				mult_n += 1
				var v := int(gate["value"])
				_check(v >= 1 and v <= 10, "%s: mult value 1..10" % tag)
			"sub":
				var c := int(gate["counter"])
				var cap := 8 if bool(opts.get("hacker", false)) else 15
				_check(c >= 1 and c <= cap, "%s: sub counter 1..%d (got %d)" % [tag, cap, c])
			"bounce":
				bounce_n += 1
				_check(gate["y"] > 350.0, "%s: bounceback sits on a lower row" % tag)
			"myst":
				myst_n += 1
	_check(mult_n >= 3, "%s: at least 3 multiplier gates" % tag)
	_check(bounce_n >= 1 and bounce_n <= 2, "%s: 1-2 bounceback gates" % tag)
	if bool(opts.get("mystery", false)):
		_check(myst_n == 1, "%s: mystery guaranteed spawns" % tag)

	# Gates never overlap each other.
	for i in gates.size():
		for j in range(i + 1, gates.size()):
			var ri := BoardGenS.gate_rect(gates[i])
			var rj := BoardGenS.gate_rect(gates[j])
			_check(not ri.intersects(rj), "%s: gates %d/%d overlap" % [tag, i, j])

	# Lines stay inside walls and clear of gates.
	for seg: Dictionary in lines:
		for p_name in ["a", "b"]:
			var p: Vector2 = seg[p_name]
			_check(
				p.x >= BalanceS.BOARD_LEFT + 18.0 and p.x <= BalanceS.BOARD_RIGHT - 18.0,
				"%s: line endpoint inside walls" % tag
			)
		for gate: Dictionary in gates:
			var rect := BoardGenS.gate_rect(gate).grow(18.0)
			for k in 6:
				var p: Vector2 = seg["a"].lerp(seg["b"], k / 5.0)
				_check(not rect.has_point(p), "%s: line clears gates" % tag)

	# GDD fairness: the played board always validates.
	_check(BoardGenS.validate(board), "%s: board passes solvability validation" % tag)


# ---------------------------------------------------------------- physics


func _test_physics() -> void:
	# Free fall reaches the exit fast on an open board.
	var open_board := {"gates": [], "lines": []}
	var ball := BoardGenS.make_ball(Vector2(240.0, BalanceS.DROP_Y), Vector2.ZERO, 1)
	var t := 0.0
	while t < 2.5 and ball["pos"].y <= BalanceS.BOARD_EXIT_Y:
		t += 1.0 / 60.0
		for s in 3:
			BoardGenS.step_ball(ball, open_board, 1.0 / 180.0)
	_check(ball["pos"].y > BalanceS.BOARD_EXIT_Y, "free-fall ball exits in <2.5s")

	# Walls contain a fast sideways ball.
	var wild := BoardGenS.make_ball(Vector2(240.0, 300.0), Vector2(800.0, -200.0), 1)
	var contained := true
	for i in 300:
		BoardGenS.step_ball(wild, open_board, 1.0 / 60.0)
		var x: float = wild["pos"].x
		if x < BalanceS.BOARD_LEFT or x > BalanceS.BOARD_RIGHT:
			contained = false
			break
	_check(contained, "walls contain fast balls")

	# closest_point_on_segment basics.
	var a := Vector2(0, 0)
	var b := Vector2(10, 0)
	_check(
		BoardGenS.closest_point_on_segment(Vector2(5, 5), a, b) == Vector2(5, 0),
		"segment closest point (middle)"
	)
	_check(
		BoardGenS.closest_point_on_segment(Vector2(-4, 2), a, b) == Vector2(0, 0),
		"segment closest point (clamped)"
	)

	# A V-shaped trap cannot hold a ball forever (anti-stuck fairness).
	var trap := {
		"gates": [],
		"lines":
		[
			{"a": Vector2(160.0, 500.0), "b": Vector2(240.0, 560.0)},
			{"a": Vector2(320.0, 500.0), "b": Vector2(240.0, 560.0)},
		],
	}
	var trapped := BoardGenS.make_ball(Vector2(240.0, 400.0), Vector2.ZERO, 1)
	var escape_t := 0.0
	while escape_t < 15.0 and trapped["pos"].y <= BalanceS.BOARD_EXIT_Y:
		escape_t += 1.0 / 60.0
		for s in 3:
			BoardGenS.step_ball(trapped, trap, 1.0 / 180.0)
		BoardGenS.anti_stuck(trapped, 1.0 / 60.0)
	_check(trapped["pos"].y > BalanceS.BOARD_EXIT_Y, "V-trap ball escapes via anti-stuck")


# ---------------------------------------------------------------- upgrades


func _test_upgrades() -> void:
	var base = RunStateS.build("ranger", {}, {})
	var cfg: Dictionary = BalanceS.CHARACTERS["ranger"]
	_check(base.max_hp == cfg["hp"], "base hp matches character")
	_check(base.dmg == cfg["dmg"], "base dmg matches character")

	# Meta perks land on the run.
	var perked = RunStateS.build("ranger", {"vital": 2, "headstart": 3}, {"mystery": true})
	_check(perked.max_hp == cfg["hp"] + 24.0, "vitality meta adds hp")
	_check(perked.balls == 120, "head start meta adds balls")
	_check(perked.mystery_guaranteed, "mystery unlock flags the run")

	# Every pool entry applies cleanly and is recorded.
	var ids := {}
	for def: Dictionary in UpgradePoolS.POOL:
		var id := str(def["id"])
		_check(not ids.has(id), "upgrade ids unique: %s" % id)
		ids[id] = true
		var run = RunStateS.build("ranger", {}, {})
		UpgradePoolS.apply(run, id)
		_check(run.picked_upgrades == [id], "apply records pick: %s" % id)
		_check(UpgradePoolS.CATEGORY_NAMES.has(str(def["cat"])), "category known: %s" % id)

	var run = RunStateS.build("ranger", {}, {})
	UpgradePoolS.apply(run, "heavy")
	_check(absf(run.dmg - 12.5) < 0.001, "heavy caliber math")
	UpgradePoolS.apply(run, "multishot")
	_check(run.projectiles == 2, "multishot adds projectile")

	# Offers: correct size, no duplicates, eligibility respected.
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var sw = RunStateS.build("ranger", {}, {})
	UpgradePoolS.apply(sw, "second_wind")
	UpgradePoolS.apply(sw, "multishot")
	UpgradePoolS.apply(sw, "multishot")
	UpgradePoolS.apply(sw, "multishot")
	for i in 120:
		var offer := UpgradePoolS.roll_offer(rng, sw, 3)
		_check(offer.size() == 3, "offer size 3")
		var seen := {}
		for def: Dictionary in offer:
			var id := str(def["id"])
			_check(not seen.has(id), "offer has no duplicates")
			seen[id] = true
			_check(id != "second_wind", "one-time upgrade not re-offered")
			_check(id != "multishot", "capped stack not re-offered")
		if fails > 0:
			break


# ---------------------------------------------------------------- synergies


func _test_synergies() -> void:
	_check(UpgradePoolS.POOL.size() >= 34, "pool has 34+ upgrades (%d)" % UpgradePoolS.POOL.size())
	var ids := {}
	for def: Dictionary in UpgradePoolS.POOL:
		ids[def["id"]] = true
	var names := {}
	var goods := 0
	var bads := 0
	for rule: Dictionary in UpgradePoolS.SYNERGIES:
		_check(ids.has(rule["a"]), "synergy '%s': a exists" % rule["id"])
		_check(ids.has(rule["b"]), "synergy '%s': b exists" % rule["id"])
		_check(rule["a"] != rule["b"], "synergy '%s': not a self-pair" % rule["id"])
		_check(not names.has(rule["name"]), "synergy names unique: %s" % rule["name"])
		names[rule["name"]] = true
		if rule["good"]:
			goods += 1
		else:
			bads += 1
	_check(goods >= 6 and bads >= 6, "both polarities present (%d good / %d bad)" % [goods, bads])

	# Completing a pair triggers exactly once and applies its effect.
	var run = RunStateS.build("ranger", {}, {})
	var t1: Array = UpgradePoolS.apply(run, "multishot")
	_check(t1.is_empty(), "no synergy on first pick")
	var before: int = run.projectiles
	var t2: Array = UpgradePoolS.apply(run, "flak")
	_check(t2.size() == 1 and t2[0]["id"] == "bullet_storm", "bullet storm triggers")
	_check(run.projectiles == before + 3, "flak +2 plus synergy +1 projectiles")
	_check(run.synergies.size() == 1, "synergy recorded on the run")
	var t3: Array = UpgradePoolS.apply(run, "multishot")
	_check(t3.is_empty(), "synergy never retriggers")

	# Negative polarity path.
	var run2 = RunStateS.build("ranger", {}, {})
	UpgradePoolS.apply(run2, "titan_frame")
	var spd: float = run2.move_speed
	var t4: Array = UpgradePoolS.apply(run2, "swift")
	_check(t4.size() == 1 and not t4[0]["good"], "bulky (negative) triggers")
	_check(run2.move_speed < spd * 1.12, "bulky dampens swift boots")

	# Offer hint.
	var run3 = RunStateS.build("ranger", {}, {})
	UpgradePoolS.apply(run3, "pierce")
	_check(UpgradePoolS.would_synergize(run3, "ricochet"), "hint detects completing pick")
	_check(not UpgradePoolS.would_synergize(run3, "vitality"), "no false hint")


# ---------------------------------------------------------------- meta save


func _test_meta() -> void:
	var path := "user://smoke_test_save.json"
	var m = MetaS.new()
	m.save_path = path
	m.gold = 1000
	m.materials = 10
	_check(m.buy_upgrade("vital"), "can buy vitality")
	_check(m.gold == 900, "gold deducted (%d)" % m.gold)
	_check(m.upgrade_level("vital") == 1, "level recorded")
	_check(m.buy_unlock("mystery"), "can buy unlock")
	_check(m.materials == 7, "materials deducted")
	_check(not m.buy_unlock("mystery"), "cannot re-buy unlock")
	_check(not m.character_available("blitz"), "blitz locked by default")
	m.unlocks["char_blitz"] = true
	_check(m.character_available("blitz"), "blitz unlocks via material unlock")
	m.record_run(9, false)
	m.save()

	var m2 = MetaS.new()
	m2.save_path = path
	m2.load_save()
	_check(m2.gold == 900, "save roundtrip: gold")
	_check(m2.upgrade_level("vital") == 1, "save roundtrip: upgrade level")
	_check(m2.has_unlock("mystery"), "save roundtrip: unlock")
	_check(m2.best_wave == 9, "save roundtrip: best wave")

	m2.wipe()
	_check(m2.gold == 0 and m2.upgrade_levels.is_empty(), "wipe clears state")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	m.free()
	m2.free()
