extends Node2D
## Wave-15 boss. Three HP-gated phases (GDD: multiple attack phases + arena
## hazards):
##   P1  (100-70%): radial bullet rings + aimed fans
##   P2  (70-35%):  adds telegraphed charges and peon summons
##   P3  (35-0%):   adds a rotating bullet spiral and burning hazard zones

const BalanceS := preload("res://src/balance.gd")

var arena = null
var hp := BalanceS.BOSS_HP
var max_hp := BalanceS.BOSS_HP
var radius := BalanceS.BOSS_RADIUS
var is_elite := true
var alive := true
var phase := 1

var flash_t := 0.0
var contact_cd := 0.0
var spin := 0.0
## Measured each step so the hero can lead its shots.
var vel_estimate := Vector2.ZERO

var _move_state := "drift"
var _charge_t := 0.0
var _charge_dir := Vector2.ZERO
var _orbit_dir := 1.0
var _orbit_flip_t := 3.0

var _ring_t := 1.6
var _aimed_t := 2.2
var _charge_cd := 3.0
var _summon_t := 4.0
var _spiral_t := 0.0
var _spiral_angle := 0.0
var _hazard_t := 2.5


func step(dt: float, hero) -> void:
	if not alive:
		return
	flash_t = maxf(0.0, flash_t - dt)
	contact_cd = maxf(0.0, contact_cd - dt)
	spin += dt * (0.6 + 0.5 * phase)
	var pre := position
	_update_phase()
	_move(dt, hero)
	_attacks(dt, hero)
	_contact(hero)
	vel_estimate = (position - pre) / maxf(dt, 0.0001)
	queue_redraw()


func _update_phase() -> void:
	var frac := hp / max_hp
	var new_phase := 1
	if frac <= BalanceS.BOSS_PHASE3_FRAC:
		new_phase = 3
	elif frac <= BalanceS.BOSS_PHASE2_FRAC:
		new_phase = 2
	if new_phase != phase:
		phase = new_phase
		Sfx.play("boss_roar")
		arena.fx.shake(10.0)
		arena.fx.floater(
			position + Vector2(0, -radius - 16), "PHASE %d" % phase, Color(1, 0.5, 0.4), 20
		)


func _move(dt: float, hero) -> void:
	match _move_state:
		"drift":
			_orbit_flip_t -= dt
			if _orbit_flip_t <= 0.0:
				_orbit_flip_t = arena.rng.randf_range(2.5, 4.5)
				_orbit_dir = -_orbit_dir
			var to_hero: Vector2 = hero.position - position
			var dist := to_hero.length()
			var dir := to_hero.normalized()
			var tangent := dir.rotated(PI * 0.5) * _orbit_dir
			var radial := dir * clampf((dist - 180.0) * 0.02, -1.0, 1.0)
			position += (radial + tangent * 0.55).normalized() * BalanceS.BOSS_SPEED * dt
		"windup":
			_charge_t -= dt
			_charge_dir = (hero.position - position).normalized()
			if _charge_t <= 0.0:
				_move_state = "charge"
				_charge_t = 0.55
				Sfx.play("boss_roar", 0.2, -6.0)
		"charge":
			_charge_t -= dt
			position += _charge_dir * 460.0 * dt
			if _charge_t <= 0.0:
				_move_state = "drift"
	var rect: Rect2 = BalanceS.ARENA_RECT
	position.x = clampf(position.x, rect.position.x + radius, rect.end.x - radius)
	position.y = clampf(position.y, rect.position.y + radius, rect.end.y - radius)


