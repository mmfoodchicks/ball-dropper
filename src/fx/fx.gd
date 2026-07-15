extends Node2D
## Lightweight feedback layer: floating numbers, burst particles and screen
## shake. Owned by the arena / dropper; stepped explicitly by its owner so
## turbo mode and pausing stay deterministic.

var floaters: Array = []
var particles: Array = []
var shake_mag := 0.0

var _rng := RandomNumberGenerator.new()


func floater(pos: Vector2, text: String, color: Color, size := 16) -> void:
	floaters.append({"pos": pos, "text": text, "color": color, "size": size, "t": 0.0, "life": 0.9})


func burst(pos: Vector2, color: Color, count := 8, speed := 120.0) -> void:
	for i in count:
		var ang := _rng.randf() * TAU
		var vel := Vector2.from_angle(ang) * _rng.randf_range(speed * 0.4, speed)
		(
			particles
			. append(
				{
					"pos": pos,
					"vel": vel,
					"r": _rng.randf_range(1.5, 3.5),
					"color": color,
					"t": 0.0,
					"life": _rng.randf_range(0.25, 0.5),
				}
			)
		)


func shake(mag: float) -> void:
	shake_mag = maxf(shake_mag, mag)


func offset() -> Vector2:
	if shake_mag <= 0.05:
		return Vector2.ZERO
	return Vector2(_rng.randf_range(-shake_mag, shake_mag), _rng.randf_range(-shake_mag, shake_mag))


func step(dt: float) -> void:
	shake_mag = maxf(0.0, shake_mag - 26.0 * dt)
	var keep_f: Array = []
	for f: Dictionary in floaters:
		f["t"] += dt
		f["pos"] += Vector2(0, -46.0 * dt)
		if f["t"] < f["life"]:
			keep_f.append(f)
	floaters = keep_f
	var keep_p: Array = []
	for p: Dictionary in particles:
		p["t"] += dt
		p["pos"] += p["vel"] * dt
		p["vel"] *= 1.0 - 3.0 * dt
		if p["t"] < p["life"]:
			keep_p.append(p)
	particles = keep_p
	queue_redraw()


func clear() -> void:
	floaters.clear()
	particles.clear()
	shake_mag = 0.0
	queue_redraw()


func _draw() -> void:
	var font := ThemeDB.fallback_font
	for p: Dictionary in particles:
		var pa: float = 1.0 - p["t"] / p["life"]
		var pc: Color = p["color"]
		draw_circle(p["pos"], p["r"] * pa, Color(pc.r, pc.g, pc.b, pa))
	for f: Dictionary in floaters:
		var a := 1.0 - pow(f["t"] / f["life"], 2.0)
		var c: Color = f["color"]
		var text: String = f["text"]
		var size: int = f["size"]
		var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		var pos: Vector2 = f["pos"] - Vector2(w * 0.5, 0)
		draw_string(
			font,
			pos + Vector2(1, 1),
			text,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			size,
			Color(0, 0, 0, a * 0.6)
		)
		draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(c.r, c.g, c.b, a))
