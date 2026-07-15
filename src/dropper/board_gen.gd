class_name BoardGen
extends RefCounted
## Procedural dropper boards + the shared ball physics step.
##
## GDD rules implemented here:
##  - no pegs; only gates and angled guiding physics lines
##  - multiplier gates x1..x10, weighted so high values are rare
##  - subtractor gates -1..-15 with depleting counters
##  - bounceback gates on lower rows
##  - rare ??? gate (guaranteed with the right unlock/upgrade)
##  - high multipliers get "guard" lines so they are riskier to reach
##  - fairness: boards are validated with a phantom-ball sim before play;
##    generation retries and finally falls back to a safe sparse layout.

const BalanceS := preload("res://src/balance.gd")

const LINE_HALF_THICKNESS := 3.0
const VALIDATE_BALLS := 9
const VALIDATE_TIME := 8.0
const VALIDATE_MIN_EXITS := 3
const GEN_ATTEMPTS := 6

# ---------------------------------------------------------------- generation


static func generate_validated(rng: RandomNumberGenerator, opts: Dictionary) -> Dictionary:
	for attempt in GEN_ATTEMPTS:
		var board := generate(rng, opts)
		if validate(board):
			return board
	# Fallback: gates without any lines can never trap a ball.
	var safe := generate(rng, opts)
	safe["lines"] = []
	return safe


static func generate(rng: RandomNumberGenerator, opts: Dictionary) -> Dictionary:
	var lucky := int(opts.get("lucky", 0))
	var hacker := bool(opts.get("hacker", false))
	var mystery_guaranteed := bool(opts.get("mystery", false))

	var gates: Array = []
	var next_id := 0

	# Slot grid: 3 / 2 / 3 gates per row. The middle row is offset half a
	# column and jitter is wide, so straight falls rarely thread multiple
	# gates in a perfect vertical chain.
	var rows: Array = []
	var row_ys := [255.0, 415.0, 575.0]
	for i in row_ys.size():
		var y: float = row_ys[i] + rng.randf_range(-14.0, 14.0)
		var slots: Array = []
		if i == 1:
			for x in [155.0, 325.0]:
				slots.append(Vector2(x + rng.randf_range(-30.0, 30.0), y))
		else:
			for x in [90.0, 240.0, 390.0]:
				slots.append(Vector2(x + rng.randf_range(-30.0, 30.0), y))
		rows.append(slots)

	# Decide gate types. Bouncebacks only on rows 1-2 so a bounced ball has
	# multiplier gates above it to re-enter (GDD: balls can pass gates again
	# after bouncing, once per ball).
	var all_slots: Array = []
	for i in rows.size():
		for slot: Vector2 in rows[i]:
			all_slots.append({"pos": slot, "row": i})
	_shuffle(rng, all_slots)

	var bounce_budget := 1 if rng.randf() < 0.45 else 2
	var sub_budget := 2 if rng.randf() < 0.6 else 3
	var mystery_budget := 0
	if mystery_guaranteed or rng.randf() < BalanceS.MYSTERY_CHANCE:
		mystery_budget = 1
	# Non-multiplier budgets may never squeeze multipliers below 3
	# (GDD: the board must always offer meaningful reward paths).
	sub_budget = mini(sub_budget, all_slots.size() - 3 - bounce_budget - mystery_budget)

	for slot: Dictionary in all_slots:
		var kind := "mult"
		if bounce_budget > 0 and int(slot["row"]) >= 1:
			kind = "bounce"
			bounce_budget -= 1
		elif mystery_budget > 0:
			kind = "myst"
			mystery_budget -= 1
		elif sub_budget > 0:
			kind = "sub"
			sub_budget -= 1
		var gate := _make_gate(rng, next_id, kind, slot["pos"], lucky, hacker)
		gate["row"] = slot["row"]
		gates.append(gate)
		next_id += 1

	_cap_vertical_chains(gates)

	# Guiding physics lines: random angled bars between the gate rows.
	var lines: Array = []
	var bands := [
		Vector2(165.0, 235.0), Vector2(300.0, 390.0), Vector2(460.0, 550.0), Vector2(620.0, 700.0)
	]
	var line_count := rng.randi_range(4, 6)
	for i in line_count:
		var seg := _random_line(rng, bands[rng.randi_range(0, bands.size() - 1)], gates)
		if not seg.is_empty():
			lines.append(seg)

	# Risk/reward: guard the approach to high multipliers with a deflector.
	for gate: Dictionary in gates:
		if gate["type"] == "mult" and int(gate["value"]) >= 6:
			var guard := _guard_line(rng, gate, gates)
			if not guard.is_empty():
				lines.append(guard)

	return {"gates": gates, "lines": lines}


