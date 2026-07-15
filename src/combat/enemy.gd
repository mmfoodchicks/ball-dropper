extends Node2D
## One script for all regular enemies. GDD types:
##  - peon: swarms, low HP, no ball drops, pure pressure
##  - brute (elite): tanky charger, drops balls
##  - spitter (elite): ranged kiter, drops balls
## Elites carry a gold ring marking them as ball carriers.

const BalanceS := preload("res://src/balance.gd")

var arena = null
var kind := "peon"
var is_elite := false
var hp := 10.0
var max_hp := 10.0
var speed := 60.0
var contact_dmg := 6.0
var radius := 10.0
var ball_drop := 0
var alive := true

var flash_t := 0.0
var spawn_t := 0.45
var contact_cd := 0.0

# brute charge state
var charge_state := "approach"
var charge_t := 0.0
var charge_cd := 1.5
var charge_dir := Vector2.ZERO

# spitter state
var orbit_dir := 1.0
var shot_cd := 1.2

var _speed_jitter := 1.0


func setup(enemy_kind: String, wave: int, arena_ref) -> void:
	arena = arena_ref
	kind = enemy_kind
	var rng: RandomNumberGenerator = arena.rng
	_speed_jitter = rng.randf_range(0.9, 1.1)
	orbit_dir = 1.0 if rng.randf() < 0.5 else -1.0
	shot_cd = rng.randf_range(0.8, 1.6)
	charge_cd = rng.randf_range(1.0, 2.2)
	match kind:
		"peon":
			hp = BalanceS.peon_hp(wave)
			speed = BalanceS.peon_speed(wave)
			contact_dmg = BalanceS.PEON_DMG
			radius = 10.0
		"brute":
			is_elite = true
			hp = BalanceS.brute_hp(wave)
			speed = 46.0
			contact_dmg = BalanceS.BRUTE_DMG
			radius = 16.0
			ball_drop = BalanceS.elite_ball_drop(wave, arena.run.elite_ball_mult)
		"spitter":
			is_elite = true
			hp = BalanceS.spitter_hp(wave)
			speed = 55.0
			contact_dmg = BalanceS.SPITTER_CONTACT_DMG
			radius = 13.0
			ball_drop = BalanceS.elite_ball_drop(wave, arena.run.elite_ball_mult)
	max_hp = hp


func step(dt: float) -> void:
	flash_t = maxf(0.0, flash_t - dt)
	contact_cd = maxf(0.0, contact_cd - dt)
	if spawn_t > 0.0:
		spawn_t -= dt
		queue_redraw()
		return
	var hero = arena.hero
	if hero != null and hero.alive:
		match kind:
			"peon":
				_step_peon(dt, hero)
			"brute":
				_step_brute(dt, hero)
			"spitter":
				_step_spitter(dt, hero)
		_try_contact(hero)
	_clamp_to_arena()
	queue_redraw()


func _step_peon(dt: float, hero) -> void:
	var dir := (hero.position - position).normalized()
	var sep := _separation()
	position += (dir * speed * _speed_jitter + sep) * dt


func _step_brute(dt: float, hero) -> void:
	charge_cd = maxf(0.0, charge_cd - dt)
	match charge_state:
		"approach":
			var dir := (hero.position - position).normalized()
			position += (dir * speed * _speed_jitter + _separation()) * dt
			if charge_cd <= 0.0 and position.distance_to(hero.position) < 160.0:
				charge_state = "windup"
				charge_t = 0.5
				Sfx.play("charge_warn", 0.1)
		"windup":
			charge_t -= dt
			charge_dir = (hero.position - position).normalized()
			if charge_t <= 0.0:
				charge_state = "charge"
				charge_t = 0.55
		"charge":
			charge_t -= dt
			position += charge_dir * 380.0 * dt
			if charge_t <= 0.0:
				charge_state = "approach"
				charge_cd = 2.8


