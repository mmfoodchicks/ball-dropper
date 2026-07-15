extends Node
## Autoload "Meta": persistent currencies (gold, materials), permanent upgrade
## levels, high-tier unlocks, settings, and lifetime stats. Saved as JSON in
## user:// so it survives between sessions on device.

const BalanceS := preload("res://src/balance.gd")

const SAVE_VERSION := 1

var save_path := "user://orbfall_save.json"

var gold := 0
var materials := 0
var upgrade_levels := {}
var unlocks := {}
var selected_character := "ranger"
var muted := false
var best_wave := 0
var runs_played := 0
var runs_won := 0


func _ready() -> void:
	load_save()


# ---------------------------------------------------------------- persistence


func load_save() -> void:
	if not FileAccess.file_exists(save_path):
		return
	var f := FileAccess.open(save_path, FileAccess.READ)
	if f == null:
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var data: Dictionary = parsed
	gold = int(data.get("gold", 0))
	materials = int(data.get("materials", 0))
	upgrade_levels = data.get("upgrade_levels", {})
	unlocks = data.get("unlocks", {})
	selected_character = str(data.get("selected_character", "ranger"))
	muted = bool(data.get("muted", false))
	best_wave = int(data.get("best_wave", 0))
	runs_played = int(data.get("runs_played", 0))
	runs_won = int(data.get("runs_won", 0))


func save() -> void:
	var data := {
		"version": SAVE_VERSION,
		"gold": gold,
		"materials": materials,
		"upgrade_levels": upgrade_levels,
		"unlocks": unlocks,
		"selected_character": selected_character,
		"muted": muted,
		"best_wave": best_wave,
		"runs_played": runs_played,
		"runs_won": runs_won,
	}
	var f := FileAccess.open(save_path, FileAccess.WRITE)
	if f == null:
		push_warning("Orbfall: could not write save file at %s" % save_path)
		return
	f.store_string(JSON.stringify(data, "  "))


func wipe() -> void:
	gold = 0
	materials = 0
	upgrade_levels = {}
	unlocks = {}
	selected_character = "ranger"
	best_wave = 0
	runs_played = 0
	runs_won = 0
	save()


# ---------------------------------------------------------------- queries


func upgrade_level(id: String) -> int:
	return int(upgrade_levels.get(id, 0))


func has_unlock(id: String) -> bool:
	return bool(unlocks.get(id, false))


func snapshot_levels() -> Dictionary:
	return upgrade_levels.duplicate()


func snapshot_unlocks() -> Dictionary:
	return unlocks.duplicate()


func character_available(id: String) -> bool:
	var cfg: Dictionary = BalanceS.CHARACTERS.get(id, {})
	var req: String = cfg.get("unlock", "")
	return req == "" or has_unlock(req)


# ---------------------------------------------------------------- mutations


func add_rewards(gold_amount: int, material_amount: int) -> void:
	gold += maxi(0, gold_amount)
	materials += maxi(0, material_amount)
	save()


func record_run(wave_reached: int, won: bool) -> void:
	runs_played += 1
	if won:
		runs_won += 1
	best_wave = maxi(best_wave, wave_reached)
	save()


func buy_upgrade(id: String) -> bool:
	for def: Dictionary in BalanceS.META_UPGRADES:
		if def["id"] != id:
			continue
		var lvl := upgrade_level(id)
		if lvl >= int(def["max"]):
			return false
		var cost := BalanceS.meta_cost(def, lvl)
		if gold < cost:
			return false
		gold -= cost
		upgrade_levels[id] = lvl + 1
		save()
		return true
	return false


func buy_unlock(id: String) -> bool:
	for def: Dictionary in BalanceS.META_UNLOCKS:
		if def["id"] != id:
			continue
		if has_unlock(id):
			return false
		var cost := int(def["cost"])
		if materials < cost:
			return false
		materials -= cost
		unlocks[id] = true
		save()
		return true
	return false


func set_muted(value: bool) -> void:
	muted = value
	save()


func set_character(id: String) -> void:
	if character_available(id):
		selected_character = id
		save()
