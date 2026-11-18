extends Node3D
## Solo unit close-up: one pinned enemy in front of the camera.
## --tag=on|off decides the output name only (code state decides merge).
var game: Node
var tag: String = "on"

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--tag="):
			tag = a.trim_prefix("--tag=")
	game = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	_run()

func _run() -> void:
	await get_tree().create_timer(2.0).timeout
	game.call("select_hero", 0)
	game.call("_start_wave", 1)
	var guard := 0
	while not (game.get("spawn_queue") as Array).is_empty() and guard < 40:
		game.call("_spawn_from_queue")
		guard += 1
	var units_root: Node = game.get("units_root")
	var foe: Node3D = null
	for u in units_root.get_children():
		if String(u.get("archetype")) == "enemy":
			foe = u
			break
	if foe == null:
		print("PROBE_SOLO no enemy")
		get_tree().quit()
		return
	foe.set("max_hp", 100000.0)
	foe.set("hp", 100000.0)
	await get_tree().create_timer(0.3).timeout
	var spot := Vector3(-40, 0, 20)
	foe.set("global_position", spot)
	foe.set("speed", 0.0)
	game.set("cam_target", spot)
	game.set("cam_dist", 9.0)
	game.call("_apply_camera")
	await get_tree().create_timer(0.4).timeout
	for ry in [0.0, PI]:
		foe.set("global_position", spot)
		foe.set("rotation", Vector3(0, ry, 0))
		await get_tree().create_timer(0.25).timeout
		foe.set("global_position", spot)
		foe.set("rotation", Vector3(0, ry, 0))
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.save_png("res://shots/solo_enemy_%s_r%s.png" % [tag, "0" if ry == 0.0 else "180"])
	print("PROBE_SOLO saved tag=", tag)
	get_tree().quit()
