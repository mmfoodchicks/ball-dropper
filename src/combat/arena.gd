extends Node2D
## Combat phase controller: single-screen top-down arena (GDD: no scrolling).
## Owns the hero, enemies, projectiles, hazards and the wave spawner, and
## steps them explicitly so pause/turbo behave deterministically.
##
## Signals tell main.gd when the phase changes hands:
##   dropper_ready(wave)  -> waves 5/10 cleared, hand over to the dropper
##   boss_defeated        -> wave 15 boss killed, hand over to victory flow
##   hero_down            -> run ended in defeat

signal dropper_ready(wave)
signal boss_defeated
signal hero_down

const BalanceS := preload("res://src/balance.gd")
const HeroS := preload("res://src/combat/hero.gd")
const EnemyS := preload("res://src/combat/enemy.gd")
const BossS := preload("res://src/combat/boss.gd")
const BulletS := preload("res://src/combat/bullet.gd")
const HazardS := preload("res://src/combat/hazard.gd")
const FxS := preload("res://src/fx/fx.gd")

var run = null
var joy_move = null
var joy_aim = null
var external_stepping := false

var rng := RandomNumberGenerator.new()
var wave := 1
var state := "banner"

var hero = null
var fx = null
var boss = null
var enemies: Array = []
var bullets: Array = []
var enemy_bullets: Array = []
var hazards: Array = []

var _banner_text := ""
var _banner_t := 0.0
var _inter_t := 0.0
var _end_t := 0.0
var _spawn_queue: Array = []
var _spawn_timer := 0.0
var _is_boss_wave := false
var _wave_t := 0.0
var _stall_report_at := 45.0


func _ready() -> void:
	rng.randomize()
	fx = FxS.new()
	fx.z_index = 10
	add_child(fx)
	hero = HeroS.new()
	hero.arena = self
	hero.run = run
	hero.z_index = 5
	hero.position = Vector2(BalanceS.DESIGN_W * 0.5, BalanceS.DESIGN_H * 0.62)
	add_child(hero)
	start_wave(run.wave)


func _physics_process(delta: float) -> void:
	if not external_stepping:
		step(delta)


# ---------------------------------------------------------------- wave flow


func start_wave(w: int) -> void:
	wave = w
	run.wave = w
	if run.autoplay:
		print("AUTOPLAY: wave %d starting (balls %d)" % [w, run.balls])
	_is_boss_wave = w >= BalanceS.BOSS_WAVE
	_spawn_queue = _build_queue(w)
	_spawn_timer = 0.0
	_wave_t = 0.0
	_stall_report_at = 45.0
	state = "banner"
	_banner_text = "BOSS INCOMING" if _is_boss_wave else "WAVE %d" % w
	_banner_t = 2.4 if _is_boss_wave else BalanceS.WAVE_BANNER_TIME
	if _is_boss_wave:
		Sfx.play("boss_roar")


