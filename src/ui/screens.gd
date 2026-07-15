extends Control
## All full-screen UI panels, built in code: title / upgrade choice / dropper
## result / game over / victory / meta shop / pause. Panels that show live
## data are rebuilt every time they open. Run-flow decisions are emitted as
## signals for main.gd; pure-meta interactions (shop, character select,
## sound) talk to the Meta autoload directly.

signal start_requested(character_id)
signal upgrade_chosen(upgrade_id)
signal reroll_requested
signal result_continue
signal gameover_retry
signal gameover_menu
signal victory_menu
signal resume_pressed
signal quit_pressed

const BalanceS := preload("res://src/balance.gd")
const UpgradePoolS := preload("res://src/upgrades.gd")

const CAT_COLORS := {
	"weapon": Color(1.0, 0.82, 0.24),
	"passive": Color(0.45, 0.95, 0.55),
	"utility": Color(0.45, 0.75, 1.0),
	"dropper": Color(0.8, 0.55, 1.0),
	"synergy": Color(1.0, 0.5, 0.75),
}

var _panels := {}
var _boxes := {}
var _wipe_armed := false


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	for panel_name in ["title", "upgrade", "result", "gameover", "victory", "shop", "pause"]:
		_build_screen(panel_name)
	show_only("")


func show_only(panel_name: String) -> void:
	for key: String in _panels:
		_panels[key].visible = key == panel_name


# ---------------------------------------------------------------- builders


func _build_screen(panel_name: String) -> void:
	var screen := Control.new()
	screen.name = panel_name
	screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	screen.visible = false
	add_child(screen)

	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.025, 0.05, 0.82)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	screen.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	screen.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(420, 0)
	panel.add_theme_stylebox_override("panel", _panel_style())
	center.add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)

	_panels[panel_name] = screen
	_boxes[panel_name] = box


func _panel_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.062, 0.086, 0.16)
	sb.border_color = Color(0.17, 0.23, 0.36)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(12)
	sb.content_margin_left = 18.0
	sb.content_margin_right = 18.0
	sb.content_margin_top = 16.0
	sb.content_margin_bottom = 16.0
	return sb


