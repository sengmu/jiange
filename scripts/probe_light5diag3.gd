extends Node3D
## Rev 5 (light) diag #3: GateRoofFill tuning variants on the e view only.
## Runtime-only overrides on top of production values.

var game: Node


func _grab(path: String) -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
	print("PROBE_L5D3 saved=", path)


func _shot(name: String) -> void:
	await get_tree().create_timer(0.45).timeout
	await _grab("res://shots/l5d3_%s.png" % name)


func _run() -> void:
	await get_tree().create_timer(2.5).timeout
	game.call("select_hero", 0)
	await get_tree().create_timer(1.0).timeout
	var dir: Vector3 = game.get("cam_dir")
	game.set("cam_target", Vector3(-59, 0, -13))
	game.set("cam_dist", 14.0)
	game.set("cam_dir", dir)
	game.call("_apply_camera")
	await get_tree().create_timer(0.6).timeout
	await _shot("e_base")
	var rf = game.get("gate_roof_fill_light")
	rf.light_energy = 3.8
	await _shot("e_v1_hot")
	rf.position = Vector3(-80, 14, -4)
	rf.look_at(Vector3(-56, 4.5, -4), Vector3.UP)
	rf.spot_angle = 20.0
	rf.light_energy = 3.4
	await _shot("e_v2_west")
	rf.light_energy = 4.5
	await _shot("e_v3_westhot")
	get_tree().quit()


func _ready() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	_run()
