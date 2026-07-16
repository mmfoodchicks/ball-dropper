extends Node2D
## A projectile. Player bullets can pierce; hostile bullets hurt the hero.
## Movement/collision is stepped by the arena so pausing and turbo mode stay
## deterministic.

const BalanceS := preload("res://src/balance.gd")

var vel := Vector2.ZERO
var dmg := 10.0
var radius := 4.0
var pierce_left := 0
var hostile := false
var alive := true
var can_ricochet := false
var ricocheted := false
var can_split := false
var is_shard := false

var _hit_ids := {}
var _tex: Texture2D = null


func _ready() -> void:
	var path := (
		"res://assets/sprites/bullet_enemy.png"
		if hostile
		else "res://assets/sprites/bullet_player.png"
	)
	if ResourceLoader.exists(path):
		_tex = load(path)


func step(dt: float) -> void:
	position += vel * dt
	if can_ricochet and not ricocheted and not hostile:
		var r := BalanceS.ARENA_RECT
		var bounced := false
		if position.x < r.position.x or position.x > r.end.x:
			vel.x = -vel.x
			bounced = true
		if position.y < r.position.y or position.y > r.end.y:
			vel.y = -vel.y
			bounced = true
		if bounced:
			ricocheted = true
			position.x = clampf(position.x, r.position.x, r.end.x)
			position.y = clampf(position.y, r.position.y, r.end.y)
			return
	var bounds := BalanceS.ARENA_RECT.grow(40.0)
	if not bounds.has_point(position):
		alive = false


func already_hit(id: int) -> bool:
	return _hit_ids.has(id)


func mark_hit(id: int) -> void:
	_hit_ids[id] = true


func _draw() -> void:
	if _tex != null:
		var side := _tex.get_width() / 4.0 * (radius / 4.0)
		draw_texture_rect(_tex, Rect2(-side * 0.5, -side * 0.5, side, side), false)
		return
	if hostile:
		draw_circle(Vector2.ZERO, radius + 3.0, Color(1.0, 0.35, 0.45, 0.25))
		draw_circle(Vector2.ZERO, radius, Color(1.0, 0.45, 0.55))
		draw_circle(Vector2.ZERO, radius * 0.45, Color(1.0, 0.85, 0.9))
	else:
		draw_circle(Vector2.ZERO, radius + 3.0, Color(1.0, 0.9, 0.4, 0.22))
		draw_circle(Vector2.ZERO, radius, Color(1.0, 0.93, 0.55))
		draw_circle(Vector2.ZERO, radius * 0.45, Color(1, 1, 1))
