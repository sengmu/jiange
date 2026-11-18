extends Node3D
## Casino captures (2026-11-14, stage-2 赌场）: the casino panel (free
## chips, odds, gamble button) after a premium pull, and a startled
## saint beast standing in the forest. Through the game's own entry
## points only (casino index found from shop_defs).
##  1 shots/casino_a_panel.png — panel with chips 9 + last=premium.
##  2 shots/casino_b_beast.png — saint beast in the forest clearing.
## Run: xvfb-run godot --path . res://scenes/probe_casino.tscn -- --quality=0

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
	print("PROBE_CASINO saved=", path)


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
	# One premium pull first so the panel shows a last-result line.
	game.call("casino_gamble", 0.15)
	var casino_idx := -1
	var defs: Array = game.get("shop_defs")
	for i in range(defs.size()):
		if String((defs[i] as Dictionary).get("kind", "")) == "casino":
			casino_idx = i
	game.call("_open_shop_panel", casino_idx)
	await get_tree().create_timer(0.6).timeout
	await _grab("res://shots/casino_a_panel.png")
	game.call("_close_shop_panel")
	# Startle a saint beast and frame it in the forest.
	game.call("casino_gamble", 0.01)
	_set_cam(Vector3(60, 0, -36), 40.0)
	await get_tree().create_timer(1.2).timeout
	print("PROBE_CASINO beast=", String(game.get("casino_beast_name")), " wilds=", (game.get("wilds") as Array).size(), " chips=", int(game.get("casino_chips")))
	await _grab("res://shots/casino_b_beast.png")
	get_tree().quit()
