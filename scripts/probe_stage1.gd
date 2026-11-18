extends Node3D
## Stage-1 captures: instances the real game scene and photographs the
## new full-map build at four framings.
##  1 shots/stage1_select.png   — hero select panel at boot.
##  2 shots/stage1_base.png     — default classic framing after selecting
##     a hero: main base, gate wall, market row edge, seal core.
##  3 shots/stage1_overview.png — camera pulled back over the whole map:
##     both lanes, both rifts, plaza, base, training pens.
##  4 shots/stage1_training.png — training pen with the hero inside and
##     trainees spawning.
## Run: xvfb-run godot --path . res://scenes/probe_stage1.tscn

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
	print("PROBE_STAGE1 saved=", path)


func _set_cam(target: Vector3, dist: float) -> void:
	var dir: Vector3 = game.get("cam_dir")
	game.set("cam_target", target)
	game.set("cam_dist", dist)
	game.set("cam_dir", dir)
	game.call("_apply_camera")


func _run() -> void:
	await get_tree().create_timer(2.5).timeout
	await _grab("res://shots/stage1_select.png")
	game.call("select_hero", 0) # 赵统
	await get_tree().create_timer(1.2).timeout
	game.call("reset_camera_view")
	await _grab("res://shots/stage1_base.png")
	_set_cam(Vector3(0, 0, 0), 150.0)
	await get_tree().create_timer(0.6).timeout
	await _grab("res://shots/stage1_overview.png")
	# Training pen: stage the hero inside and wait for a trainee.
	var strat: Node = game.get("strategist")
	if strat != null:
		strat.set("global_position", Vector3(-52, 0, 33))
	var waited := 0.0
	while waited < 10.0 and (game.get("trainees") as Array).is_empty():
		await get_tree().create_timer(0.25).timeout
		waited += 0.25
	print("PROBE_STAGE1 trainees=", (game.get("trainees") as Array).size(), " waited=", waited)
	_set_cam(Vector3(-50, 0, 30), 42.0)
	await get_tree().create_timer(0.6).timeout
	await _grab("res://shots/stage1_training.png")
	get_tree().quit()
