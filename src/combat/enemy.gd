extends Node2D
## Data-driven enemy: every kind in Balance.ENEMY_KINDS shares this script.
## Peons swarm and drop nothing; elites are ball carriers (gold ring).
## Behaviors: chase, weave, hop, turret, blink, charge, orbit_ranged,
## burst_ranged, spawner, shieldcycle, exploder.

const BalanceS := preload("res://src/balance.gd")

var arena = null
var kind := "scrapper"
var def := {}
var is_elite := false
var hp := 10.0
var max_hp := 10.0
var speed := 60.0
var contact_dmg := 6.0
var radius := 10.0
var ball_drop := 0
var alive := true
var shape := "circle"
var body_color := Color(1.0, 0.45, 0.3)

var flash_t := 0.0
var spawn_t := 0.45
var contact_cd := 0.0
## Measured each step so the hero can lead its shots.
var vel_estimate := Vector2.ZERO

# Behavior state (only the fields for this kind's behavior are used).
var charge_state := "approach"
var charge_t := 0.0
var charge_cd := 1.5
var charge_dir := Vector2.ZERO
var orbit_dir := 1.0
var shot_cd := 1.2
var strafe_t := 0.0
var hop_t := 0.0
var blink_t := 2.0
var spawn_timer := 4.0
var shield_t := 0.0
var shielded := false
var fuse_t := -1.0
var weave_seed := 0.0
var weave_t := 0.0

var _speed_jitter := 1.0
var _tex: Texture2D = null
var _anim_t := 0.0


func setup(enemy_kind: String, wave: int, arena_ref) -> void:
	arena = arena_ref
	kind = enemy_kind
	def = BalanceS.enemy_def(kind)
	var tex_path := "res://assets/sprites/enemy_%s.png" % kind
	if ResourceLoader.exists(tex_path):
		_tex = load(tex_path)
	is_elite = def["class"] == "elite"
	hp = BalanceS.enemy_hp(kind, wave)
	max_hp = hp
	speed = float(def["speed"]) * BalanceS.enemy_speed_scale(wave)
	contact_dmg = float(def["dmg"])
	radius = float(def["radius"])
	shape = str(def["shape"])
	body_color = def["color"]
	if is_elite:
		ball_drop = BalanceS.elite_ball_drop(wave, arena.run.elite_ball_mult)
	var rng: RandomNumberGenerator = arena.rng
	_speed_jitter = rng.randf_range(0.9, 1.1)
	orbit_dir = 1.0 if rng.randf() < 0.5 else -1.0
	shot_cd = rng.randf_range(0.8, 1.6)
	strafe_t = rng.randf_range(0.0, 1.7)
	charge_cd = rng.randf_range(1.0, 2.2)
	blink_t = rng.randf_range(0.8, float(def.get("blink_interval", 2.2)))
	hop_t = rng.randf_range(0.0, 1.2)
	spawn_timer = rng.randf_range(2.0, float(def.get("spawn_interval", 5.0)))
	shield_t = rng.randf_range(0.0, 3.0)
	weave_seed = rng.randf() * TAU


func step(dt: float) -> void:
	_anim_t += dt
	flash_t = maxf(0.0, flash_t - dt)
	contact_cd = maxf(0.0, contact_cd - dt)
	if spawn_t > 0.0:
		spawn_t -= dt
		queue_redraw()
		return
	var pre := position
	var hero = arena.hero
	if hero != null and hero.alive:
		var sf := 1.0
		if arena.run.slow_field and position.distance_to(hero.position) < 90.0:
			sf = 0.75
		_behave(dt, hero, sf)
		if def["behavior"] != "exploder":
			_try_contact(hero)
	_clamp_to_arena()
	vel_estimate = (position - pre) / maxf(dt, 0.0001)
	queue_redraw()


# ---------------------------------------------------------------- behaviors


func _behave(dt: float, hero, sf: float) -> void:
	match str(def["behavior"]):
		"chase":
			_move_chase(dt, hero, sf)
		"weave":
			_step_weave(dt, hero, sf)
		"hop":
			_step_hop(dt, hero, sf)
		"turret":
			_move_chase(dt, hero, sf)
			_step_shooting(dt, hero, 0.0)
		"blink":
			_move_chase(dt, hero, sf)
			_step_blink(dt, hero)
		"charge":
			_step_charge(dt, hero, sf)
		"orbit_ranged":
			_step_orbit(dt, hero, sf)
			_step_shooting(dt, hero, 0.0)
		"burst_ranged":
			_step_orbit(dt, hero, sf)
			_step_shooting(dt, hero, 0.25)
		"spawner":
			_move_chase(dt, hero, sf)
			_step_spawning(dt)
		"shieldcycle":
			_move_chase(dt, hero, sf)
			shield_t += dt
			var cycle := float(def.get("shield_on", 1.8)) + float(def.get("shield_off", 3.2))
			shielded = fmod(shield_t, cycle) < float(def.get("shield_on", 1.8))
		"exploder":
			_step_exploder(dt, hero, sf)