func _build_queue(w: int) -> Array:
	var queue: Array = []
	if w >= BalanceS.BOSS_WAVE:
		return queue
	for i in BalanceS.peon_count(w):
		queue.append("peon")
	for i in BalanceS.elite_count(w):
		queue.append("brute" if rng.randf() < 0.5 else "spitter")
	# Fisher-Yates with the arena rng, so seeded runs stay reproducible.
	for i in range(queue.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = queue[i]
		queue[i] = queue[j]
		queue[j] = tmp
	return queue


func step(dt: float) -> void:
	match state:
		"banner":
			_banner_t -= dt
			if _banner_t <= 0.0:
				state = "fight"
				if _is_boss_wave:
					_spawn_boss()
				else:
					var initial := int(ceil(_spawn_queue.size() * BalanceS.SPAWN_INITIAL_FRAC))
					for i in initial:
						_spawn_next()
		"fight":
			_spawn_tick(dt)
			_wave_t += dt
			# Watchdog: a dead hero while the wave still "fights" is an
			# illegal state — resolve it instead of hanging the run.
			if not hero.alive:
				if hero.god:
					hero.alive = true
					print("WATCHDOG: god hero resurrected (illegal death)")
				else:
					print("WATCHDOG: dead hero in fight state, ending run")
					on_hero_died()
			if run.autoplay and _wave_t >= _stall_report_at:
				_stall_report_at += 25.0
				_print_stall_state()
		"cleared":
			_inter_t -= dt
			if _inter_t <= 0.0:
				if wave in BalanceS.DROPPER_WAVES:
					state = "idle"
					dropper_ready.emit(wave)
				else:
					start_wave(wave + 1)
		"boss_dead":
			_end_t -= dt
			if _end_t <= 0.0:
				state = "idle"
				boss_defeated.emit()
		"hero_dead":
			_end_t -= dt
			if _end_t <= 0.0:
				state = "idle"
				hero_down.emit()
	if state != "idle":
		_step_entities(dt)
		_check_cleared()
	fx.step(dt)
	position = fx.offset()
	queue_redraw()


func _spawn_tick(dt: float) -> void:
	if _spawn_queue.is_empty():
		return
	_spawn_timer -= dt
	if _spawn_timer > 0.0:
		return
	_spawn_timer = BalanceS.SPAWN_INTERVAL
	var batch := mini(BalanceS.SPAWN_BATCH, _spawn_queue.size())
	for i in batch:
		if alive_enemy_count() >= BalanceS.ALIVE_CAP:
			return
		_spawn_next()


func _spawn_next() -> void:
	if _spawn_queue.is_empty():
		return
	var kind: String = _spawn_queue.pop_back()
	_spawn_enemy(kind, _edge_point())


func _spawn_enemy(kind: String, pos: Vector2) -> void:
	var e := EnemyS.new()
	e.position = pos
	e.z_index = 3
	add_child(e)
	e.setup(kind, wave, self)
	enemies.append(e)


func _spawn_boss() -> void:
	boss = BossS.new()
	boss.arena = self
	boss.position = Vector2(BalanceS.DESIGN_W * 0.5, BalanceS.ARENA_RECT.position.y + 120.0)
	boss.z_index = 4
	add_child(boss)
	fx.shake(8.0)


func _edge_point() -> Vector2:
	var rect := BalanceS.ARENA_RECT
	var inset := 22.0
	match rng.randi_range(0, 3):
		0:
			return Vector2(rng.randf_range(rect.position.x, rect.end.x), rect.position.y + inset)
		1:
			return Vector2(rng.randf_range(rect.position.x, rect.end.x), rect.end.y - inset)
		2:
			return Vector2(rect.position.x + inset, rng.randf_range(rect.position.y, rect.end.y))
		_:
			return Vector2(rect.end.x - inset, rng.randf_range(rect.position.y, rect.end.y))


func _check_cleared() -> void:
	if state != "fight":
		return
	if _is_boss_wave:
		return
	if _spawn_queue.is_empty() and enemies.is_empty():
		state = "cleared"
		_inter_t = 1.2
		run.heal_fraction(BalanceS.WAVE_HEAL_PCT)
		fx.floater(hero.position + Vector2(0, -26), "WAVE CLEAR  +HP", Color(0.5, 1.0, 0.7), 17)


# ---------------------------------------------------------------- stepping


func _step_entities(dt: float) -> void:
	if hero.alive:
		var move := _move_input()
		var aim := Vector2.ZERO
		if run.autoplay:
			move = _bot_move()
		elif joy_aim != null and joy_aim.active:
			aim = joy_aim.vec
		hero.step(dt, move, aim)
	for e in enemies.duplicate():
		if e.alive:
			e.step(dt)
	if boss != null and boss.alive:
		boss.step(dt, hero)
		if run.hp < run.max_hp * 0.5:
			run.boss_flawless = false
	_step_bullets(dt)
	for h in hazards.duplicate():
		h.step(dt)
	_cleanup()


func _move_input() -> Vector2:
	var v := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
		v.y -= 1.0
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
		v.y += 1.0
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		v.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		v.x += 1.0
	if joy_move != null and joy_move.active:
		v += joy_move.vec
	return v.limit_length(1.0)


func _step_bullets(dt: float) -> void:
	for b in bullets.duplicate():
		if not b.alive:
			continue
		b.step(dt)
		if b.alive:
			_bullet_hit_pass(b)
	for b in enemy_bullets.duplicate():
		if not b.alive:
			continue
		b.step(dt)
		if b.alive and hero.alive:
			if b.position.distance_to(hero.position) < b.radius + hero.radius():
				b.alive = false
				hero.take_damage(b.dmg)


func _bullet_hit_pass(b) -> void:
	## Also runs once at spawn: bullets spawn ahead of the muzzle, so a
	## point-blank enemy would otherwise sit in a dead zone between the hero
	## and the first post-move collision check and never get hit.
	var targets: Array = enemies.duplicate()
	if boss != null and boss.alive:
		targets.append(boss)
	for e in targets:
		if not e.alive or not b.alive:
			continue
		if e.get("spawn_t") != null and e.spawn_t > 0.0:
			continue
		var id: int = e.get_instance_id()
		if b.already_hit(id):
			continue
		if b.position.distance_to(e.position) < b.radius + e.radius:
			b.mark_hit(id)
			var crit: bool = rng.randf() < run.crit_chance
			var dmg: float = b.dmg * (run.crit_mult if crit else 1.0)
			if run.executioner and e.is_elite:
				dmg *= 1.25
			e.take_hit(dmg, crit)
			Sfx.play("hit", 0.15, -10.0)
			if b.pierce_left > 0:
				b.pierce_left -= 1
			else:
				b.alive = false


func _cleanup() -> void:
	enemies = _filter_alive(enemies)
	bullets = _filter_alive(bullets)
	enemy_bullets = _filter_alive(enemy_bullets)
	var keep_h: Array = []
	for h in hazards:
		if h.done:
			h.queue_free()
		else:
			keep_h.append(h)
	hazards = keep_h
	if boss != null and not boss.alive:
		boss.queue_free()
		boss = null


func _filter_alive(list: Array) -> Array:
	var keep: Array = []
	for item in list:
		if item.alive:
			keep.append(item)
		else:
			item.queue_free()
	return keep


# ---------------------------------------------------------------- services


func nearest_enemy(from: Vector2):
	var best = null
	var best_d := INF
	for e in enemies:
		if not e.alive or e.spawn_t > 0.0:
			continue
		var d := from.distance_squared_to(e.position)
		if d < best_d:
			best_d = d
			best = e
	if boss != null and boss.alive:
		var d := from.distance_squared_to(boss.position)
		if d < best_d:
			best = boss
	return best


func alive_enemy_count() -> int:
	return enemies.size()


func random_arena_point() -> Vector2:
	var rect := BalanceS.ARENA_RECT.grow(-60.0)
	return Vector2(
		rng.randf_range(rect.position.x, rect.end.x), rng.randf_range(rect.position.y, rect.end.y)
	)


func spawn_bullet(pos: Vector2, vel: Vector2, dmg: float, radius: float, pierce: int) -> void:
	var b := BulletS.new()
	b.position = pos
	b.vel = vel
	b.dmg = dmg
	b.radius = radius
	b.pierce_left = pierce
	b.z_index = 4
	add_child(b)
	bullets.append(b)
	# Point-blank targets overlap the muzzle position; resolve immediately.
	_bullet_hit_pass(b)


func spawn_enemy_bullet(pos: Vector2, vel: Vector2, dmg: float) -> void:
	var b := BulletS.new()
	b.position = pos
	b.vel = vel
	b.dmg = dmg
	b.radius = 5.0
	b.hostile = true
	b.z_index = 4
	add_child(b)
	enemy_bullets.append(b)


func spawn_summons(count: int) -> void:
	for i in count:
		if alive_enemy_count() >= 26:
			return
		_spawn_enemy("peon", _edge_point())


func spawn_hazard(pos: Vector2) -> void:
	var h := HazardS.new()
	h.arena = self
	h.position = pos
	h.z_index = 1
	add_child(h)
	hazards.append(h)


# ---------------------------------------------------------------- events


func on_enemy_died(e) -> void:
	run.kills += 1
	if e.is_elite:
		run.elite_kills += 1
		var drop: int = e.ball_drop
		run.balls += drop
		fx.floater(
			e.position + Vector2(0, -e.radius - 8),
			"+%s" % BalanceS.fmt(drop),
			Color(1.0, 0.82, 0.24),
			18
		)
		fx.burst(e.position, Color(1.0, 0.82, 0.24), 14, 160.0)
		Sfx.play("elite_die", 0.06)
		if run.frenzy:
			hero.frenzy_t = 4.0
		if run.executioner:
			for other in enemies.duplicate():
				if other != e and other.alive:
					if other.position.distance_to(e.position) < 80.0:
						other.take_hit(60.0, false)
	else:
		fx.burst(e.position, Color(1.0, 0.42, 0.4), 7, 110.0)
		Sfx.play("peon_die", 0.2, -6.0)


func on_boss_died() -> void:
	run.balls += BalanceS.BOSS_BALL_DROP
	fx.shake(14.0)
	fx.floater(
		boss.position,
		"+%s BALLS" % BalanceS.fmt(BalanceS.BOSS_BALL_DROP),
		Color(1.0, 0.82, 0.24),
		24
	)
	fx.burst(boss.position, Color(1.0, 0.6, 0.3), 40, 260.0)
	for e in enemies:
		e.alive = false
	for b in enemy_bullets:
		b.alive = false
	state = "boss_dead"
	_end_t = 1.4
	Sfx.play("elite_die")


func on_hero_died() -> void:
	fx.shake(12.0)
	fx.burst(hero.position, Color(0.45, 0.85, 1.0), 30, 240.0)
	state = "hero_dead"
	_end_t = 1.2


func _print_stall_state() -> void:
	## Autoplay diagnostics: if a wave runs long, dump who is still alive so
	## CI logs identify the unkillable entity / stuck state exactly.
	var parts := PackedStringArray()
	for e in enemies:
		parts.append(
			(
				"%s hp%.0f sp%.2f al%s @(%.0f,%.0f)"
				% [e.kind, e.hp, e.spawn_t, e.alive, e.position.x, e.position.y]
			)
		)
	print(
		(
			(
				"AUTOPLAY-STALL: w%d t=%.0fs st=%s q=%d bl=%d hero=(%.0f,%.0f) "
				+ "alive=%s god=%s hp=%.0f acc=%.2f aim=(%.2f,%.2f) tgt=%s | %s"
			)
			% [
				wave,
				_wave_t,
				state,
				_spawn_queue.size(),
				bullets.size(),
				hero.position.x,
				hero.position.y,
				hero.alive,
				hero.god,
				run.hp,
				hero._fire_acc,
				hero._aim.x,
				hero._aim.y,
				nearest_enemy(hero.position) != null,
				", ".join(parts),
			]
		)
	)


# ---------------------------------------------------------------- autoplay bot


func _bot_move() -> Vector2:
	var pos: Vector2 = hero.position
	var flee := Vector2.ZERO
	for e in enemies:
		if not e.alive:
			continue
		var d := pos.distance_to(e.position)
		if d < 150.0:
			flee += (pos - e.position).normalized() * ((150.0 - d) / 150.0)
	if boss != null and boss.alive:
		var d := pos.distance_to(boss.position)
		if d < 260.0:
			flee += (pos - boss.position).normalized() * ((260.0 - d) / 260.0) * 1.5
	for b in enemy_bullets:
		var d := pos.distance_to(b.position)
		if d < 100.0:
			flee += (pos - b.position).normalized() * ((100.0 - d) / 100.0) * 1.2
	for h in hazards:
		if h.warn_left <= 0.0 and not h.done:
			var d := pos.distance_to(h.position)
			if d < BalanceS.HAZARD_RADIUS + 30.0:
				flee += (pos - h.position).normalized() * 1.5
	var to_center := (Vector2(240.0, 480.0) - pos) * 0.004
	var tangent := flee.rotated(PI * 0.5) * 0.35
	var extra := Vector2.ZERO
	var near_e = nearest_enemy(pos)
	if near_e != null:
		var nd := pos.distance_to(near_e.position)
		if flee.length() < 0.3 and nd < 150.0:
			# Surrounded: symmetric threats cancel out — break out sideways.
			extra = (pos - near_e.position).normalized().rotated(PI * 0.5) * 1.2
		elif flee.length() < 0.01 and nd > 230.0:
			# Nothing pressuring us: close distance so shots fly shorter.
			extra = (near_e.position - pos).normalized() * 0.7
	# Never let flee pin us into walls/corners.
	var rect := BalanceS.ARENA_RECT
	var wall := Vector2.ZERO
	if pos.x - rect.position.x < 70.0:
		wall.x += 1.0
	if rect.end.x - pos.x < 70.0:
		wall.x -= 1.0
	if pos.y - rect.position.y < 70.0:
		wall.y += 1.0
	if rect.end.y - pos.y < 70.0:
		wall.y -= 1.0
	return (flee * 1.4 + to_center + tangent + extra + wall * 1.1).limit_length(1.0)


# ---------------------------------------------------------------- drawing


func _draw() -> void:
	var rect := BalanceS.ARENA_RECT
	# Subtle grid.
	var grid := Color(1, 1, 1, 0.035)
	var x := rect.position.x
	while x <= rect.end.x:
		draw_line(Vector2(x, rect.position.y), Vector2(x, rect.end.y), grid, 1.0)
		x += 56.0
	var y := rect.position.y
	while y <= rect.end.y:
		draw_line(Vector2(rect.position.x, y), Vector2(rect.end.x, y), grid, 1.0)
		y += 56.0
	# Border glow.
	draw_rect(rect, Color(0.4, 0.7, 1.0, 0.22), false, 2.0)
	# Banner.
	if state == "banner":
		var font := ThemeDB.fallback_font
		var a := clampf(_banner_t / 0.4, 0.0, 1.0)
		var size := 36
		var w := font.get_string_size(_banner_text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		var pos := Vector2((BalanceS.DESIGN_W - w) * 0.5, BalanceS.DESIGN_H * 0.42)
		var col := Color(1.0, 0.35, 0.35, a) if _is_boss_wave else Color(1, 1, 1, a)
		draw_string(font, pos + Vector2(2, 2), _banner_text, 0, -1, size, Color(0, 0, 0, a * 0.6))
		draw_string(font, pos, _banner_text, 0, -1, size, col)
