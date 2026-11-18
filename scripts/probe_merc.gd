extends Node3D
## Mercenary captures (2026-11-14, stage-2 雇佣兵）: the quartermaster
## panel with the full roster, and a bought squad standing at the base
## staging ground (farmer by the seal core). Through the game's own
## entry points only (buy_mercenary, panel via shop_defs index).
##  1 shots/merc_a_panel.png — panel: pop line, upkeep note, 7 rows.
##  2 shots/merc_b_squad.png — farmer + xiliang + bubing + piliche.
## Run: xvfb-run godot --path . res://scenes/probe_merc.tscn -- --quality=0

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
	print("PROBE_MERC saved=", path)


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
	game.set("gold", 5000)
	game.set("current_wave", 10)
	var merc_idx := -1
	var defs: Array = game.get("shop_defs")
	for i in range(defs.size()):
		if String((defs[i] as Dictionary).get("kind", "")) == "mercenary":
			merc_idx = i
	game.call("_open_shop_panel", merc_idx)
	await get_tree().create_timer(0.6).timeout
	await _grab("res://shots/merc_a_panel.png")
	game.call("buy_mercenary", 0) # farmer
	game.call("buy_mercenary", 1) # xiliang
	game.call("buy_mercenary", 2) # bubing
	game.call("buy_mercenary", 5) # piliche
	game.call("_close_shop_panel")
	_set_cam(Vector3(-62, 0, -12), 38.0)
	await get_tree().create_timer(2.5).timeout
	print("PROBE_MERC mercs=", (game.get("mercs") as Array).size(), " pop=", int(game.call("pop_used")), "/", int(game.call("pop_cap")))
	await _grab("res://shots/merc_b_squad.png")
	get_tree().quit()
