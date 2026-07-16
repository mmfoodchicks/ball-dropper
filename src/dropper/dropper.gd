extends Node2D
## Dropper phase controller (every 5 waves). The whole ball bank is streamed
## into a validated procedural board; gates multiply, delete, bounce or
## scramble balls. Big banks are simulated as "chunks": each visual ball
## carries the value of several real balls so thousands stay smooth, while
## subtractor gates still delete in units of real balls.

signal finished(result)

const BalanceS := preload("res://src/balance.gd")
const BoardGenS := preload("res://src/dropper/board_gen.gd")
const FxS := preload("res://src/fx/fx.gd")

var run = null
var external_stepping := false

var rng := RandomNumberGenerator.new()
var board := {}
var balls: Array = []
var fx = null

var phase := "aim"
var aim_x := 240.0
var started_bank := 0
var queue_left := 0
var chunk := 1
var collected := 0
var gold_bonus := 0
var buff_t := 0.0

var _spawn_acc := 0.0
var _timeout := 0.0
var _settle_t := 0.0
var _auto_t := 0.0
var _finished_emitted := false

# Per-frame sfx aggregation to avoid 400 simultaneous blips.
var _evt := {}
# Balls created mid-iteration (??? gate splits) join the sim next tick.
var _pending_balls: Array = []


func _ready() -> void:
	rng.randomize()
	board = (
		BoardGenS
		. generate_validated(
			rng,
			{
				"lucky": run.lucky_gates,
				"hacker": run.gate_hacker,
				"mystery": run.mystery_guaranteed,
			}
		)
	)
	# Upgrade-driven physics overrides (heavy/rubber balls).
	board["phys"] = {
		"g": BalanceS.GRAVITY * run.ball_gravity_mult,
		"wall": clampf(BalanceS.WALL_RESTITUTION * run.ball_restitution_mult, 0.2, 0.92),
		"line": clampf(BalanceS.LINE_RESTITUTION * run.ball_restitution_mult, 0.2, 0.92),
	}
	fx = FxS.new()
	fx.z_index = 10
	add_child(fx)


func _physics_process(delta: float) -> void:
	if not external_stepping:
		step(delta)


func begin_drop() -> void:
	if phase != "aim":
		return
	phase = "dropping"
	started_bank = run.balls
	queue_left = started_bank
	chunk = maxi(1, int(ceil(started_bank / float(BalanceS.MAX_SIM_BALLS))))
	run.balls = 0
	_timeout = BalanceS.BOARD_TIMEOUT
	Sfx.play("drop_start")


func set_aim(x: float) -> void:
	aim_x = clampf(x, 40.0, 440.0)


# ---------------------------------------------------------------- stepping


func step(dt: float) -> void:
	fx.step(dt)
	_evt = {}
	for gate: Dictionary in board["gates"]:
		gate["flash"] = maxf(0.0, gate["flash"] - dt * 4.0)
	_step_buff(dt)
	if run.autoplay and phase == "aim":
		_auto_t += dt
		set_aim(_auto_aim_x())
		if _auto_t > 0.4:
			begin_drop()
	if phase == "dropping":
		_spawn_tick(dt)
		_physics_tick(dt)
		_timeout -= dt
		if _timeout <= 0.0:
			for ball: Dictionary in balls:
				collected += int(ball["val"])
			balls.clear()
			queue_left = 0
		if queue_left <= 0 and balls.is_empty():
			phase = "settled"
			_settle_t = 0.9
	elif phase == "settled":
		_settle_t -= dt
		if _settle_t <= 0.0 and not _finished_emitted:
			_finished_emitted = true
			finished.emit(result())
	_play_events()
	queue_redraw()


func result() -> Dictionary:
	var mult := 0.0
	if started_bank > 0:
		mult = collected / float(started_bank)
	return {"start": started_bank, "final": collected, "gold": gold_bonus, "mult": mult}


func status() -> Dictionary:
	var in_flight := queue_left
	for ball: Dictionary in balls:
		in_flight += int(ball["val"])
	return {
		"phase": phase,
		"start": started_bank,
		"in_flight": in_flight,
		"collected": collected,
	}


