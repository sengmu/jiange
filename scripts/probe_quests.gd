extends Node3D
## Quest captures (2026-11-14, stage-2 任务链）: the quest log panel,
## a forest wild fight (bandit chief + beasts), and an escort event
## mid-route (villagers + ambush bandits). Through the game's own
## entry points only.
##  1 shots/quest_a_panel.png  — quest log, all twelve rows.
##  2 shots/quest_b_forest.png — hero fighting forest wilds.
##  3 shots/quest_c_escort.png — villagers under ambush, mid-map.
## Run: xvfb-run godot --path . res://scenes/probe_quests.tscn -- --quality=0

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
	print("PROBE_QUESTS saved=", path)


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
	game.call("_open_quest_panel")
	await get_tree().create_timer(0.6).timeout
	await _grab("res://shots/quest_a_panel.png")
	game.call("_close_quest_panel")
	# Forest wilds: drop the hero by the bandit chief's tree line.
	var strat: Node = game.get("strategist")
	strat.set("global_position", Vector3(52, 0, -36))
	_set_cam(Vector3(56, 0, -36), 36.0)
	await get_tree().create_timer(3.0).timeout
	print("PROBE_QUESTS hero_hp=", int(strat.get("hp")), " wilds=", (game.get("wilds") as Array).size())
	await _grab("res://shots/quest_b_forest.png")
	# Escort event: stage the ambush meeting point mid-route so the
	# frame holds villagers and bandits together.
	game.call("spawn_escort_event")
	var vs: Array = game.get("villagers")
	for i in range(vs.size()):
		(vs[i] as Node).set("global_position", Vector3(46 + i * 2, 0, -6 + i * 4))
	_set_cam(Vector3(42, 0, 0), 42.0)
	await get_tree().create_timer(2.0).timeout
	print("PROBE_QUESTS villagers=", (game.get("villagers") as Array).size(), " saved=", int(game.get("saved_villagers")))
	await _grab("res://shots/quest_c_escort.png")
	get_tree().quit()
