extends Node3D
## Rev 4 square-boundary hunt round 2: prefix-enumerated hides
## (round 1's find_children pattern matched only one node per
## repeated name) plus same-run shadow-off shots.
## Run: xvfb-run godot --path . res://scenes/probe_light4hide2.tscn -- --quality=0

var game: Node


func _grab(path: String) -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
	print("PROBE_HIDE2 saved=", path)


func _set_cam(target: Vector3, dist: float) -> void:
	var dir: Vector3 = game.get("cam_dir")
	game.set("cam_target", target)
	game.set("cam_dist", dist)
	game.set("cam_dir", dir)
	game.call("_apply_camera")


func _ready() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	_run()


func _all_visuals() -> Array:
	var out: Array = []
	for n in game.find_children("*", "VisualInstance3D", true, false):
		out.append(n)
	return out


func _run() -> void:
	await get_tree().create_timer(2.5).timeout
	game.call("select_hero", 0)
	await get_tree().create_timer(1.0).timeout
	_set_cam(Vector3(-70, 0, 0), 19.0)
	await get_tree().create_timer(0.6).timeout
	await _grab("res://shots/light_hh2_none.png")
	var prefixes: Array = ["RoadRibbon", "RoadCenter", "CourtyardWall", "Cliff", "Rock", "SealCore"]
	for pre in prefixes:
		var nodes: Array = []
		for n in _all_visuals():
			if String(n.name).begins_with(pre):
				nodes.append(n)
				n.visible = false
		await get_tree().create_timer(0.35).timeout
		await _grab("res://shots/light_hh2_%s.png" % pre.to_lower())
		for n in nodes:
			n.visible = true
		print("HIDEHUNT2 ", pre, " count=", nodes.size())
	var sun = game.get("sun_light")
	sun.shadow_enabled = false
	await get_tree().create_timer(0.35).timeout
	await _grab("res://shots/light_hh2_sunoff.png")
	sun.shadow_enabled = true
	game.get("crystal_light").shadow_enabled = false
	await get_tree().create_timer(0.35).timeout
	await _grab("res://shots/light_hh2_coreoff.png")
	get_tree().quit()
