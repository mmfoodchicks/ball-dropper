extends Node2D
## Telegraphed arena hazard used by the boss: a warning ring, then a burning
## zone that damages the hero while inside (GDD: boss "arena hazards").

const BalanceS := preload("res://src/balance.gd")

var arena = null
var warn_left := BalanceS.HAZARD_WARN_TIME
var active_left := BalanceS.HAZARD_ACTIVE_TIME
var done := false


func step(dt: float) -> void:
	if warn_left > 0.0:
		warn_left -= dt
	elif active_left > 0.0:
		active_left -= dt
		var hero = arena.hero
		if hero != null and hero.alive:
			if position.distance_to(hero.position) < BalanceS.HAZARD_RADIUS:
				hero.take_damage(BalanceS.HAZARD_DPS * dt, true)
	else:
		done = true
	queue_redraw()


func _draw() -> void:
	var r := BalanceS.HAZARD_RADIUS
	if warn_left > 0.0:
		var pulse := 0.5 + 0.5 * sin(warn_left * 18.0)
		draw_arc(Vector2.ZERO, r, 0, TAU, 40, Color(1.0, 0.45, 0.2, 0.35 + 0.3 * pulse), 3.0)
		draw_circle(Vector2.ZERO, r, Color(1.0, 0.4, 0.2, 0.07))
	elif not done:
		var a := clampf(active_left / BalanceS.HAZARD_ACTIVE_TIME, 0.0, 1.0)
		draw_circle(Vector2.ZERO, r, Color(1.0, 0.35, 0.15, 0.16 + 0.12 * a))
		draw_arc(Vector2.ZERO, r, 0, TAU, 40, Color(1.0, 0.5, 0.25, 0.5), 2.0)
		draw_circle(
			Vector2.ZERO, r * (0.3 + 0.1 * sin(active_left * 10.0)), Color(1.0, 0.5, 0.2, 0.2)
		)
