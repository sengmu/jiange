extends Node3D
## UI-B probe (2026-11-16, UI redesign phase 2 batch 2): icon-ified
## surfaces — battle HUD with a filled bag, build (tower) popup, quest
## panel, mercenary / trainer / casino / refine shop panels.
##  1 shots/uiB_hud.png     — HUD, bag holds weapon/potion/material
##  2 shots/uiB_build.png   — build-choice popup (6 tower rows)
##  3 shots/uiB_quest.png   — quest panel (frame texture + strip)
##  4 shots/uiB_merc.png    — mercenary panel rows
##  5 shots/uiB_trainer.png — trainer panel rows
##  6 shots/uiB_casino.png  — casino panel rows
##  7 shots/uiB_refine.png  — refine panel rows (scrolls)
## Run: xvfb-run godot --path . --resolution 1920x864 res://scenes/probe_ui_b.tscn -- --touch-ui --quality=0

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
	print("PROBE_UI_B saved=", path)


func _run() -> void:
	await get_tree().create_timer(2.5).timeout
	game.call("_on_hero_button", 0)
	await get_tree().create_timer(0.3).timeout
	game.call("select_hero", 0) # 赵统
	await get_tree().create_timer(1.0).timeout
	game.set("gold", 5000)
	# Fill three bag slots so the inventory icons show in the HUD shot.
	game.set("hero_inventory", [
		{"id": "sword_t1", "name": "铁剑", "kind": "weapon"},
		{"id": "potion_heal", "name": "金创药", "kind": "potion_heal"},
		{"id": "mat_longlin", "name": "龙鳞", "kind": "material"},
	])
	game.call("_refresh_inventory_row")
	game.call("_start_wave", 1)
	await get_tree().create_timer(1.2).timeout
	game.call("reset_camera_view")
	await get_tree().create_timer(0.5).timeout
	await _grab("res://shots/uiB_hud.png")
	# Build popup on the first pad.
	game.call("_open_build_popup", 0)
	await get_tree().create_timer(0.6).timeout
	await _grab("res://shots/uiB_build.png")
	game.call("_close_build_popup")
	# Quest panel.
	game.call("_open_quest_panel")
	await get_tree().create_timer(0.6).timeout
	await _grab("res://shots/uiB_quest.png")
	game.call("_close_quest_panel")
	# Shop-family panels: mercenary 5, trainer 6, casino 4, refine 7.
	game.call("_open_shop_panel", 5)
	await get_tree().create_timer(0.6).timeout
	await _grab("res://shots/uiB_merc.png")
	game.call("_open_shop_panel", 6)
	await get_tree().create_timer(0.6).timeout
	await _grab("res://shots/uiB_trainer.png")
	game.call("_open_shop_panel", 4)
	await get_tree().create_timer(0.6).timeout
	await _grab("res://shots/uiB_casino.png")
	game.call("_open_shop_panel", 7)
	await get_tree().create_timer(0.6).timeout
	await _grab("res://shots/uiB_refine.png")
	game.call("_close_shop_panel")
	# Cooldown state of the big skill button (greyed + seconds).
	game.set("skill_cooldown", 5.0)
	await get_tree().create_timer(0.4).timeout
	await _grab("res://shots/uiB_hud_cd.png")
	print("PROBE_UI_B done")
	get_tree().quit()
