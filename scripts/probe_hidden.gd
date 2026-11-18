extends Node3D
## Hidden-hero unlock probe (stage 1): drives the real select-panel UI path
## (pw_edit.text + _on_unlock_pressed) for all three passwords, photographs
## the panel locked and fully unlocked, then starts a battle as 刘谌.
## Run: xvfb-run godot --path . --resolution 1280x720 res://scenes/probe_hidden.tscn

var game: Node


func _ready() -> void:
	_beat("ready_start")
	game = load("res://scenes/main.tscn").instantiate()
	_beat("game_loaded")
	add_child(game)
	_beat("game_added")
	_run()


func _beat(tag: String) -> void:
	var f := FileAccess.open("res://.tmp/probe_hidden_hb.txt", FileAccess.WRITE_READ)
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
	print("PROBE_HIDDEN saved=", path)


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
	results["locked_marked_all_three"] = "锁" in String(locked_labels[0]) and "锁" in String(locked_labels[1]) and "锁" in String(locked_labels[2])
	results["locked_buttons_disabled"] = (buttons[9] as Button).disabled and (buttons[11] as Button).disabled and (buttons[14] as Button).disabled
	print("PROBE_HIDDEN locked_labels=", locked_labels)
	await _grab("res://shots/hidden_panel_locked.png")
	# Wrong password through the real UI handler.
	var pw_edit: LineEdit = game.get("pw_edit")
	pw_edit.text = "luboyanx"
	game.call("_on_unlock_pressed")
	await get_tree().create_timer(0.3).timeout
	results["wrong_pw_rejected_ui"] = bool(game.call("hero_is_locked", 9)) and "不对" in String((game.get("hero_detail_label") as Label).text)
	# Case + whitespace tolerant entry through the same handler.
	pw_edit.text = " LUBOYAN "
	game.call("_on_unlock_pressed")
	await get_tree().create_timer(0.3).timeout
	results["luboyan_ui_unlock"] = not bool(game.call("hero_is_locked", 9))
	results["luboyan_button_open"] = not (buttons[9] as Button).disabled and not ("锁" in (buttons[9] as Button).text)
	pw_edit.text = "muludawang"
	game.call("_on_unlock_pressed")
	await get_tree().create_timer(0.3).timeout
	results["muludawang_ui_unlock"] = not bool(game.call("hero_is_locked", 11))
	pw_edit.text = "beidiwang"
	game.call("_on_unlock_pressed")
	await get_tree().create_timer(0.3).timeout
	results["beidiwang_ui_unlock"] = not bool(game.call("hero_is_locked", 14))
	results["all_unlocked_ui"] = not bool(game.call("hero_is_locked", 9)) and not bool(game.call("hero_is_locked", 11)) and not bool(game.call("hero_is_locked", 14))
	print("PROBE_HIDDEN detail_after_unlock=", String((game.get("hero_detail_label") as Label).text))
	await _grab("res://shots/hidden_panel_unlocked.png")
	# Start a battle as 刘谌 (hidden, beidiwang) to prove end-to-end select.
	game.call("select_hero", 14)
	await get_tree().create_timer(1.0).timeout
	game.call("reset_camera_view")
	await get_tree().create_timer(0.5).timeout
	results["battle_started"] = String(game.get("game_state")) == "battle"
	var strat: Node = game.get("strategist")
	results["strategist_is_liuchen"] = strat != null and String(strat.get("display_name")) == "刘谌"
	await _grab("res://shots/hidden_battle_liuchen.png")
	print("PROBE_HIDDEN SUMMARY ", results)
	_beat("summary_printed")
	_beat("done")
	get_tree().quit()