func _spawn_tick(dt: float) -> void:
	if queue_left <= 0:
		return
	_spawn_acc += BalanceS.DROP_RATE * dt
	while _spawn_acc >= 1.0 and queue_left > 0:
		_spawn_acc -= 1.0
		if balls.size() >= BalanceS.MAX_SIM_BALLS:
			return
		var value := mini(chunk, queue_left)
		queue_left -= value
		var pos := Vector2(aim_x + rng.randf_range(-26.0, 26.0), BalanceS.DROP_Y)
		var vel := Vector2(rng.randf_range(-60.0, 60.0), rng.randf_range(20.0, 60.0))
		balls.append(BoardGenS.make_ball(pos, vel, value))


func _physics_tick(dt: float) -> void:
	var keep: Array = []
	for ball: Dictionary in balls:
		if run.magnet_strength > 0.0:
			_apply_magnet(ball, dt)
		var sub_dt := dt / 3.0
		for s in 3:
			BoardGenS.step_ball(ball, board, sub_dt)
		BoardGenS.anti_stuck(ball, dt)
		_check_gates(ball)
		if ball["dead"]:
			continue
		if ball["pos"].y > BalanceS.BOARD_EXIT_Y:
			collected += int(ball["val"])
			_evt["tick"] = int(_evt.get("tick", 0)) + 1
			continue
		keep.append(ball)
	balls = keep
	if not _pending_balls.is_empty():
		balls.append_array(_pending_balls)
		_pending_balls.clear()


func _apply_magnet(ball: Dictionary, dt: float) -> void:
	## Magnet Gates upgrade: active gates pull nearby balls toward themselves
	## — multipliers and subtractors alike. Double-edged by design.
	var pos: Vector2 = ball["pos"]
	var best_d := 80.0
	var pull := Vector2.ZERO
	for gate: Dictionary in board["gates"]:
		if not gate["active"]:
			continue
		var gp := Vector2(gate["x"], gate["y"])
		var d := pos.distance_to(gp)
		if d < best_d and d > 4.0:
			best_d = d
			pull = (gp - pos).normalized() * run.magnet_strength
	if pull != Vector2.ZERO:
		ball["vel"] += pull * dt


func _step_buff(dt: float) -> void:
	if buff_t <= 0.0:
		return
	buff_t -= dt
	if buff_t <= 0.0:
		for gate: Dictionary in board["gates"]:
			if gate["type"] == "mult":
				gate["value"] = gate["base_value"]


# ---------------------------------------------------------------- gates


func _check_gates(ball: Dictionary) -> void:
	for gate: Dictionary in board["gates"]:
		if not gate["active"]:
			continue
		var id: int = gate["id"]
		if ball["triggered"].has(id):
			continue
		if not BoardGenS.gate_rect(gate).grow(4.0).has_point(ball["pos"]):
			continue
		ball["triggered"][id] = true
		gate["flash"] = 1.0
		match gate["type"]:
			"mult":
				_apply_mult(ball, gate)
			"sub":
				_apply_sub(ball, gate)
			"bounce":
				_apply_bounce(ball)
			"myst":
				_apply_mystery(ball, gate)
		if ball["dead"]:
			return


func _apply_mult(ball: Dictionary, gate: Dictionary) -> void:
	var v := int(gate["value"])
	ball["val"] = int(ball["val"]) * v
	_evt["mult"] = maxi(int(_evt.get("mult", 0)), v)
	if v >= 5:
		fx.floater(ball["pos"] + Vector2(0, -12), "x%d!" % v, Color(0.45, 1.0, 0.6), 15)


func _apply_sub(ball: Dictionary, gate: Dictionary) -> void:
	var take := mini(int(gate["counter"]), int(ball["val"]))
	ball["val"] = int(ball["val"]) - take
	gate["counter"] = int(gate["counter"]) - take
	_evt["sub"] = true
	if gate["counter"] <= 0:
		gate["active"] = false
		fx.floater(Vector2(gate["x"], gate["y"] - 18.0), "DEPLETED", Color(0.7, 0.7, 0.75), 12)
	if ball["val"] <= 0:
		ball["dead"] = true
		fx.burst(ball["pos"], Color(1.0, 0.4, 0.4), 5, 80.0)


func _apply_bounce(ball: Dictionary) -> void:
	## Each ball can only be bounced once (GDD: prevents infinite loops).
	## A bounced ball may pass through gates again, so clear its trigger set.
	if ball["bounced"]:
		return
	ball["bounced"] = true
	ball["triggered"] = {}
	ball["vel"] = Vector2(rng.randf_range(-240.0, 240.0), -rng.randf_range(520.0, 760.0))
	_evt["bounce"] = true


