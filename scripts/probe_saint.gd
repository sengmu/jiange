extends Node3D
## Saint captures (2026-11-14, stage-2 圣痕/四圣兽）: a wild saint on
## its dais, and a summoned saint standing by the hero after its mark
## is used from the bag. Through the game's own entry points only.
##  1 shots/saint_a_wild.png — wild 青龙 on the forest dais.
##  2 shots/saint_b_summon.png — 朱雀 summoned beside the hero.
## Run: xvfb-run godot --path . res://scenes/probe_saint.tscn -- --quality=0

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
	print("PROBE_SAINT saved=", path)


func _set_cam(target: Vector3, dist: float) -> void:
	var dir: Vector3 = game.get("cam_dir")
	game.set("cam_target", target)
	game.set("cam_dist", dist)
	game.set("cam_dir", dir)
	game.call("_apply_camera")


func _run() -> void:
	await get_tree().create_timer(2.5).timeout
	game.call("select_hero", 0)
	await get_tree().create_timer(1.0).timeout
	_set_cam(Vector3(77, 0, -37), 30.0)
	await get_tree().create_timer(1.2).timeout
	await _grab("res://shots/saint_a_wild.png")
	game.call("give_hero_item", game.call("saint_mark_item", "朱雀"))
	await get_tree().create_timer(0.3).timeout
	var inv: Array = game.get("hero_inventory")
	for i in range(inv.size()):
		if String((inv[i] as Dictionary).get("name", "")) == "圣痕·朱雀":
			game.call("_use_inventory_item", i)
	await get_tree().create_timer(1.5).timeout
	var hero: Node = game.get("strategist")
	_set_cam(hero.global_position, 26.0)
	await get_tree().create_timer(0.8).timeout
	print("PROBE_SAINT saints=", (game.get("saints_active") as Array).size(), " pop=", int(game.call("pop_used")), "/", int(game.call("pop_cap")))
	await _grab("res://shots/saint_b_summon.png")
	get_tree().quit()