static func _cap_vertical_chains(gates: Array) -> void:
	## Near-aligned multiplier gates on different rows can both be hit by the
	## same falling ball; cap the pair's product so a focused stream lands a
	## satisfying jackpot instead of an economy-breaking x40+.
	for i in gates.size():
		for j in range(i + 1, gates.size()):
			var top: Dictionary = gates[i]
			var bottom: Dictionary = gates[j]
			if top["type"] != "mult" or bottom["type"] != "mult":
				continue
			if top["row"] == bottom["row"]:
				continue
			if absf(top["x"] - bottom["x"]) >= 46.0:
				continue
			while int(top["value"]) * int(bottom["value"]) > 12:
				var big: Dictionary = top if int(top["value"]) >= int(bottom["value"]) else bottom
				big["value"] = int(big["value"]) - 1
				big["base_value"] = big["value"]


static func _make_gate(
	rng: RandomNumberGenerator, id: int, kind: String, pos: Vector2, lucky: int, hacker: bool
) -> Dictionary:
	var gate := {
		"id": id,
		"type": kind,
		"x": pos.x,
		"y": pos.y,
		"w": BalanceS.GATE_W,
		"h": BalanceS.GATE_H,
		"value": 0,
		"base_value": 0,
		"counter": 0,
		"active": true,
		"flash": 0.0,
	}
	match kind:
		"mult":
			# "Lucky Gates" rerolls the value and keeps the best.
			var v := int(BalanceS.pick_weighted(rng, BalanceS.MULT_WEIGHTS))
			for i in lucky:
				v = maxi(v, int(BalanceS.pick_weighted(rng, BalanceS.MULT_WEIGHTS)))
			gate["value"] = v
			gate["base_value"] = v
		"sub":
			var pairs: Array = []
			for i in BalanceS.SUB_WEIGHTS.size():
				pairs.append([i + 1, BalanceS.SUB_WEIGHTS[i]])
			var counter := int(BalanceS.pick_weighted(rng, pairs))
			if hacker:
				counter = maxi(1, int(ceil(counter / 2.0)))
			gate["counter"] = counter
			gate["value"] = counter
	return gate


static func _random_line(rng: RandomNumberGenerator, band: Vector2, gates: Array) -> Dictionary:
	for attempt in 25:
		var cx := rng.randf_range(70.0, 410.0)
		var cy := rng.randf_range(band.x, band.y)
		var ang := rng.randf_range(0.2, 0.65) * (1.0 if rng.randf() < 0.5 else -1.0)
		var half := rng.randf_range(45.0, 85.0)
		var dir := Vector2.from_angle(ang)
		var a := Vector2(cx, cy) - dir * half
		var b := Vector2(cx, cy) + dir * half
		if _line_ok(a, b, gates):
			return {"a": a, "b": b}
	return {}


static func _guard_line(rng: RandomNumberGenerator, gate: Dictionary, gates: Array) -> Dictionary:
	var side := 1.0 if rng.randf() < 0.5 else -1.0
	var ang := side * rng.randf_range(0.55, 0.85)
	var dir := Vector2.from_angle(ang)
	var center := Vector2(gate["x"] - side * 36.0, gate["y"] - 52.0)
	var a := center - dir * 34.0
	var b := center + dir * 34.0
	if _line_ok(a, b, gates):
		return {"a": a, "b": b}
	return {}


static func _line_ok(a: Vector2, b: Vector2, gates: Array) -> bool:
	var margin := 26.0
	if a.x < BalanceS.BOARD_LEFT + 20.0 or a.x > BalanceS.BOARD_RIGHT - 20.0:
		return false
	if b.x < BalanceS.BOARD_LEFT + 20.0 or b.x > BalanceS.BOARD_RIGHT - 20.0:
		return false
	for gate: Dictionary in gates:
		var rect := gate_rect(gate).grow(margin)
		for i in 6:
			var p := a.lerp(b, i / 5.0)
			if rect.has_point(p):
				return false
	return true


static func _shuffle(rng: RandomNumberGenerator, arr: Array) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp


