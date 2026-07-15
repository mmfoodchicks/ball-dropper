extends Control
## Dynamic virtual joystick. GDD mobile controls: left thumb = movement,
## right thumb = aim (or auto-aim when untouched). The stick appears where the
## thumb lands on its half of the screen. Mouse works too via Godot's
## emulate_touch_from_mouse, so the prototype is desktop-testable.

const RADIUS := 58.0
const DEADZONE := 0.16
const KNOB_R := 22.0

@export var left_side := true

var vec := Vector2.ZERO
var active := false

var _touch_index := -1
var _origin := Vector2.ZERO
var _knob := Vector2.ZERO


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


func _in_my_half(pos: Vector2) -> bool:
	var half_w := 480.0 * 0.5
	return pos.x < half_w if left_side else pos.x >= half_w


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed and _touch_index == -1 and _in_my_half(touch.position):
			_touch_index = touch.index
			_origin = touch.position
			_knob = touch.position
			active = true
			vec = Vector2.ZERO
			queue_redraw()
		elif not touch.pressed and touch.index == _touch_index:
			_release()
	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		if drag.index == _touch_index:
			var delta := (drag.position - _origin).limit_length(RADIUS)
			_knob = _origin + delta
			var raw := delta / RADIUS
			vec = Vector2.ZERO if raw.length() < DEADZONE else raw
			queue_redraw()


func _release() -> void:
	_touch_index = -1
	active = false
	vec = Vector2.ZERO
	queue_redraw()


func reset() -> void:
	_release()


func _draw() -> void:
	if not active:
		return
	draw_circle(_origin, RADIUS, Color(1, 1, 1, 0.06))
	draw_arc(_origin, RADIUS, 0, TAU, 40, Color(1, 1, 1, 0.22), 2.0)
	draw_circle(_knob, KNOB_R, Color(1, 1, 1, 0.16))
	draw_arc(_knob, KNOB_R, 0, TAU, 24, Color(1, 1, 1, 0.4), 2.0)