func _move_chase(dt: float, hero, sf: float) -> void:
	var dir: Vector2 = (hero.position - position).normalized()
	position += (dir * speed * _speed_jitter * sf + _separation()) * dt


func _step_weave(dt: float, hero, sf: float) -> void:
	weave_t += dt
	var dir: Vector2 = (hero.position - position).normalized()
	var perp := dir.rotated(PI * 0.5) * sin(weave_t * 3.0 + weave_seed) * 0.8
	position += ((dir + perp).normalized() * speed * _speed_jitter * sf + _separation()) * dt


func _step_hop(dt: float, hero, sf: float) -> void:
	hop_t += dt
	var hop := float(def.get("hop_time", 0.45))
	var cycle := hop + float(def.get("rest_time", 0.75))
	if fmod(hop_t, cycle) < hop:
		var dir: Vector2 = (hero.position - position).normalized()
		position += (dir * speed * _speed_jitter * sf + _separation()) * dt


func _step_blink(dt: float, hero) -> void:
	blink_t -= dt
	if blink_t > 0.0:
		return
	blink_t = float(def.get("blink_interval", 2.2))
	var to_hero: Vector2 = hero.position - position
	var dist := to_hero.length()
	var jump := minf(float(def.get("blink_range", 90.0)), maxf(0.0, dist - 40.0))
	if jump > 8.0:
		arena.fx.burst(position, body_color, 5, 90.0)
		position += to_hero.normalized() * jump
		arena.fx.burst(position, body_color, 5, 90.0)


func _step_charge(dt: float, hero, sf: float) -> void:
	charge_cd = maxf(0.0, charge_cd - dt)
	match charge_state:
		"approach":
			_move_chase(dt, hero, sf)
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
			position += charge_dir * 380.0 * sf * dt
			if charge_t <= 0.0:
				charge_state = "approach"
				charge_cd = 2.8


func _step_orbit(dt: float, hero, sf: float) -> void:
	# Move-then-hold rhythm: the hold window keeps ranged orbiters hittable.
	strafe_t += dt
	if fmod(strafe_t, 1.7) < 1.1:
		var to_me: Vector2 = position - hero.position
		var ring_pos: Vector2 = hero.position + to_me.normalized().rotated(orbit_dir * 0.5) * 210.0
		var dir: Vector2 = (ring_pos - position).normalized()
		position += (dir * speed * _speed_jitter * sf + _separation()) * dt


func _step_shooting(dt: float, hero, fan: float) -> void:
	shot_cd -= dt
	if shot_cd > 0.0:
		return
	shot_cd = float(def.get("shot_interval", 2.0))
	var count := int(def.get("burst", 1))
	var aim: Vector2 = (hero.position - position).normalized()
	for i in count:
		var off := (float(i) - (count - 1) * 0.5) * fan
		var dir := aim.rotated(off)
		arena.spawn_enemy_bullet(
			position + dir * (radius + 4.0),
			dir * BalanceS.ENEMY_BULLET_SPEED,
			BalanceS.enemy_shot_dmg(kind, arena.wave)
		)


func _step_spawning(dt: float) -> void:
	spawn_timer -= dt
	if spawn_timer > 0.0:
		return
	spawn_timer = float(def.get("spawn_interval", 5.0))
	var child := str(def.get("spawn_kind", "mite"))
	for i in int(def.get("spawn_count", 2)):
		arena.spawn_reinforcement(child, position + Vector2(arena.rng.randf_range(-20, 20), 14))
	arena.fx.burst(position, body_color, 8, 110.0)


func _step_exploder(dt: float, hero, sf: float) -> void:
	if fuse_t < 0.0:
		_move_chase(dt, hero, sf)
		if position.distance_to(hero.position) < float(def.get("fuse_range", 70.0)):
			fuse_t = float(def.get("fuse_time", 0.8))
			Sfx.play("charge_warn", 0.0, -2.0)
		return
	fuse_t -= dt
	if fuse_t <= 0.0:
		var blast := float(def.get("blast_radius", 90.0))
		if hero.position.distance_to(position) < blast:
			hero.take_damage(contact_dmg)
		arena.fx.burst(position, body_color, 26, 240.0)
		arena.fx.shake(8.0)
		Sfx.play("elite_die", 0.1)
		alive = false
		arena.on_enemy_died(self)


