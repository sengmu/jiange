extends Node3D
## UI-A probe (2026-11-15, UI redesign phase 1): touch-UI captures of the
## bronze-ink-gold theme — battle HUD, hero select panel, shop panel.
##  1 shots/uiA_select.png — select panel (touch layout, before start)
##  2 shots/uiA_hud.png    — battle HUD after selecting 赵统, wave 3 field
##  3 shots/uiA_shop.png   — equipment shop panel open over the market
## Run: xvfb-run godot --path . --resolution 1920x864 res://scenes/probe_ui_a.tscn -- --touch-ui --quality=0

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
	print("PROBE_UI_A saved=", path)


func _set_cam(target: Vector3, dist: float) -> void:
	var dir: Vector3 = game.get("cam_dir")
	game.set("cam_target", target)
	game.set("cam_dist", dist)
	game.set("cam_dir", dir)
	game.call("_apply_camera")


func _run() -> void:
	await get_tree().create_timer(2.5).timeout
	# 1) Select panel in touch layout.
	await _grab("res://shots/uiA_select.png")
	# Choose a hero through the real button path so the emblem + detail
	# row show a chosen state in the HUD shot.
	game.call("_on_hero_button", 0)
	await get_tree().create_timer(0.3).timeout
	game.call("select_hero", 0) # 赵统
	await get_tree().create_timer(1.0).timeout
	game.set("gold", 5000)
	game.call("_start_wave", 3)
	await get_tree().create_timer(0.6).timeout
	var guard := 0
	while not (game.get("spawn_queue") as Array).is_empty() and guard < 160:
		game.call("_spawn_from_queue")
		guard += 1
	await get_tree().create_timer(1.2).timeout
	game.call("reset_camera_view")
	await get_tree().create_timer(0.5).timeout
	# 2) Battle HUD (touch: minimap, big skill button, emblem).
	await _grab("res://shots/uiA_hud.png")
	# 3) Shop panel over the market row.
	_set_cam(Vector3(-64, 0, -14), 42.0)
	await get_tree().create_timer(0.6).timeout
	game.call("_open_shop_panel", 0)
	await get_tree().create_timer(0.6).timeout
	await _grab("res://shots/uiA_shop.png")
	print("PROBE_UI_A done emblem=", String((game.get("hero_emblem_label") as Label).text) if game.get("hero_emblem_label") != null else "none")
	get_tree().quit()