func _apply_mystery(ball: Dictionary, gate: Dictionary) -> void:
	_evt["myst"] = true
	var pairs: Array = []
	for key: String in BalanceS.MYSTERY_WEIGHTS:
		pairs.append([key, BalanceS.MYSTERY_WEIGHTS[key]])
	var effect := str(BalanceS.pick_weighted(rng, pairs))
	var pos: Vector2 = ball["pos"]
	match effect:
		"mult":
			var v := rng.randi_range(2, 8)
			ball["val"] = int(ball["val"]) * v
			fx.floater(pos, "? x%d" % v, Color(1.0, 0.85, 0.35), 15)
		"sub":
			var s := mini(rng.randi_range(3, 10), int(ball["val"]))
			ball["val"] = int(ball["val"]) - s
			fx.floater(pos, "? -%d" % s, Color(1.0, 0.5, 0.4), 15)
			if ball["val"] <= 0:
				ball["dead"] = true
		"split":
			if balls.size() < BalanceS.MAX_SIM_BALLS + 60 and int(ball["val"]) >= 2:
				var half := int(ball["val"]) / 2
				ball["val"] = int(ball["val"]) - half
				var twin := BoardGenS.make_ball(
					pos + Vector2(6, 0),
					Vector2(-ball["vel"].x, ball["vel"].y).rotated(rng.randf_range(-0.2, 0.2)),
					half
				)
				twin["triggered"][gate["id"]] = true
				_pending_balls.append(twin)
				fx.floater(pos, "SPLIT", Color(0.6, 0.9, 1.0), 14)
		"teleport":
			ball["pos"] = Vector2(rng.randf_range(50.0, 430.0), BalanceS.DROP_Y + 6.0)
			ball["vel"] = Vector2.ZERO
			fx.floater(pos, "WARP", Color(0.8, 0.6, 1.0), 14)
		"gold":
			var g := maxi(1, int(ceil(int(ball["val"]) * 0.5)))
			gold_bonus += g
			ball["dead"] = true
			fx.floater(pos, "+%d GOLD" % g, Color(1.0, 0.9, 0.4), 15)
		"buff":
			if buff_t <= 0.0:
				for other: Dictionary in board["gates"]:
					if other["type"] == "mult":
						other["value"] = int(other["base_value"]) + 1
			buff_t = BalanceS.MYSTERY_BUFF_TIME
			fx.floater(pos, "GATES +1", Color(0.5, 1.0, 0.7), 15)


func _auto_aim_x() -> float:
	var best_x := 240.0
	var best_v := -1
	for gate: Dictionary in board["gates"]:
		if gate["type"] == "mult" and int(gate["value"]) > best_v:
			best_v = int(gate["value"])
			best_x = gate["x"]
	return best_x


func _play_events() -> void:
	if _evt.has("mult"):
		Sfx.play("gate_mult", 0.05, -4.0 + mini(int(_evt["mult"]), 10) * 0.5)
	if _evt.has("sub"):
		Sfx.play("gate_sub", 0.05, -6.0)
	if _evt.has("bounce"):
		Sfx.play("bounce", 0.1, -6.0)
	if _evt.has("myst"):
		Sfx.play("mystery")
	if _evt.has("tick"):
		var n := int(_evt["tick"])
		Sfx.play("ball_tick", 0.04, -12.0 + minf(n, 12.0))


# ---------------------------------------------------------------- input


func _unhandled_input(event: InputEvent) -> void:
	if phase != "aim" and phase != "dropping":
		return
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed and touch.position.y > 92.0:
			set_aim(touch.position.x)
	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		if drag.position.y > 92.0:
			set_aim(drag.position.x)


# ---------------------------------------------------------------- drawing