# ---------------------------------------------------------------- shared


func _separation() -> Vector2:
	var push := Vector2.ZERO
	for other in arena.enemies:
		if other == self or not other.alive:
			continue
		var d: Vector2 = position - other.position
		var min_d: float = (radius + other.radius) * 0.9
		var dist := d.length()
		if dist > 0.001 and dist < min_d:
			push += d / dist * (min_d - dist) * 4.0
	return push


func _try_contact(hero) -> void:
	if contact_cd > 0.0:
		return
	if position.distance_to(hero.position) < radius + hero.radius():
		hero.take_damage(contact_dmg)
		contact_cd = BalanceS.CONTACT_COOLDOWN
		if arena.run.thorns > 0.0:
			take_hit(arena.run.thorns, false)


func _clamp_to_arena() -> void:
	var rect := BalanceS.ARENA_RECT
	position.x = clampf(position.x, rect.position.x + radius, rect.end.x - radius)
	position.y = clampf(position.y, rect.position.y + radius, rect.end.y - radius)


func take_hit(amount: float, crit: bool) -> void:
	if not alive or spawn_t > 0.0:
		return
	if shielded:
		flash_t = 0.06
		return
	hp -= amount
	flash_t = 0.08
	if crit:
		arena.fx.floater(position + Vector2(0, -radius - 6), "CRIT", Color(1.0, 0.8, 0.3), 13)
	if hp <= 0.0:
		alive = false
		arena.on_enemy_died(self)


# ---------------------------------------------------------------- drawing


func _draw() -> void:
	var a := 1.0
	if spawn_t > 0.0:
		a = clampf(1.0 - spawn_t / 0.45, 0.1, 1.0) * 0.6
	var body := Color(body_color.r, body_color.g, body_color.b, a)
	var core := body.darkened(0.45)

	if def["behavior"] == "charge" and charge_state == "windup":
		var pulse := 0.5 + 0.5 * sin(charge_t * 40.0)
		draw_circle(Vector2.ZERO, radius + 5.0, Color(1.0, 0.3, 0.2, 0.35 * pulse))
	if fuse_t >= 0.0:
		var fpulse := 0.5 + 0.5 * sin(fuse_t * 50.0)
		draw_circle(Vector2.ZERO, radius + 6.0, Color(1.0, 0.25, 0.25, 0.4 * fpulse))

	if _tex != null:
		# Pixel sprite (tools/make_sprites.py); vector shapes are the fallback.
		var side := _tex.get_width() / 4.0
		var bob := sin(_anim_t * 5.0 + weave_seed) * 1.1
		draw_texture_rect(
			_tex, Rect2(-side * 0.5, -side * 0.5 + bob, side, side), false, Color(1, 1, 1, a)
		)
	else:
		match shape:
			"circle":
				draw_circle(Vector2.ZERO, radius, body)
				draw_circle(Vector2.ZERO, radius * 0.55, core)
			"triangle":
				_draw_poly(3, radius + 2.0, body, core)
			"square":
				draw_rect(Rect2(-radius, -radius, radius * 2.0, radius * 2.0), body)
				draw_rect(Rect2(-radius * 0.5, -radius * 0.5, radius, radius), core)
			"diamond":
				_draw_poly(4, radius + 3.0, body, core)
			"hex":
				_draw_poly(6, radius + 2.0, body, core)
			"spike":
				_draw_star(radius + 4.0, body)
				draw_circle(Vector2.ZERO, radius * 0.45, core)

	if shielded:
		draw_arc(Vector2.ZERO, radius + 6.0, 0, TAU, 24, Color(0.5, 0.9, 1.0, 0.9), 3.0)
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


func _draw_poly(sides: int, r: float, body: Color, core: Color) -> void:
	var pts := PackedVector2Array()
	var cols := PackedColorArray()
	for i in sides:
		var ang := -PI * 0.5 + TAU * i / sides
		pts.append(Vector2.from_angle(ang) * r)
		cols.append(body)
	draw_polygon(pts, cols)
	draw_circle(Vector2.ZERO, r * 0.4, core)


func _draw_star(r: float, body: Color) -> void:
	var pts := PackedVector2Array()
	var cols := PackedColorArray()
	for i in 8:
		var ang := TAU * i / 8.0
		var rad := r if i % 2 == 0 else r * 0.5
		pts.append(Vector2.from_angle(ang) * rad)
		cols.append(body)
	draw_polygon(pts, cols)
