extends Node2D
## The player avatar. HP lives on RunState (single source of truth for HUD
## and persistence). Fires automatically at the aim direction: manual right
## stick if held, otherwise auto-aim at the nearest enemy (GDD accessibility).

const BalanceS := preload("res://src/balance.gd")

var arena = null
var run = null
var alive := true
var god := false

var iframes := 0.0
var frenzy_t := 0.0
var moving := false

var _fire_acc := 0.0
var _aim := Vector2.RIGHT
var _no_dmg_t := 99.0


func radius() -> float:
	return BalanceS.HERO_RADIUS


func step(dt: float, move_dir: Vector2, manual_aim: Vector2) -> void:
	if not alive:
		return
	if god:
		run.hp = run.max_hp
	iframes = maxf(0.0, iframes - dt)
	frenzy_t = maxf(0.0, frenzy_t - dt)
	_no_dmg_t += dt
	if run.regen > 0.0:
		run.hp = minf(run.max_hp, run.hp + run.regen * dt)

	moving = move_dir.length() > 0.05
	if moving:
		position += move_dir.limit_length(1.0) * run.move_speed * dt
	var rect: Rect2 = BalanceS.ARENA_RECT
	position.x = clampf(position.x, rect.position.x + radius(), rect.end.x - radius())
	position.y = clampf(position.y, rect.position.y + radius(), rect.end.y - radius())

	var target = arena.nearest_enemy(position)
	if manual_aim.length() > 0.2:
		_aim = manual_aim.normalized()
	elif target != null:
		# Lead the shot by projected bullet flight time, or orbiting enemies
		# sidestep every bullet.
		var to_t: Vector2 = target.position - position
		var flight: float = to_t.length() / maxf(run.bullet_speed, 1.0)
		var predicted: Vector2 = target.position + target.vel_estimate * flight
		_aim = (predicted - position).normalized()
	elif moving:
		_aim = move_dir.normalized()

	# Auto-fire while any target exists (or when manually aiming).
	var want_fire := target != null or manual_aim.length() > 0.2
	var rate: float = run.fire_rate * (run.frenzy_mult if frenzy_t > 0.0 else 1.0)
	if want_fire:
		_fire_acc += dt * rate
		while _fire_acc >= 1.0:
			_fire_acc -= 1.0
			_fire_volley()
	else:
		_fire_acc = minf(_fire_acc + dt * rate, 0.999)
	queue_redraw()


func _fire_volley() -> void:
	var n: int = run.projectiles
	var spread := 0.14
	var dmg: float = run.dmg * (1.2 if run.momentum and moving else 1.0)
	for i in n:
		var off := (float(i) - (n - 1) * 0.5) * spread
		var dir := _aim.rotated(off)
		arena.spawn_bullet(
			position + dir * (radius() - 2.0),
			dir * run.bullet_speed,
			dmg,
			run.bullet_radius,
			run.pierce
		)
	Sfx.play("shoot", 0.08, -6.0)


func take_damage(amount: float, from_hazard := false) -> void:
	if not alive or god:
		return
	if not from_hazard and iframes > 0.0:
		return
	if run.kinetic_shield and not from_hazard and _no_dmg_t >= 4.0:
		_no_dmg_t = 0.0
		arena.fx.floater(position + Vector2(0, -22), "BLOCKED", Color(0.5, 0.9, 1.0), 14)
		Sfx.play("bounce", 0.1)
		return
	_no_dmg_t = 0.0
	run.hp -= amount * run.dmg_taken_mult
	if not from_hazard:
		iframes = BalanceS.HERO_IFRAMES
		Sfx.play("hurt", 0.1)
		arena.fx.shake(7.0)
		arena.fx.burst(position, Color(0.45, 0.85, 1.0), 6, 90.0)
	if run.hp <= 0.0:
		if run.second_wind_ready:
			run.second_wind_ready = false
			run.hp = run.max_hp * run.second_wind_frac
			iframes = 1.5
			Sfx.play("second_wind")
			arena.fx.floater(position + Vector2(0, -24), "SECOND WIND", Color(0.5, 1.0, 0.7), 18)
			arena.fx.burst(position, Color(0.5, 1.0, 0.7), 20, 200.0)
		else:
			run.hp = 0.0
			alive = false
			arena.on_hero_died()


func _draw() -> void:
	var a := 1.0
	if iframes > 0.0:
		a = 0.45 + 0.4 * sin(iframes * 40.0)
	draw_circle(Vector2.ZERO, radius() + 4.0, Color(0.35, 0.85, 1.0, 0.14 * a))
	draw_circle(Vector2.ZERO, radius(), Color(0.35, 0.85, 1.0, a))
	draw_circle(Vector2.ZERO, radius() * 0.5, Color(0.9, 1.0, 1.0, a))
	# Aim tick.
	var tip := _aim * (radius() + 9.0)
	draw_line(_aim * radius(), tip, Color(1, 1, 1, 0.7 * a), 2.0)
	if frenzy_t > 0.0:
		draw_arc(Vector2.ZERO, radius() + 7.0, 0, TAU, 24, Color(1.0, 0.5, 0.3, 0.7), 2.0)
