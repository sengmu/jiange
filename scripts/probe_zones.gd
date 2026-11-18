extends Node3D
## Map-completion zone captures (2026-11-14 round): instances the real
## game scene and photographs the two new wild zones.
##  1 shots/zones_overview.png — whole map pulled back to 150: both
##     new zones readable at the north edge (forest NE, graveyard NW).
##  2 shots/zones_forest.png   — forest close-up: 青龙之位 dais and
##     crystal, 烧皮点 scorch disc, 毒蜘蛛巢 mound, dense canopy.
##  3 shots/zones_grave.png    — graveyard close-up: 项羽之魂 stele,
##     grave mounds, 白虎之位 dais, stone fence and dead trees.
##  4 shots/zones_water.png    — water close-up: pond, 玄武之位 dais
##     and dark-blue crystal, reeds and shore rocks.
##  5 shots/zones_newcity.png  — new-city close-up: town gate, three
##     houses, well and 孟达 by the gate.
##  6 shots/zones_valley.png   — valley close-up: 葫芦谷 mouth sign,
##     gorge walls, scorch discs, firewood piles, 上方谷 sign.
##  7 shots/zones_refiner.png  — refiner close-up: forge furnace,
##     anvil, roofed stall, 炼化师 NPC and point sign.
##  8 shots/zones_hunter.png   — hunter close-up: hut, drying rack
##     with hides, hide pile, 猎人 NPC and point sign.
##  9 shots/zones_wall.png     — base-gate wall close-up: gatehouse
##     roof, two gate towers, wall segments, two watchtowers, sign.
## Run: xvfb-run godot --path . res://scenes/probe_zones.tscn -- --quality=0

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
	print("PROBE_ZONES saved=", path)


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
	_set_cam(Vector3(0, 0, 0), 150.0)
	await get_tree().create_timer(0.6).timeout
	await _grab("res://shots/zones_overview.png")
	_set_cam(Vector3(63, 0, -37), 42.0)
	await get_tree().create_timer(0.6).timeout
	await _grab("res://shots/zones_forest.png")
	_set_cam(Vector3(-19, 0, -36.5), 42.0)
	await get_tree().create_timer(0.6).timeout
	await _grab("res://shots/zones_grave.png")
	_set_cam(Vector3(63, 0, 36.5), 42.0)
	await get_tree().create_timer(0.6).timeout
	await _grab("res://shots/zones_water.png")
	_set_cam(Vector3(-75, 0, -34), 42.0)
	await get_tree().create_timer(0.6).timeout
	await _grab("res://shots/zones_newcity.png")
	_set_cam(Vector3(84, 0, -33), 60.0)
	await get_tree().create_timer(0.6).timeout
	await _grab("res://shots/zones_valley.png")
	_set_cam(Vector3(-70, 0, 31.5), 42.0)
	await get_tree().create_timer(0.6).timeout
	await _grab("res://shots/zones_refiner.png")
	_set_cam(Vector3(45, 0, -29.5), 42.0)
	await get_tree().create_timer(0.6).timeout
	await _grab("res://shots/zones_hunter.png")
	_set_cam(Vector3(-56, 0, 0), 46.0)
	await get_tree().create_timer(0.6).timeout
	await _grab("res://shots/zones_wall.png")
	get_tree().quit()
