extends SceneTree
## Scripted real-play balance simulation for the Jiange 3D slice.
## Plays all 5 waves through REAL gameplay paths only: the strategist is
## moved with the same move_to() command the right-click handler issues,
## chain lightning goes through _cast_chain_lightning(), towers are built
## with build_tower() at intermissions and the core is repaired with
## repair_core(), exactly like the UI buttons. No direct damage/HP writes
## to enemies, heroes or the core anywhere in this driver.
##
## Fixed policy:
## - Battle: cast chain lightning whenever it is off cooldown and >= 3
##   enemies are within CHAIN_RANGE of the strategist. Move the strategist
##   toward the nearest enemy when nothing is in skill range; retreat west
##   when his HP drops below 60.
## - Intermission: build in priority order pad2 thunder, pad3 flame,
##   pad0 flame, pad1 thunder, keeping an 80g repair reserve while the
##   core is below 60%; then repair while core < 300 HP and gold allows
##   (max 2 repairs); then press "next wave".
##
## Run: godot --headless --path . --script res://Test/sim_driver.gd
## Exit 0 = scripted victory, 1 = defeat, 2 = timeout.

const TIME_SCALE := 8.0
const REAL_TIMEOUT_MS := 420000
# Build priority: [pad_index, tower_type]
const BUILD_ORDER: Array = [[2, "thunder"], [3, "flame"], [0, "flame"], [1, "thunder"]]

var game: Node = null
var start_ticks: int = 0
var wave_start_elapsed: float = 0.0
var gold_at_wave_start: int = 0
var spent_this_intermission: int = 0
var last_move_elapsed: float = -10.0
var finished: bool = false


func _initialize() -> void:
	_run()


func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _run() -> void:
	Engine.time_scale = TIME_SCALE
	start_ticks = Time.get_ticks_msec()
	await process_frame
	var packed: PackedScene = load("res://scenes/main.tscn")
	if packed == null:
		print("SIM ERROR: main scene failed to load")
		quit(2)
		return
	game = packed.instantiate()
	root.add_child(game)
	await process_frame
	await process_frame
	# Stage-1: the run starts at hero select; the sim plays 马谡 (the
	# chain-lightning hero its tactics were written for).
	if String(game.get("game_state")) == "select":
		game.call("select_hero", 10)
		await process_frame
	print("SIM start: state=", String(game.get("game_state")), " wave=", int(game.get("current_wave")))
	wave_start_elapsed = float(game.get("elapsed"))
	gold_at_wave_start = int(game.get("gold"))
	var prev_state: String = String(game.get("game_state"))

	while not finished:
		if Time.get_ticks_msec() - start_ticks > REAL_TIMEOUT_MS:
			print("SIM RESULT: timeout state=", String(game.get("game_state")), " wave=", int(game.get("current_wave")), " core_hp=", snappedf(float(game.get("core_hp")), 0.1))
			quit(2)
			return
		await create_timer(0.1).timeout
		if not is_instance_valid(game):
			quit(2)
			return
		var state: String = String(game.get("game_state"))
		if state == "battle":
			_battle_policy()
		elif state == "intermission" and prev_state == "battle":
			_on_wave_cleared()
			if not finished:
				_intermission_policy()
				# Start the next wave through the real button path.
				game.call("_on_next_wave_pressed")
				wave_start_elapsed = float(game.get("elapsed"))
				gold_at_wave_start = int(game.get("gold"))
		elif state == "victory" and prev_state == "battle":
			_on_final_wave_cleared()
		elif state == "defeat":
			_on_defeat()
		prev_state = state


