extends Node
## Root orchestrator. Owns the GDD core loop as a state machine:
##   title -> combat (waves) -> dropper (after 5/10) -> upgrade -> combat ...
##         -> boss (wave 15) -> victory/defeat -> meta -> title
##
## Command-line flags (after "--") for headless verification:
##   --autoplay      bot plays the run (kite + auto-aim + auto menus)
##   --god           hero ignores damage (loop verification, not balance)
##   --turbo         steps the sim 8x per frame
##   --quit-on-end   print AUTOPLAY_RESULT json and quit when the run ends

const BalanceS := preload("res://src/balance.gd")
const RunStateS := preload("res://src/run_state.gd")
const UpgradePoolS := preload("res://src/upgrades.gd")
const ArenaS := preload("res://src/combat/arena.gd")
const DropperS := preload("res://src/dropper/dropper.gd")
const HudS := preload("res://src/ui/hud.gd")
const ScreensS := preload("res://src/ui/screens.gd")
const JoystickS := preload("res://src/ui/joystick.gd")

const TURBO_STEPS := 8

var run = null
var arena = null
var dropper = null
var state := "title"

var hud = null
var screens = null
var joy_move = null
var joy_aim = null

var autoplay := false
var god_mode := false
var turbo := false
var quit_on_end := false
var current_offer: Array = []

var _rng := RandomNumberGenerator.new()
var _auto_t := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.randomize()
	# Flags after "--" land in get_cmdline_user_args(), not get_cmdline_args().
	var args := OS.get_cmdline_args()
	args.append_array(OS.get_cmdline_user_args())
	autoplay = "--autoplay" in args
	god_mode = "--god" in args
	turbo = "--turbo" in args
	quit_on_end = "--quit-on-end" in args

	# main stays ALWAYS so the pause overlay keeps working, but everything
	# gameplay-facing must explicitly be PAUSABLE or it would inherit ALWAYS
	# and keep simulating while paused.
	var ui := CanvasLayer.new()
	ui.layer = 10
	ui.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(ui)

	joy_move = JoystickS.new()
	joy_move.left_side = true
	ui.add_child(joy_move)
	joy_aim = JoystickS.new()
	joy_aim.left_side = false
	ui.add_child(joy_aim)

	hud = HudS.new()
	ui.add_child(hud)
	hud.pause_pressed.connect(_on_pause_pressed)
	hud.drop_pressed.connect(_on_drop_pressed)

	screens = ScreensS.new()
	ui.add_child(screens)
	screens.start_requested.connect(start_run)
	screens.upgrade_chosen.connect(_on_upgrade_chosen)
	screens.reroll_requested.connect(_on_reroll)
	screens.result_continue.connect(_on_result_continue)
	screens.gameover_retry.connect(_on_gameover_retry)
	screens.gameover_menu.connect(_go_title)
	screens.victory_menu.connect(_go_title)
	screens.resume_pressed.connect(_on_resume)
	screens.quit_pressed.connect(_on_abandon)

	_set_joysticks(false)
	_go_title()


func _go_title() -> void:
	state = "title"
	hud.set_mode("hidden")
	_set_joysticks(false)
	screens.show_title()


func _set_joysticks(shown: bool) -> void:
	joy_move.visible = shown
	joy_aim.visible = shown
	joy_move.reset()
	joy_aim.reset()


# ---------------------------------------------------------------- run flow


func start_run(character_id: String) -> void:
	run = RunStateS.build(character_id, Meta.snapshot_levels(), Meta.snapshot_unlocks())
	run.autoplay = autoplay
	_enter_combat(1)


func _enter_combat(wave: int) -> void:
	state = "combat"
	run.wave = wave
	if autoplay:
		print(
			(
				"AUTOPLAY: wave %d (balls %d, hp %d, upgrades %s)"
				% [wave, run.balls, int(run.hp), run.picked_upgrades]
			)
		)
	screens.hide_all()
	arena = ArenaS.new()
	arena.run = run
	arena.joy_move = joy_move
	arena.joy_aim = joy_aim
	arena.external_stepping = turbo
	arena.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(arena)
	arena.hero.god = god_mode
	arena.dropper_ready.connect(_on_dropper_ready)
	arena.boss_defeated.connect(_on_boss_defeated)
	arena.hero_down.connect(_on_hero_down)
	hud.run = run
	hud.arena = arena
	hud.set_mode("combat")
	_set_joysticks(not autoplay)


func _on_dropper_ready(_wave: int) -> void:
	_free_arena()
	state = "dropper"
	_set_joysticks(false)
	dropper = DropperS.new()
	dropper.run = run
	dropper.external_stepping = turbo
	dropper.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(dropper)
	dropper.finished.connect(_on_dropper_finished)
	hud.dropper = dropper
	hud.set_mode("dropper")


func _on_drop_pressed() -> void:
	if dropper != null:
		dropper.begin_drop()


func _on_dropper_finished(result: Dictionary) -> void:
	run.balls = int(result["final"])
	run.bonus_gold += int(result["gold"])
	if autoplay:
		print(
			(
				"AUTOPLAY: dropper %d -> %d (x%.2f)"
				% [int(result["start"]), int(result["final"]), float(result["mult"])]
			)
		)
	state = "result"
	hud.set_mode("hidden")
	screens.show_result(result)


