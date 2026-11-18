extends Node3D
## Wave/boss-chain probe (stage 1): stages wave 6 (three Zhang brothers)
## and wave 20 (Three Simas) through the real spawn queue, photographs
## both boss groups in the field, and checks the wave preview names.
## Run: xvfb-run godot --path . --resolution 1280x720 res://scenes/probe_wave.tscn

var game: Node


func _ready() -> void:
	_beat("ready_start")
	game = load("res://scenes/main.tscn").instantiate()
	_beat("game_loaded")
	add_child(game)
	_beat("game_added")
	_run()


func _beat(tag: String) -> void:
	var f := FileAccess.open("res://.tmp/probe_wave_hb.txt", FileAccess.WRITE_READ)
	if f == null:
		return
	f.seek_end()
	f.store_line("%d frames=%d %s" % [Time.get_ticks_msec(), Engine.get_frames_drawn(), tag])
	f.close()


func _grab(path: String) -> void:
	_beat("grab_start " + path)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	_beat("grab_frames_done " + path)
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
	print("PROBE_WAVE saved=", path)


func _drain_queue() -> void:
	var guard := 0
	while not (game.get("spawn_queue") as Array).is_empty() and guard < 120:
		game.call("_spawn_from_queue")
		guard += 1


func _boss_names_alive() -> Array:
	var names: Array = []
	for e in game.get("enemies"):
		if is_instance_valid(e) and bool(e.get("alive")) and String(e.get("archetype")) == "boss":
			names.append(String(e.get("display_name")))
	return names


func _stage_bosses_for_photo(spots: Array) -> void:
	# Probe staging only: bosses spawn at the east rifts (off-frame at the
	# default camera), so park them by the plaza for the photograph. The
	# alive/order checks above already ran on the real spawn positions.
	var i := 0
	for e in game.get("enemies"):
		if is_instance_valid(e) and bool(e.get("alive")) and String(e.get("archetype")) == "boss" and i < spots.size():
			e.set("global_position", spots[i])
			i += 1


func _run() -> void:
	_beat("run_start")
	await get_tree().create_timer(1.5).timeout
	_beat("after_1p5s_timer")
	var results := {}
	game.call("select_hero", 0)
	await get_tree().create_timer(0.5).timeout
	results["battle_started"] = String(game.get("game_state")) == "battle"
	# Wave 6: three Zhang brothers through the real queue.
	game.call("_start_wave", 6)
	await get_tree().create_timer(0.5).timeout
	_drain_queue()
	await get_tree().create_timer(0.5).timeout
	var names6: Array = _boss_names_alive()
	results["wave6_bosses_alive"] = names6
	results["wave6_three_brothers"] = names6.has("张角") and names6.has("张梁") and names6.has("张宝")
	var spawned6: Array = game.get("bosses_spawned_names")
	results["wave6_spawn_order"] = spawned6.slice(spawned6.size() - 3, spawned6.size()) == ["张角", "张梁", "张宝"]
	print("PROBE_WAVE wave6 bosses=", names6, " spawned=", spawned6)
	_stage_bosses_for_photo([Vector3(10, 0, -4), Vector3(16, 0, 0), Vector3(22, 0, 4)])
	game.call("reset_camera_view")
	await get_tree().create_timer(0.5).timeout
	await _grab("res://shots/wave6_brothers.png")
	# Wave preview text names the next wave's bosses (intermission label).
	var prev20: String = game.call("wave_preview_text", 20)
	results["preview20_names_simas"] = "司马昭" in prev20 and "司马师" in prev20 and "司马懿" in prev20
	print("PROBE_WAVE preview20=", prev20)
	# Clear wave 6 through the real damage pipeline, then stage wave 20.
	for e in game.get("enemies"):
		if is_instance_valid(e) and bool(e.get("alive")):
			game.call("apply_damage", null, e, 9999.0, "probe_wave")
	await get_tree().create_timer(1.0).timeout
	results["wave6_cleared_to_intermission"] = String(game.get("game_state")) == "intermission"
	game.call("_start_wave", 20)
	await get_tree().create_timer(0.5).timeout
	_drain_queue()
	await get_tree().create_timer(0.5).timeout
	var names20: Array = _boss_names_alive()
	results["wave20_bosses_alive"] = names20
	results["wave20_three_simas"] = names20.has("司马昭") and names20.has("司马师") and names20.has("司马懿")
	var spawned20: Array = game.get("bosses_spawned_names")
	results["wave20_spawn_order"] = spawned20.slice(spawned20.size() - 3, spawned20.size()) == ["司马昭", "司马师", "司马懿"]
	print("PROBE_WAVE wave20 bosses=", names20, " spawned=", spawned20)
	_stage_bosses_for_photo([Vector3(10, 0, -4), Vector3(16, 0, 0), Vector3(22, 0, 4)])
	game.call("reset_camera_view")
	await get_tree().create_timer(0.5).timeout
	await _grab("res://shots/wave20_simas.png")
	print("PROBE_WAVE SUMMARY ", results)
	_beat("summary_printed")
	_beat("done")
	get_tree().quit()
