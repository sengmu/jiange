extends Node3D
## Shop purchase captures (2026-11-14 round, LOOP_STATE -0.4): instances
## the real game scene and photographs the market row + shop panel, then
## buys one item through the game's own functions and photographs the
## result (gold deducted, item in the 6-slot bag, damage raised).
##  1 shots/shop_market.png       — market row close-up: six shops,
##     shopkeepers, name signs, empty bag row.
##  2 shots/shop_panel_equip.png  — equipment shop panel open (tier-1
##     white gear, prices, gold + bag state).
##  3 shots/shop_bought.png       — after buying 铁剑: gold deducted,
##     铁剑 in the bag row, hero damage raised.
##  4 shots/shop_panel_book.png   — book shop panel open (5 books).
## Run: xvfb-run godot --path . res://scenes/probe_shop.tscn -- --quality=0

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
	print("PROBE_SHOP saved=", path)


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
	_set_cam(Vector3(-64, 0, -14), 42.0)
	await get_tree().create_timer(0.6).timeout
	await _grab("res://shots/shop_market.png")
	game.call("_open_shop_panel", 0)
	await get_tree().create_timer(0.6).timeout
	await _grab("res://shots/shop_panel_equip.png")
	var hero: Node = game.get("strategist")
	var dmg_before := float(hero.get("attack_damage"))
	game.call("_on_shop_buy", "sword_t1")
	await get_tree().create_timer(0.4).timeout
	print("PROBE_SHOP bought: gold=", int(game.get("gold")), " bag=", (game.get("hero_inventory") as Array).size(), " dmg_before=", dmg_before, " dmg_after=", float(hero.get("attack_damage")), " msg=", String((game.get("message_label") as Label).text))
	await _grab("res://shots/shop_bought.png")
	game.call("_close_shop_panel")
	game.call("_open_shop_panel", 3)
	await get_tree().create_timer(0.6).timeout
	await _grab("res://shots/shop_panel_book.png")
	get_tree().quit()