func _battle_policy() -> void:
	var strat: Node3D = game.get("strategist")
	if strat == null or not is_instance_valid(strat) or not bool(strat.get("alive")):
		return
	var enemies: Array = game.call("alive_enemies")
	# Chain lightning: off cooldown and >= 3 enemies within skill range.
	if float(game.get("skill_cooldown")) <= 0.0:
		var in_range := 0
		for e in enemies:
			if _flat(e.global_position, strat.global_position) <= 25.0:
				in_range += 1
		if in_range >= 3:
			game.call("_cast_chain_lightning")
			return
	# Positioning: retreat when hurt, otherwise close with the nearest enemy
	# when nothing is inside skill range.
	var elapsed_now := float(game.get("elapsed"))
	if elapsed_now - last_move_elapsed < 2.0:
		return
	if float(strat.get("hp")) < 60.0:
		strat.call("move_to", Vector3(-14, 0, 4.5))
		last_move_elapsed = elapsed_now
		return
	var nearest: Node3D = null
	var best := 1.0e9
	for e in enemies:
		var d := _flat(e.global_position, strat.global_position)
		if d < best:
			best = d
			nearest = e
	if nearest != null and best > 20.0:
		var target := nearest.global_position
		target.x = clampf(target.x - 10.0, -6.0, 10.0)
		target.z = clampf(target.z, -8.0, 8.0)
		strat.call("move_to", target)
		last_move_elapsed = elapsed_now


func _wave_record(earned: int) -> Dictionary:
	return {
		"wave": int(game.get("current_wave")),
		"dur": float(game.get("elapsed")) - wave_start_elapsed,
		"gold_earned": earned,
		"core_hp_end": float(game.get("core_hp")),
	}


func _on_wave_cleared() -> void:
	var earned := int(game.get("gold")) - gold_at_wave_start
	var rec := _wave_record(earned)
	print("SIM wave=%d dur=%.1fs gold_earned=%d core_hp_end=%.0f (%.0f%%)" % [
		rec["wave"], rec["dur"], rec["gold_earned"], rec["core_hp_end"],
		rec["core_hp_end"] / 520.0 * 100.0])


func _on_final_wave_cleared() -> void:
	var earned := int(game.get("gold")) - gold_at_wave_start
	var rec := _wave_record(earned)
	print("SIM wave=%d dur=%.1fs gold_earned=%d core_hp_end=%.0f (%.0f%%)" % [
		rec["wave"], rec["dur"], rec["gold_earned"], rec["core_hp_end"],
		rec["core_hp_end"] / 520.0 * 100.0])
	var pct := float(game.get("core_hp")) / 520.0 * 100.0
	var in_band := pct >= 10.0 and pct <= 60.0
	print("SIM RESULT: victory core_hp=%.0f pct=%.1f band_10_60=%s total_time=%.1fs" % [
		float(game.get("core_hp")), pct, str(in_band), float(game.get("elapsed"))])
	finished = true
	quit(0)


func _on_defeat() -> void:
	print("SIM RESULT: defeat wave=%d elapsed=%.1fs" % [int(game.get("current_wave")), float(game.get("elapsed"))])
	finished = true
	quit(1)


func _intermission_policy() -> void:
	spent_this_intermission = 0
	var core_hp := float(game.get("core_hp"))
	# Build in fixed priority order; hold an 80g reserve for repairs while
	# the core is below 60%.
	for step in BUILD_ORDER:
		var pad_index: int = step[0]
		var tower_type: String = step[1]
		var pads: Array = game.get("pads")
		if pads[pad_index].get("tower") != null:
			continue
		var cost := int(game.call("tower_cost", tower_type))
		var reserve := 80 if core_hp < 312.0 else 0
		if int(game.get("gold")) - cost >= reserve:
			if bool(game.call("build_tower", pad_index, tower_type)):
				spent_this_intermission += cost
	# Repairs: while the core is below 300 HP and gold allows (max 2).
	var repairs := 0
	while float(game.get("core_hp")) < 300.0 and int(game.get("gold")) >= 80 and repairs < 2:
		if bool(game.call("repair_core")):
			spent_this_intermission += 80
			repairs += 1
		else:
			break
	print("SIM intermission after wave %d: spent=%d gold_left=%d core_hp=%.0f" % [
		int(game.get("current_wave")), spent_this_intermission, int(game.get("gold")), float(game.get("core_hp"))])