func _step_spitter(dt: float, hero) -> void:
	var to_me := position - hero.position
	var ring_pos := hero.position + to_me.normalized().rotated(orbit_dir * 0.5) * 210.0
	var dir := (ring_pos - position).normalized()
	position += (dir * speed * _speed_jitter + _separation()) * dt
	shot_cd -= dt
	if shot_cd <= 0.0:
		shot_cd = 1.9
		var aim := (hero.position - position).normalized()
		arena.spawn_enemy_bullet(
			position + aim * (radius + 4.0),
			aim * BalanceS.ENEMY_BULLET_SPEED,
			BalanceS.spitter_shot_dmg(arena.wave)
		)


func _separation() -> Vector2:
	var push := Vector2.ZERO
	for other in arena.enemies:
		if other == self or not other.alive:
			continue
		var d: Vector2 = position - other.position
		var min_d: float = (radius + other.radius) * 0.9
		var len2 := d.length()
		if len2 > 0.001 and len2 < min_d:
			push += d / len2 * (min_d - len2) * 4.0
	return push


func _try_contact(hero) -> void:
	if contact_cd > 0.0:
		return
	if position.distance_to(hero.position) < radius + hero.radius():
		hero.take_damage(contact_dmg)
		contact_cd = BalanceS.CONTACT_COOLDOWN


func _clamp_to_arena() -> void:
	var rect := BalanceS.ARENA_RECT
	position.x = clampf(position.x, rect.position.x + radius, rect.end.x - radius)
	position.y = clampf(position.y, rect.position.y + radius, rect.end.y - radius)


func take_hit(amount: float, crit: bool) -> void:
	if not alive or spawn_t > 0.0:
		return
	hp -= amount
	flash_t = 0.08
	if crit:
		arena.fx.floater(position + Vector2(0, -radius - 6), "CRIT", Color(1.0, 0.8, 0.3), 13)
	if hp <= 0.0:
		alive = false
		arena.on_enemy_died(self)


func _draw() -> void:
	var a := 1.0
	if spawn_t > 0.0:
		a = clampf(1.0 - spawn_t / 0.45, 0.1, 1.0) * 0.6
	var body: Color
	match kind:
		"peon":
			body = Color(1.0, 0.36, 0.36, a)
			draw_circle(Vector2.ZERO, radius, body)
			draw_circle(Vector2.ZERO, radius * 0.55, Color(0.62, 0.13, 0.16, a))
		"brute":
			body = Color(1.0, 0.6, 0.25, a)
			if charge_state == "windup":
				var pulse := 0.5 + 0.5 * sin(charge_t * 40.0)
				draw_circle(Vector2.ZERO, radius + 5.0, Color(1.0, 0.3, 0.2, 0.35 * pulse))
			draw_circle(Vector2.ZERO, radius, body)
			draw_circle(Vector2.ZERO, radius * 0.6, Color(0.7, 0.3, 0.08, a))
		"spitter":
			body = Color(0.9, 0.4, 0.95, a)
			var pts := PackedVector2Array(
				[
					Vector2(0, -radius - 3),
					Vector2(radius, 0),
					Vector2(0, radius + 3),
					Vector2(-radius, 0),
				]
			)
			draw_polygon(pts, PackedColorArray([body, body, body, body]))
			draw_circle(Vector2.ZERO, radius * 0.4, Color(0.5, 0.12, 0.55, a))
	if is_elite:
		draw_arc(Vector2.ZERO, radius + 4.0, 0, TAU, 24, Color(1.0, 0.82, 0.24, 0.9 * a), 2.0)
	if flash_t > 0.0:
		draw_circle(Vector2.ZERO, radius, Color(1, 1, 1, 0.65))
	if is_elite and hp < max_hp:
		var w := radius * 2.0
		var frac := clampf(hp / max_hp, 0.0, 1.0)
		var bar_y := -radius - 10.0
		draw_rect(Rect2(-w * 0.5, bar_y, w, 3.0), Color(0, 0, 0, 0.5))
		draw_rect(Rect2(-w * 0.5, bar_y, w * frac, 3.0), Color(0.4, 1.0, 0.5, 0.9))