# ---------------------------------------------------------------- physics


static func gate_rect(gate: Dictionary) -> Rect2:
	return Rect2(gate["x"] - gate["w"] * 0.5, gate["y"] - gate["h"] * 0.5, gate["w"], gate["h"])


static func make_ball(pos: Vector2, vel: Vector2, value: int) -> Dictionary:
	return {
		"pos": pos,
		"vel": vel,
		"val": value,
		"bounced": false,
		"triggered": {},
		"stuck_t": 0.0,
		"nudges": 0,
		"ignore_lines": false,
		"done": false,
		"dead": false,
	}


static func step_ball(ball: Dictionary, board: Dictionary, dt: float) -> void:
	## Integrates one ball for dt (call with substeps). Gates are sensors and
	## are handled by the caller; this only does gravity, walls and lines.
	var vel: Vector2 = ball["vel"]
	vel.y += BalanceS.GRAVITY * dt
	vel = vel.limit_length(BalanceS.MAX_BALL_SPEED)
	var pos: Vector2 = ball["pos"] + vel * dt
	var r := BalanceS.BALL_RADIUS

	# Side walls.
	if pos.x - r < BalanceS.BOARD_LEFT:
		pos.x = BalanceS.BOARD_LEFT + r
		vel.x = absf(vel.x) * BalanceS.WALL_RESTITUTION
	elif pos.x + r > BalanceS.BOARD_RIGHT:
		pos.x = BalanceS.BOARD_RIGHT - r
		vel.x = -absf(vel.x) * BalanceS.WALL_RESTITUTION
	# Soft ceiling so bounced balls stay on screen.
	if pos.y - r < BalanceS.BOARD_TOP - 26.0:
		pos.y = BalanceS.BOARD_TOP - 26.0 + r
		vel.y = absf(vel.y) * 0.3

	if not ball["ignore_lines"]:
		for seg: Dictionary in board["lines"]:
			var cp := closest_point_on_segment(pos, seg["a"], seg["b"])
			var d := pos.distance_to(cp)
			var min_d := r + LINE_HALF_THICKNESS
			if d < min_d:
				var n := (pos - cp) / maxf(d, 0.001)
				pos = cp + n * min_d
				var vn := vel.dot(n)
				if vn < 0.0:
					vel -= n * vn * (1.0 + BalanceS.LINE_RESTITUTION)
					vel *= 0.99

	ball["pos"] = pos
	ball["vel"] = vel


static func closest_point_on_segment(p: Vector2, a: Vector2, b: Vector2) -> Vector2:
	var ab := b - a
	var len2 := ab.length_squared()
	if len2 < 0.0001:
		return a
	var t := clampf((p - a).dot(ab) / len2, 0.0, 1.0)
	return a + ab * t


# ---------------------------------------------------------------- validation


static func validate(board: Dictionary) -> bool:
	## GDD fairness rule: board generation validates solvability before play.
	## Phantom balls (ignoring gate effects, which never block motion anyway)
	## must reach the exit from several drop positions.
	var exits := 0
	for i in VALIDATE_BALLS:
		var x := lerpf(40.0, 440.0, i / float(VALIDATE_BALLS - 1))
		var ball := make_ball(Vector2(x, BalanceS.DROP_Y), Vector2.ZERO, 1)
		var t := 0.0
		var dt := 1.0 / 60.0
		while t < VALIDATE_TIME:
			t += dt
			for s in 2:
				step_ball(ball, board, dt * 0.5)
			anti_stuck(ball, dt)
			if ball["pos"].y > BalanceS.BOARD_EXIT_Y:
				exits += 1
				break
	return exits >= VALIDATE_MIN_EXITS


static func anti_stuck(ball: Dictionary, dt: float) -> void:
	## Shared stuck detection: slow balls get a nudge, chronic ones fall
	## through lines. Guarantees every drop resolves (GDD fairness).
	if ball["vel"].length() < 18.0:
		ball["stuck_t"] += dt
	else:
		ball["stuck_t"] = 0.0
	if ball["stuck_t"] > 1.0:
		ball["stuck_t"] = 0.0
		ball["nudges"] += 1
		var side := 1.0 if fmod(ball["pos"].x, 2.0) < 1.0 else -1.0
		ball["vel"] += Vector2(side * 90.0, -160.0)
		if ball["nudges"] > 3:
			ball["ignore_lines"] = true