func _draw() -> void:
	var font := ThemeDB.fallback_font
	var left := BalanceS.BOARD_LEFT
	var right := BalanceS.BOARD_RIGHT
	var top := BalanceS.BOARD_TOP
	var exit_y := BalanceS.BOARD_EXIT_Y

	# Board panel + walls.
	draw_rect(Rect2(left, top - 20.0, right - left, exit_y - top + 40.0), Color(1, 1, 1, 0.025))
	draw_line(
		Vector2(left, top - 20.0), Vector2(left, exit_y + 20.0), Color(0.4, 0.7, 1.0, 0.5), 3.0
	)
	draw_line(
		Vector2(right, top - 20.0), Vector2(right, exit_y + 20.0), Color(0.4, 0.7, 1.0, 0.5), 3.0
	)
	# Exit zone.
	draw_rect(Rect2(left, exit_y, right - left, 16.0), Color(1.0, 0.82, 0.24, 0.12))
	draw_line(Vector2(left, exit_y), Vector2(right, exit_y), Color(1.0, 0.82, 0.24, 0.5), 2.0)

	# Guiding physics lines.
	for seg: Dictionary in board["lines"]:
		draw_line(seg["a"], seg["b"], Color(0.35, 0.6, 0.95, 0.25), 10.0)
		draw_line(seg["a"], seg["b"], Color(0.55, 0.8, 1.0, 0.9), 5.0)
		draw_circle(seg["a"], 2.5, Color(0.55, 0.8, 1.0))
		draw_circle(seg["b"], 2.5, Color(0.55, 0.8, 1.0))

	# Gates.
	for gate: Dictionary in board["gates"]:
		_draw_gate(font, gate)

	# Aim marker + dashed guide.
	if phase == "aim" or phase == "dropping":
		var ax := aim_x
		var tri := PackedVector2Array(
			[Vector2(ax - 9, top - 24.0), Vector2(ax + 9, top - 24.0), Vector2(ax, top - 8.0)]
		)
		var gold := Color(1.0, 0.82, 0.24)
		draw_polygon(tri, PackedColorArray([gold, gold, gold]))
		var y := top
		while y < top + 70.0:
			draw_line(Vector2(ax, y), Vector2(ax, y + 6.0), Color(1.0, 0.82, 0.24, 0.35), 2.0)
			y += 12.0

	# Balls.
	for ball: Dictionary in balls:
		var pos: Vector2 = ball["pos"]
		var v := int(ball["val"])
		var r := BalanceS.BALL_RADIUS
		if v > chunk:
			r += minf(3.0, log(maxf(1.0, float(v) / maxf(1.0, float(chunk)))) * 0.9)
		draw_circle(pos, r + 2.0, Color(1.0, 0.82, 0.24, 0.18))
		draw_circle(pos, r, Color(1.0, 0.84, 0.3))
		draw_circle(pos + Vector2(-r * 0.3, -r * 0.3), r * 0.35, Color(1.0, 0.95, 0.75))


func _draw_gate(font: Font, gate: Dictionary) -> void:
	var rect := BoardGenS.gate_rect(gate)
	var flash: float = gate["flash"]
	var label := ""
	var col: Color
	match gate["type"]:
		"mult":
			var v := int(gate["value"])
			label = "x%d" % v
			var heat := clampf((v - 1) / 9.0, 0.0, 1.0)
			col = Color(0.25, 0.9, 0.55).lerp(Color(1.0, 0.82, 0.24), heat)
			if v <= 1:
				col = Color(0.55, 0.6, 0.62)
		"sub":
			label = "-%d" % int(gate["counter"])
			col = Color(1.0, 0.4, 0.4)
		"bounce":
			col = Color(0.75, 0.5, 1.0)
		"myst":
			label = "?"
			col = Color(1.0, 0.85, 0.35)
	if not gate["active"]:
		col = Color(0.45, 0.47, 0.5, 0.5)

	# Frame.
	draw_rect(rect, Color(col.r, col.g, col.b, 0.12 + 0.3 * flash))
	draw_rect(rect, col, false, 2.0)
	# Side posts, so gates read as "gates" not buttons.
	draw_rect(Rect2(rect.position.x - 3.0, rect.position.y - 4.0, 3.0, rect.size.y + 8.0), col)
	draw_rect(Rect2(rect.end.x, rect.position.y - 4.0, 3.0, rect.size.y + 8.0), col)

	if gate["type"] == "bounce":
		var cx := rect.get_center().x
		var cy := rect.get_center().y
		for off in [-14.0, 4.0]:
			var tri := PackedVector2Array(
				[
					Vector2(cx + off - 6.0, cy + 6.0),
					Vector2(cx + off + 6.0, cy + 6.0),
					Vector2(cx + off, cy - 7.0),
				]
			)
			draw_polygon(tri, PackedColorArray([col, col, col]))
	elif label != "":
		var size := 15
		var w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		var pos := rect.get_center() + Vector2(-w * 0.5, size * 0.36)
		draw_string(font, pos, label, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col.lightened(0.3))
	if flash > 0.0:
		draw_rect(rect.grow(3.0), Color(1, 1, 1, 0.5 * flash), false, 2.0)