func _btn_style(bg: Color, border: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(10)
	sb.content_margin_left = 12.0
	sb.content_margin_right = 12.0
	sb.content_margin_top = 8.0
	sb.content_margin_bottom = 8.0
	return sb


func _button(text: String, size: int, border := Color(0.3, 0.42, 0.65)) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", size)
	b.add_theme_stylebox_override("normal", _btn_style(Color(0.1, 0.14, 0.26), border))
	b.add_theme_stylebox_override("hover", _btn_style(Color(0.13, 0.19, 0.34), border))
	b.add_theme_stylebox_override("pressed", _btn_style(Color(0.08, 0.11, 0.2), border))
	b.add_theme_stylebox_override(
		"disabled", _btn_style(Color(0.07, 0.09, 0.15), Color(0.18, 0.22, 0.3))
	)
	b.add_theme_color_override("font_disabled_color", Color(0.5, 0.55, 0.65))
	b.pressed.connect(func() -> void: Sfx.play("button", 0.05, -8.0))
	return b


func _label(text: String, size: int, color := Color(0.88, 0.92, 1.0)) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


func _clear(box: VBoxContainer) -> void:
	for child in box.get_children():
		box.remove_child(child)
		child.queue_free()


func _spacer(box: VBoxContainer, h: float) -> void:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	box.add_child(c)


# ---------------------------------------------------------------- title


func show_title() -> void:
	var box: VBoxContainer = _boxes["title"]
	_clear(box)
	_wipe_armed = false

	box.add_child(_label("ORBFALL", 42, Color(1.0, 0.84, 0.3)))
	box.add_child(_label("A R E N A", 18, Color(0.6, 0.7, 0.9)))
	box.add_child(_label("15 waves. 2 dropper boards. 1 boss.", 12, Color(0.55, 0.6, 0.75)))
	_spacer(box, 6)
	box.add_child(
		_label("GOLD %d      MATERIALS %d" % [Meta.gold, Meta.materials], 15, Color(1.0, 0.84, 0.3))
	)
	box.add_child(
		_label(
			(
				"best wave %d  ·  runs %d  ·  wins %d"
				% [Meta.best_wave, Meta.runs_played, Meta.runs_won]
			),
			12,
			Color(0.55, 0.6, 0.75)
		)
	)
	_spacer(box, 8)

	var chars := HBoxContainer.new()
	chars.add_theme_constant_override("separation", 10)
	chars.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(chars)
	for char_id: String in BalanceS.CHARACTERS:
		var cfg: Dictionary = BalanceS.CHARACTERS[char_id]
		var available: bool = Meta.character_available(char_id)
		var selected: bool = Meta.selected_character == char_id
		var border := Color(1.0, 0.84, 0.3) if selected else Color(0.3, 0.42, 0.65)
		var text: String = cfg["name"] if available else "%s (locked)" % cfg["name"]
		var b := _button(text, 15, border)
		b.disabled = not available
		b.custom_minimum_size = Vector2(150, 0)
		b.pressed.connect(_on_char_pressed.bind(char_id))
		chars.add_child(b)
	var sel_cfg: Dictionary = BalanceS.CHARACTERS.get(
		Meta.selected_character, BalanceS.CHARACTERS["ranger"]
	)
	box.add_child(_label(str(sel_cfg["blurb"]), 12, Color(0.55, 0.6, 0.75)))
	_spacer(box, 8)

	var start := _button("START RUN", 24, Color(1.0, 0.84, 0.3))
	start.pressed.connect(func() -> void: start_requested.emit(Meta.selected_character))
	box.add_child(start)

	var shop := _button("UPGRADE SHOP", 17)
	shop.pressed.connect(show_shop)
	box.add_child(shop)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(row)
	var snd := _button("SOUND: %s" % ("OFF" if Meta.muted else "ON"), 12)
	snd.pressed.connect(
		func() -> void:
			Meta.set_muted(not Meta.muted)
			show_title()
	)
	row.add_child(snd)
	var wipe := _button("WIPE SAVE", 12, Color(0.6, 0.3, 0.3))
	wipe.pressed.connect(_on_wipe_pressed.bind(wipe))
	row.add_child(wipe)

	show_only("title")


func _on_char_pressed(char_id: String) -> void:
	Meta.set_character(char_id)
	show_title()


func _on_wipe_pressed(btn: Button) -> void:
	if _wipe_armed:
		Meta.wipe()
		show_title()
	else:
		_wipe_armed = true
		btn.text = "SURE? TAP AGAIN"


# ---------------------------------------------------------------- upgrades


func show_upgrades(offer: Array, balls: int, reroll_cost: int) -> void:
	var box: VBoxContainer = _boxes["upgrade"]
	_clear(box)
	box.add_child(_label("CHOOSE 1 UPGRADE", 24, Color(1.0, 0.84, 0.3)))
	box.add_child(_label("BALLS  %s" % BalanceS.fmt(balls), 15, Color(1.0, 0.84, 0.3)))
	_spacer(box, 4)
	for def: Dictionary in offer:
		var cat := str(def["cat"])
		var cat_color: Color = CAT_COLORS.get(cat, Color.WHITE)
		var cat_name: String = UpgradePoolS.CATEGORY_NAMES.get(cat, cat.to_upper())
		var b := _button("%s\n%s\n[%s]" % [def["name"], def["desc"], cat_name], 15, cat_color)
		b.custom_minimum_size = Vector2(0, 88)
		b.pressed.connect(func() -> void: upgrade_chosen.emit(str(def["id"])))
		box.add_child(b)
	_spacer(box, 4)
	var reroll := _button("REROLL  (-%s balls)" % BalanceS.fmt(reroll_cost), 15)
	reroll.disabled = balls < reroll_cost
	reroll.pressed.connect(func() -> void: reroll_requested.emit())
	box.add_child(reroll)
	box.add_child(
		_label("Rerolls spend balls. Cost doubles each time.", 11, Color(0.55, 0.6, 0.75))
	)
	show_only("upgrade")


# ---------------------------------------------------------------- dropper result


func show_result(result: Dictionary) -> void:
	var box: VBoxContainer = _boxes["result"]
	_clear(box)
	box.add_child(_label("BOARD COMPLETE", 24, Color(1.0, 0.84, 0.3)))
	_spacer(box, 4)
	box.add_child(_label("dropped  %s" % BalanceS.fmt(result["start"]), 16))
	box.add_child(_label("returned  %s" % BalanceS.fmt(result["final"]), 26, Color(1.0, 0.84, 0.3)))
	var mult: float = result["mult"]
	var mult_color := Color(0.45, 0.95, 0.55) if mult >= 1.0 else Color(1.0, 0.5, 0.4)
	box.add_child(_label("overall  x%.2f" % mult, 18, mult_color))
	if int(result["gold"]) > 0:
		box.add_child(
			_label("+%d bonus gold (??? gate)" % int(result["gold"]), 14, Color(1.0, 0.9, 0.5))
		)
	_spacer(box, 6)
	var cont := _button("CONTINUE", 20, Color(1.0, 0.84, 0.3))
	cont.pressed.connect(func() -> void: result_continue.emit())
	box.add_child(cont)
	show_only("result")


# ---------------------------------------------------------------- run end


func show_gameover(wave: int, gold_earned: int) -> void:
	var box: VBoxContainer = _boxes["gameover"]
	_clear(box)
	box.add_child(_label("RUN OVER", 30, Color(1.0, 0.45, 0.4)))
	box.add_child(_label("you fell on wave %d" % wave, 15))
	box.add_child(_label("+%d gold" % gold_earned, 17, Color(1.0, 0.84, 0.3)))
	_spacer(box, 6)
	var retry := _button("TRY AGAIN", 20, Color(1.0, 0.84, 0.3))
	retry.pressed.connect(func() -> void: gameover_retry.emit())
	box.add_child(retry)
	var menu := _button("MENU", 16)
	menu.pressed.connect(func() -> void: gameover_menu.emit())
	box.add_child(menu)
	show_only("gameover")


func show_victory(rewards: Dictionary) -> void:
	var box: VBoxContainer = _boxes["victory"]
	_clear(box)
	box.add_child(_label("VICTORY", 34, Color(1.0, 0.84, 0.3)))
	box.add_child(_label("the arena is cleared", 13, Color(0.6, 0.7, 0.9)))
	_spacer(box, 4)
	for line: Array in rewards["lines"]:
		box.add_child(_label("%s  %s" % [line[0], line[1]], 14))
	_spacer(box, 2)
	box.add_child(_label("TOTAL  +%d GOLD" % int(rewards["gold"]), 20, Color(1.0, 0.84, 0.3)))
	box.add_child(_label("+%d MATERIALS" % int(rewards["mats"]), 16, Color(0.8, 0.55, 1.0)))
	_spacer(box, 6)
	var menu := _button("CONTINUE", 20, Color(1.0, 0.84, 0.3))
	menu.pressed.connect(func() -> void: victory_menu.emit())
	box.add_child(menu)
	show_only("victory")


# ---------------------------------------------------------------- shop


func show_shop() -> void:
	var box: VBoxContainer = _boxes["shop"]
	_clear(box)
	box.add_child(_label("UPGRADE SHOP", 24, Color(1.0, 0.84, 0.3)))
	box.add_child(
		_label("GOLD %d      MATERIALS %d" % [Meta.gold, Meta.materials], 15, Color(1.0, 0.84, 0.3))
	)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(390, 520)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 8)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)

	list.add_child(_label("— PERMANENT UPGRADES —", 14, Color(0.6, 0.7, 0.9)))
	for def: Dictionary in BalanceS.META_UPGRADES:
		var lvl: int = Meta.upgrade_level(str(def["id"]))
		var maxed: bool = lvl >= int(def["max"])
		var cost: int = BalanceS.meta_cost(def, lvl)
		var text := (
			"%s  [%d/%d]\n%s\n%s"
			% [
				def["name"],
				lvl,
				int(def["max"]),
				def["desc"],
				"MAXED" if maxed else "BUY: %d gold" % cost,
			]
		)
		var b := _button(text, 13, Color(1.0, 0.84, 0.3) if not maxed else Color(0.3, 0.35, 0.45))
		b.disabled = maxed or Meta.gold < cost
		b.pressed.connect(_on_buy_upgrade.bind(str(def["id"])))
		list.add_child(b)

	list.add_child(_label("— HIGH-TIER UNLOCKS —", 14, Color(0.8, 0.55, 1.0)))
	for def: Dictionary in BalanceS.META_UNLOCKS:
		var owned: bool = Meta.has_unlock(str(def["id"]))
		var text := (
			"%s\n%s\n%s"
			% [
				def["name"],
				def["desc"],
				"OWNED" if owned else "BUY: %d materials" % int(def["cost"])
			]
		)
		var b := _button(text, 13, Color(0.8, 0.55, 1.0) if not owned else Color(0.3, 0.35, 0.45))
		b.disabled = owned or Meta.materials < int(def["cost"])
		b.pressed.connect(_on_buy_unlock.bind(str(def["id"])))
		list.add_child(b)

	var back := _button("BACK", 17)
	back.pressed.connect(show_title)
	box.add_child(back)
	show_only("shop")


func _on_buy_upgrade(id: String) -> void:
	if Meta.buy_upgrade(id):
		Sfx.play("upgrade")
	show_shop()


func _on_buy_unlock(id: String) -> void:
	if Meta.buy_unlock(id):
		Sfx.play("upgrade")
	show_shop()


# ---------------------------------------------------------------- pause


func show_pause() -> void:
	var box: VBoxContainer = _boxes["pause"]
	_clear(box)
	box.add_child(_label("PAUSED", 26))
	_spacer(box, 4)
	var resume := _button("RESUME", 20, Color(1.0, 0.84, 0.3))
	resume.pressed.connect(func() -> void: resume_pressed.emit())
	box.add_child(resume)
	var snd := _button("SOUND: %s" % ("OFF" if Meta.muted else "ON"), 14)
	snd.pressed.connect(
		func() -> void:
			Meta.set_muted(not Meta.muted)
			show_pause()
	)
	box.add_child(snd)
	var quit := _button("ABANDON RUN", 14, Color(0.6, 0.3, 0.3))
	quit.pressed.connect(func() -> void: quit_pressed.emit())
	box.add_child(quit)
	show_only("pause")


func hide_all() -> void:
	show_only("")
