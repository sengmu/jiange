extends Node3D
## Refine captures (2026-11-14, stage-2 炼化合成）: photographs the
## refiner stall, the refine panel (materials / sets / exclusives),
## then forges a set piece through the game's own functions and
## photographs the result (materials consumed, piece in the bag).
##  1 shots/refine_stall.png  — the smith's stall in the south-west.
##  2 shots/refine_panel.png  — refine panel open (top of the list).
##  3 shots/refine_forged.png — after buying 龙鳞x2+玄铁x1 and forging
##     青龙偃月刀·套: gold + bag state in the panel header.
## Run: xvfb-run godot --path . res://scenes/probe_refine.tscn -- --quality=0

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
	print("PROBE_REFINE saved=", path)


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
	_set_cam(Vector3(-68, 0, 30), 30.0)
	await get_tree().create_timer(0.6).timeout
	await _grab("res://shots/refine_stall.png")
	game.call("_open_shop_panel", 7) # 炼化师
	await get_tree().create_timer(0.6).timeout
	await _grab("res://shots/refine_panel.png")
	game.call("_on_shop_buy", "mat_longlin")
	game.call("_on_shop_buy", "mat_longlin")
	game.call("_on_shop_buy", "mat_xuantie")
	var ok: bool = game.call("refine_craft_set", "青龙套", "青龙偃月刀·套")
	await get_tree().create_timer(0.4).timeout
	print("PROBE_REFINE forged=", ok, " gold=", int(game.get("gold")), " bag=", (game.get("hero_inventory") as Array).size(), " crafted=", int(game.get("crafted_count")), " msg=", String((game.get("message_label") as Label).text))
	game.call("_open_shop_panel", 7)
	await get_tree().create_timer(0.6).timeout
	await _grab("res://shots/refine_forged.png")
	get_tree().quit()
