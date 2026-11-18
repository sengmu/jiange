extends Node3D
## Hero-select probe (stage 1 选将系统): photographs the real select
## panel (22 heroes, locked ones marked) and one full-kit hero in battle.
## Run: xvfb-run godot --path . --resolution 1280x720 res://scenes/probe_hero.tscn

var game: Node


func _ready() -> void:
	_beat("ready_start")
	game = load("res://scenes/main.tscn").instantiate()
	_beat("game_loaded")
	add_child(game)
	_beat("game_added")
	_run()


func _beat(tag: String) -> void:
	var f := FileAccess.open("res://.tmp/probe_hero_hb.txt", FileAccess.WRITE_READ)
	if f == null:
		return
	f.seek_end()
	f.store_line("%d frames=%d %s" % [Time.get_ticks_msec(), Engine.get_frames_drawn(), tag])
	f.close()


func _grab(path: String) -> void:
	_beat("grab_start " + path)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	_beat("grab_frames_done " + path)
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
	print("PROBE_HERO saved=", path)


func _run() -> void:
	_beat("run_start")
	await get_tree().create_timer(1.5).timeout
	_beat("after_1p5s_timer")
	var results := {}
	var buttons: Array = game.get("hero_buttons")
	results["buttons_22"] = buttons.size() == 22
	var locked_labels: Array = []
	for i in [9, 11, 14]:
		locked_labels.append((buttons[i] as Button).text)
	results["locked_marked"] = "锁" in String(locked_labels[0]) and "锁" in String(locked_labels[1]) and "锁" in String(locked_labels[2])
	results["detail_full_label"] = "完整技能" in String(game.call("_hero_detail_text", 3))
	results["detail_generic_label"] = "通用技能件" in String(game.call("_hero_detail_text", 5))
	print("PROBE_HERO locked_labels=", locked_labels)
	print("PROBE_HERO detail_jiangwei=", String(game.call("_hero_detail_text", 3)))
	print("PROBE_HERO detail_guansuo=", String(game.call("_hero_detail_text", 5)))
	await _grab("res://shots/hero_select_panel.png")
	# Unlock a hidden hero, then start a battle as 姜维 (full kit: 烈火燎原).
	game.call("try_unlock_hero", "luboyan")
	results["unlock_luboyan"] = not bool(game.call("hero_is_locked", 9))
	game.call("select_hero", 3)
	await get_tree().create_timer(1.0).timeout
	game.call("reset_camera_view")
	await get_tree().create_timer(0.5).timeout
	results["battle_started"] = String(game.get("game_state")) == "battle"
	var strat: Node = game.get("strategist")
	results["strategist_is_jiangwei"] = strat != null and String(strat.get("display_name")) == "姜维"
	results["skill_button_is_fire_line"] = String((game.get("skill_button") as Button).text) == "烈火燎原"
	await _grab("res://shots/hero_battle_jiangwei.png")
	print("PROBE_HERO SUMMARY ", results)
	_beat("summary_printed")
	_beat("done")
	get_tree().quit()
