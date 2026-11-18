extends Node3D
## Broken-piece sweep (2026-11-14 round, visual item 破损件清零):
## instances the real game scene and photographs close-ups of every
## zone/edge where placeholder pieces were reported (white trees/stones,
## uncolored mountains, floating flags/ballistae), plus the two standard
## framings used for the before/after compare.
## Run: xvfb-run godot --path . res://scenes/probe_broken.tscn -- --quality=0

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
	print("PROBE_BROKEN saved=", path)

func _set_cam(target: Vector3, dist: float) -> void:
	var dir: Vector3 = game.get("cam_dir")
	game.set("cam_target", target)
	game.set("cam_dist", dist)
	game.set("cam_dir", dir)
	game.call("_apply_camera")

func _shot(target: Vector3, dist: float, path: String) -> void:
	_set_cam(target, dist)
	await get_tree().create_timer(0.6).timeout
	await _grab(path)

func _run() -> void:
	await get_tree().create_timer(2.5).timeout
	game.call("select_hero", 0) # 赵统
	await get_tree().create_timer(1.0).timeout
	game.call("reset_camera_view")
	await get_tree().create_timer(0.6).timeout
	await _grab("res://shots/broken_a.png")
	await _shot(Vector3(0, 0, 0), 150.0, "res://shots/broken_b.png")
	await _shot(Vector3(0, 0, -44), 42.0, "res://shots/broken_north.png")
	await _shot(Vector3(0, 0, 44), 42.0, "res://shots/broken_south.png")
	await _shot(Vector3(84, 0, -26), 42.0, "res://shots/broken_east.png")
	await _shot(Vector3(-72, 0, 0), 42.0, "res://shots/broken_west.png")
	await _shot(Vector3(-50, 0, -13), 26.0, "res://shots/broken_tower.png")
	await _shot(Vector3(-24, 0, 7), 26.0, "res://shots/broken_flag.png")
	await _shot(Vector3(58, 0, -34), 40.0, "res://shots/broken_forest.png")
	await _shot(Vector3(-58, 0, -30), 40.0, "res://shots/broken_grave.png")
	await _shot(Vector3(84, 0, -37), 36.0, "res://shots/broken_valley.png")
	await _shot(Vector3(-20, 0, 15), 45.0, "res://shots/broken_market.png")
	await _shot(Vector3(77, 0, -37), 26.0, "res://shots/broken_qinglong.png")
	get_tree().quit()