func _attacks(dt: float, hero) -> void:
	_ring_t -= dt
	if _ring_t <= 0.0:
		_ring_t = 2.6 if phase < 3 else 3.4
		var count := 14 if phase < 3 else 18
		var base: float = arena.rng.randf() * TAU
		for i in count:
			var ang: float = base + TAU * i / count
			_shoot(Vector2.from_angle(ang))
	_aimed_t -= dt
	if _aimed_t <= 0.0:
		_aimed_t = 1.5
		var aim: Vector2 = (hero.position - position).normalized()
		for off in [-0.22, 0.0, 0.22]:
			_shoot(aim.rotated(off))
	if phase >= 2:
		if _move_state == "drift":
			_charge_cd -= dt
			if _charge_cd <= 0.0:
				_charge_cd = 4.2
				_move_state = "windup"
				_charge_t = 0.6
				Sfx.play("charge_warn", 0.0, -2.0)
		_summon_t -= dt
		if _summon_t <= 0.0:
			_summon_t = 6.0
			arena.spawn_summons(3)
	if phase >= 3:
		_spiral_t -= dt
		if _spiral_t <= 0.0:
			_spiral_t = 0.09
			_spiral_angle += 0.38
			_shoot(Vector2.from_angle(_spiral_angle))
			_shoot(Vector2.from_angle(_spiral_angle + PI))
		_hazard_t -= dt
		if _hazard_t <= 0.0:
			_hazard_t = 5.0
			arena.spawn_hazard(hero.position)
			arena.spawn_hazard(arena.random_arena_point())


func _shoot(dir: Vector2) -> void:
	arena.spawn_enemy_bullet(
		position + dir * (radius + 6.0), dir * BalanceS.ENEMY_BULLET_SPEED, BalanceS.BOSS_BULLET_DMG
	)


func _contact(hero) -> void:
	if contact_cd > 0.0 or not hero.alive:
		return
	if position.distance_to(hero.position) < radius + hero.radius():
		hero.take_damage(BalanceS.BOSS_CONTACT_DMG)
		contact_cd = BalanceS.CONTACT_COOLDOWN
		if arena.run.thorns > 0.0:
			take_hit(arena.run.thorns, false)


func take_hit(amount: float, crit: bool) -> void:
	if not alive:
		return
	hp -= amount
	flash_t = 0.06
	if crit:
		arena.fx.floater(position + Vector2(0, -radius - 8), "CRIT", Color(1.0, 0.8, 0.3), 14)
	if hp <= 0.0:
		alive = false
		arena.on_boss_died()


func _draw() -> void:
	var core: Color
	match phase:
		1:
			core = Color(0.7, 0.42, 1.0)
		2:
			core = Color(1.0, 0.62, 0.24)
		_:
			core = Color(1.0, 0.3, 0.43)
	if _move_state == "windup":
		var pulse := 0.5 + 0.5 * sin(_charge_t * 40.0)
		draw_line(Vector2.ZERO, _charge_dir * 500.0, Color(1.0, 0.3, 0.2, 0.35 * pulse), 4.0)
		draw_circle(Vector2.ZERO, radius + 8.0, Color(1.0, 0.3, 0.2, 0.3 * pulse))
	draw_circle(Vector2.ZERO, radius + 6.0, Color(core.r, core.g, core.b, 0.16))
	# Rotating spikes.
	for i in 6:
		var ang := spin + TAU * i / 6.0
		var a := Vector2.from_angle(ang) * (radius + 10.0)
		var b := Vector2.from_angle(ang + 0.24) * (radius - 2.0)
		var c := Vector2.from_angle(ang - 0.24) * (radius - 2.0)
		draw_polygon(
			PackedVector2Array([a, b, c]), PackedColorArray([core * 0.8, core * 0.5, core * 0.5])
		)
	draw_circle(Vector2.ZERO, radius, Color(0.16, 0.1, 0.22))
	draw_circle(Vector2.ZERO, radius * 0.72, core * 0.55)
	draw_circle(Vector2.ZERO, radius * 0.4, core)
	draw_arc(Vector2.ZERO, radius + 4.0, 0, TAU, 32, Color(1.0, 0.82, 0.24, 0.85), 2.0)
	if flash_t > 0.0:
		draw_circle(Vector2.ZERO, radius, Color(1, 1, 1, 0.5))
