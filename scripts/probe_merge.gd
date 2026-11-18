extends Node3D
## Merge telemetry probe (0.1.59): visible MeshInstance3D / Label3D per
## top-level root in (a) hero-select state, (b) drain stress state
## (wave 20 queue fully spawned + all pads built), (c) played peak:
## max sampled total during a live wave-20 defense.
## Run: xvfb-run godot --path . res://scenes/probe_merge.tscn -- --quality=0

var game: Node

func _count_bucket(root: Node) -> Dictionary:
	var res := {"mi_vis": 0, "mi_all": 0, "label_vis": 0, "label_all": 0}
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D:
			res["mi_all"] = int(res["mi_all"]) + 1
			if (n as MeshInstance3D).is_visible_in_tree():
				res["mi_vis"] = int(res["mi_vis"]) + 1
		elif n is Label3D:
			res["label_all"] = int(res["label_all"]) + 1
			if (n as Label3D).is_visible_in_tree():
				res["label_vis"] = int(res["label_vis"]) + 1
		for c in n.get_children():
			stack.push_back(c)
	return res

func _total() -> Array:
	var mi := 0
	var lb := 0
	for child in game.get_children():
		var b := _count_bucket(child)
		mi += int(b["mi_vis"])
		lb += int(b["label_vis"])
	return [mi, lb]

func _measure(tag: String) -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	for child in game.get_children():
		var b := _count_bucket(child)
		if int(b["mi_all"]) > 0 or int(b["label_all"]) > 0:
			print("MERGE_TEL bucket=", child.name, " mi_vis=", b["mi_vis"], " mi_all=", b["mi_all"], " label_vis=", b["label_vis"], " label_all=", b["label_all"])
	var t := _total()
	print("MERGE_TEL ", tag, " total_mi_vis=", t[0], " total_label_vis=", t[1], " combined=", int(t[0]) + int(t[1]))
	print("MERGE_TEL ", tag, " draws=", RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME), " prims=", RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME), " objects=", RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME))

func _ready() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	_run()

func _run() -> void:
	await get_tree().create_timer(2.0).timeout
	await _measure("SELECT")
	# --- drain stress state ---
	game.call("select_hero", 0)
	game.set("gold", 99999)
	game.call("_start_wave", 20)
	var guard := 0
	while not (game.get("spawn_queue") as Array).is_empty() and guard < 300:
		game.call("_spawn_from_queue")
		guard += 1
	var types: Array = ["arrow", "frost", "thunder", "stone", "flame", "crossbow"]
	for p in range(10):
		game.call("build_tower", p, types[p % types.size()])
	await get_tree().create_timer(1.0).timeout
	await _measure("DRAIN")
	# --- played peak: fresh run, towers pre-built, wave plays live ---
	game.call("reset_game")
	await get_tree().create_timer(0.5).timeout
	game.call("select_hero", 0)
	game.set("gold", 99999)
	for p in range(10):
		game.call("build_tower", p, types[p % types.size()])
	game.call("_start_wave", 20)
	var max_mi := 0
	var max_lb := 0
	var samples := 0
	var t := 0.0
	while t < 90.0:
		await get_tree().create_timer(1.0).timeout
		t += 1.0
		samples += 1
		var cur := _total()
		if int(cur[0]) > max_mi:
			max_mi = int(cur[0])
		if int(cur[1]) > max_lb:
			max_lb = int(cur[1])
		if String(game.get("game_state")) != "battle":
			break
	print("MERGE_TEL PLAYED_PEAK max_mi_vis=", max_mi, " max_label_vis=", max_lb, " combined=", max_mi + max_lb, " samples=", samples, " state=", String(game.get("game_state")), " wave=", int(game.get("current_wave")))
	await _measure("PLAYED_END")
	get_tree().quit()
