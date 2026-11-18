extends Node3D
## Training-room captures (2026-11-14, stage-2 训练房成长）:
## photographs a paid brush session mid-fight, the training boss in
## its pen, and the trainer panel after a forced growth-item drop
## (growth progress lines). All through the game's own entry points.
##  1 shots/train_a_brush.png — brush room, soldiers around the hero.
##  2 shots/train_b_boss.png  — training boss in the north-west pen.
##  3 shots/train_c_panel.png — trainer panel with a growth item.
## Run: xvfb-run godot --path . res://scenes/probe_train.tscn -- --quality=0

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
	print("PROBE_TRAIN saved=", path)


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
	game.set("gold", 5000)
	var ok1: bool = game.call("trainer_enter", "brush")
	_set_cam(Vector3(-50, 0, 30), 34.0)
	await get_tree().create_timer(4.0).timeout
	print("PROBE_TRAIN brush=", ok1, " level=", int(game.get("train_level")), " gold=", int(game.get("gold")), " trainees=", int(game.call("_alive_trainee_count")))
	await _grab("res://shots/train_a_brush.png")
	var ok2: bool = game.call("trainer_enter", "boss")
	_set_cam(Vector3(-47, 0, -31), 34.0)
	await get_tree().create_timer(2.0).timeout
	print("PROBE_TRAIN boss=", ok2, " gold=", int(game.get("gold")), " boss_alive=", game.get("train_boss") != null)
	await _grab("res://shots/train_b_boss.png")
	# Slay the boss through the real damage path, then make sure a
	# growth item is in the bag for the panel shot (the death roll is
	# random; top up via the same drop function if it missed).
	var strat: Node = game.get("strategist")
	var boss: Node = game.get("train_boss")
	if boss != null:
		game.call("apply_damage", strat, boss, 999999.0)
		await get_tree().create_timer(0.5).timeout
	var has_growth := false
	for it in game.get("hero_inventory"):
		if (it as Dictionary).has("growth"):
			has_growth = true
	if not has_growth:
		game.set("boss_session", true)
		game.call("training_boss_drop", 0.5)
	print("PROBE_TRAIN bag=", (game.get("hero_inventory") as Array).size(), " gold=", int(game.get("gold")))
	game.call("_open_shop_panel", 6) # 训练长官
	await get_tree().create_timer(0.6).timeout
	await _grab("res://shots/train_c_panel.png")
	get_tree().quit()
