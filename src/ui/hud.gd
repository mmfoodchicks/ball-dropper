extends Control
## In-game HUD: wave counter, HP bar, ball bank, pause button, boss bar and
## the dropper-phase status row + DROP button. Pure display: reads run/arena/
## dropper references each frame; emits button presses to main.

signal pause_pressed
signal drop_pressed

const BalanceS := preload("res://src/balance.gd")

var run = null
var arena = null
var dropper = null

var _wave_label: Label
var _bank_label: Label
var _hp_bg: ColorRect
var _hp_fill: ColorRect
var _hp_text: Label
var _boss_row: Control
var _boss_fill: ColorRect
var _pause_btn: Button
var _drop_btn: Button
var _drop_info: Label
var _mode := "hidden"


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var bar := ColorRect.new()
	bar.color = Color(0.02, 0.03, 0.06, 0.88)
	bar.position = Vector2(0, 0)
	bar.size = Vector2(480, 78)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bar)

	_wave_label = _label(Vector2(14, 8), 17, Color(1, 1, 1))
	_bank_label = _label(Vector2(14, 44), 19, Color(1.0, 0.84, 0.3))

	_hp_bg = ColorRect.new()
	_hp_bg.color = Color(0, 0, 0, 0.55)
	_hp_bg.position = Vector2(206, 12)
	_hp_bg.size = Vector2(200, 20)
	_hp_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hp_bg)
	_hp_fill = ColorRect.new()
	_hp_fill.color = Color(0.36, 0.94, 0.55)
	_hp_fill.position = Vector2(208, 14)
	_hp_fill.size = Vector2(196, 16)
	_hp_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hp_fill)
	_hp_text = _label(Vector2(210, 13), 12, Color(0, 0, 0, 0.8))

	_pause_btn = Button.new()
	_pause_btn.text = "II"
	_pause_btn.position = Vector2(424, 8)
	_pause_btn.size = Vector2(44, 36)
	_pause_btn.add_theme_font_size_override("font_size", 16)
	_pause_btn.pressed.connect(func() -> void: pause_pressed.emit())
	add_child(_pause_btn)

	_boss_row = Control.new()
	_boss_row.position = Vector2(0, 82)
	_boss_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_boss_row)
	var boss_bg := ColorRect.new()
	boss_bg.color = Color(0, 0, 0, 0.6)
	boss_bg.position = Vector2(60, 2)
	boss_bg.size = Vector2(360, 12)
	boss_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_boss_row.add_child(boss_bg)
	_boss_fill = ColorRect.new()
	_boss_fill.color = Color(1.0, 0.35, 0.4)
	_boss_fill.position = Vector2(62, 4)
	_boss_fill.size = Vector2(356, 8)
	_boss_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_boss_row.add_child(_boss_fill)
	_boss_row.visible = false

	_drop_btn = Button.new()
	_drop_btn.text = "DROP"
	_drop_btn.position = Vector2(120, 770)
	_drop_btn.size = Vector2(240, 58)
	_drop_btn.add_theme_font_size_override("font_size", 24)
	_drop_btn.pressed.connect(func() -> void: drop_pressed.emit())
	add_child(_drop_btn)

	_drop_info = _label(Vector2(206, 44), 13, Color(0.8, 0.85, 0.95))
	set_mode("hidden")


func _label(pos: Vector2, size: int, color: Color) -> Label:
	var l := Label.new()
	l.position = pos
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	return l


func set_mode(mode: String) -> void:
	_mode = mode
	visible = mode != "hidden"
	_drop_btn.visible = mode == "dropper"
	_drop_info.visible = mode == "dropper"
	_hp_bg.visible = mode == "combat"
	_hp_fill.visible = mode == "combat"
	_hp_text.visible = mode == "combat"
	_boss_row.visible = false


func _process(_delta: float) -> void:
	if run == null or _mode == "hidden":
		return
	_bank_label.text = "BALLS  %s" % BalanceS.fmt(run.balls)
	if _mode == "combat":
		_wave_label.text = "WAVE %d / %d" % [run.wave, BalanceS.WAVE_COUNT]
		var frac: float = run.hp_frac()
		_hp_fill.size.x = 196.0 * frac
		_hp_fill.color = (Color(0.36, 0.94, 0.55) if frac > 0.35 else Color(1.0, 0.45, 0.35))
		_hp_text.text = "%d / %d" % [int(ceil(run.hp)), int(run.max_hp)]
		var boss = arena.boss if arena != null else null
		_boss_row.visible = boss != null
		if boss != null:
			_boss_fill.size.x = 356.0 * clampf(boss.hp / boss.max_hp, 0.0, 1.0)
	elif _mode == "dropper" and dropper != null:
		_wave_label.text = "DROPPER"
		var s: Dictionary = dropper.status()
		match s["phase"]:
			"aim":
				_drop_btn.disabled = false
				_drop_btn.text = "DROP %s" % BalanceS.fmt(run.balls)
				_drop_info.text = "Drag to aim, then drop!"
			"dropping":
				_drop_btn.disabled = true
				_drop_btn.text = "DROPPING..."
				_drop_info.text = (
					"In play %s   Banked %s"
					% [BalanceS.fmt(s["in_flight"]), BalanceS.fmt(s["collected"])]
				)
			_:
				_drop_btn.disabled = true
				_drop_btn.text = "DONE"
				_drop_info.text = "Banked %s" % BalanceS.fmt(s["collected"])