func _on_result_continue() -> void:
	_free_dropper()
	_open_upgrades()


func _open_upgrades() -> void:
	state = "upgrade"
	run.rerolls_this_phase = 0
	var count := 4 if Meta.has_unlock("fourth") else 3
	current_offer = UpgradePoolS.roll_offer(_rng, run, count)
	screens.show_upgrades(current_offer, run.balls, BalanceS.reroll_cost(run.wave, 0))


func _on_reroll() -> void:
	var cost := BalanceS.reroll_cost(run.wave, run.rerolls_this_phase)
	if run.balls < cost:
		return
	run.balls -= cost
	run.rerolls_this_phase += 1
	Sfx.play("reroll")
	var count := 4 if Meta.has_unlock("fourth") else 3
	current_offer = UpgradePoolS.roll_offer(_rng, run, count)
	screens.show_upgrades(
		current_offer, run.balls, BalanceS.reroll_cost(run.wave, run.rerolls_this_phase)
	)


func _on_upgrade_chosen(upgrade_id: String) -> void:
	UpgradePoolS.apply(run, upgrade_id)
	Sfx.play("upgrade")
	_enter_combat(run.wave + 1)


func _on_boss_defeated() -> void:
	var conversion := int(run.balls * 0.10 * (1.0 + run.golden_touch))
	var performance := int(round(200.0 * run.hp_frac()))
	var gold := BalanceS.victory_gold(run.balls, run.hp_frac(), run.golden_touch)
	gold += run.bonus_gold
	var mats := BalanceS.victory_materials(run.boss_flawless)
	Meta.add_rewards(gold, mats)
	Meta.record_run(BalanceS.WAVE_COUNT, true)
	var lines := [
		["waves cleared", "+%d" % (BalanceS.WAVE_COUNT * 12)],
		["boss bonus", "+300"],
		["ball conversion", "+%d" % conversion],
		["performance", "+%d" % performance],
	]
	if run.bonus_gold > 0:
		lines.append(["??? gates", "+%d" % run.bonus_gold])
	if run.boss_flawless:
		lines.append(["flawless boss", "+1 material"])
	_free_arena()
	state = "victory"
	hud.set_mode("hidden")
	_set_joysticks(false)
	Sfx.jingle_win()
	screens.show_victory({"gold": gold, "mats": mats, "lines": lines})


func _on_hero_down() -> void:
	var gold: int = BalanceS.defeat_gold(run.wave, run.balls) + run.bonus_gold
	Meta.add_rewards(gold, 0)
	Meta.record_run(run.wave, false)
	_free_arena()
	state = "gameover"
	hud.set_mode("hidden")
	_set_joysticks(false)
	Sfx.jingle_lose()
	screens.show_gameover(run.wave, gold)


func _on_gameover_retry() -> void:
	start_run(run.character_id)


# ---------------------------------------------------------------- pause


func _on_pause_pressed() -> void:
	if state != "combat" and state != "dropper":
		return
	get_tree().paused = true
	screens.show_pause()


func _on_resume() -> void:
	get_tree().paused = false
	screens.hide_all()


func _on_abandon() -> void:
	get_tree().paused = false
	var gold: int = BalanceS.defeat_gold(run.wave, run.balls) + run.bonus_gold
	Meta.add_rewards(gold, 0)
	Meta.record_run(run.wave, false)
	_free_arena()
	_free_dropper()
	_go_title()


# ---------------------------------------------------------------- lifecycle


func _free_arena() -> void:
	if arena != null:
		arena.queue_free()
		arena = null
	hud.arena = null


func _free_dropper() -> void:
	if dropper != null:
		dropper.queue_free()
		dropper = null
	hud.dropper = null


func _physics_process(delta: float) -> void:
	if get_tree().paused:
		return
	if turbo:
		var target = arena if arena != null else dropper
		if target != null:
			for i in TURBO_STEPS:
				target.step(1.0 / 60.0)
	if autoplay:
		_autoplay_screens(delta)


# ---------------------------------------------------------------- autoplay


func _autoplay_screens(delta: float) -> void:
	if state == "combat" or state == "dropper":
		_auto_t = 0.0
		return
	_auto_t += delta
	if _auto_t < 0.35:
		return
	_auto_t = 0.0
	match state:
		"title":
			start_run(Meta.selected_character)
		"result":
			_on_result_continue()
		"upgrade":
			if not current_offer.is_empty():
				var pick: Dictionary = current_offer[_rng.randi_range(0, current_offer.size() - 1)]
				_on_upgrade_chosen(str(pick["id"]))
		"victory":
			_finish_autoplay(true)
		"gameover":
			_finish_autoplay(false)


func _finish_autoplay(won: bool) -> void:
	if quit_on_end:
		var summary := {
			"won": won,
			"wave": run.wave,
			"balls": run.balls,
			"gold": Meta.gold,
			"materials": Meta.materials,
			"kills": run.kills,
			"elite_kills": run.elite_kills,
			"upgrades": run.picked_upgrades,
		}
		print("AUTOPLAY_RESULT %s" % JSON.stringify(summary))
		get_tree().quit(0 if won else 1)
	else:
		_go_title()
