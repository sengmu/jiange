extends Node3D
## Ground-continuity captures (2026-11-14, 台账 -0.6 地面连续化):
## mid-distance shots at a phone-like viewing distance over open grass
## and over the forest-zone south blend edge — the range where the old
## per-hex tint/height steps read as a checkerboard on the real device
## (user report 2026-11-14 01:11) while desktop full-map shots looked
## smooth. Output goes to .tmp/; the round copies before/after frames.
## Run: xvfb-run godot --path . res://scenes/probe_groundrev.tscn -- --quality=0

var game: Node


func _ready() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	_run()


func _grab(path: String) -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
	print("PROBE_GROUNDREV saved=", path)


func _set_cam(target: Vector3, dist: float) -> void:
	var dir: Vector3 = game.get("cam_dir")
	game.set("cam_target", target)
	game.set("cam_dist", dist)
	game.set("cam_dir", dir)
	game.call("_apply_camera")


func _run() -> void:
	await get_tree().create_timer(2.5).timeout
	game.call("select_hero", 0) # 赵统
	await get_tree().create_timer(1.0).timeout
	_set_cam(Vector3(24, 0, 30), 58.0)
	await get_tree().create_timer(0.6).timeout
	await _grab("res://.tmp/groundrev_mid_south.png")
	_set_cam(Vector3(59, 0, -29), 55.0)
	await get_tree().create_timer(0.6).timeout
	await _grab("res://.tmp/groundrev_mid_forest.png")
	# Open south-west field: the frame the P1 fix is judged on — broad
	# worn-earth patches and the density wave must be perceptible here
	# at the same distance, with no road or apron covering the grass.
	_set_cam(Vector3(18, 0, 32), 52.0)
	await get_tree().create_timer(0.6).timeout
	await _grab("res://.tmp/groundrev_mid_patch.png")
	get_tree().quit()
