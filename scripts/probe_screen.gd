extends Node3D
## Screen & posture probe (mobile round): verifies the HUD at a desktop
## 1280x720 window and at a phone-like 1920x864 window with --touch-ui
## and an optional --safe-area=L,T,R,B override (simulated notch /
## gesture bar, screen px). Photographs the select panel and the in-game
## HUD, prints every edge-anchored widget rect, and asserts the widgets
## stay inside the safe area.
## Run (desktop): xvfb-run godot --path . --resolution 1280x720 res://scenes/probe_screen.tscn
## Run (phone):  xvfb-run godot --path . --resolution 1920x864 res://scenes/probe_screen.tscn -- --touch-ui --safe-area=90,50,90,40

var game: Node


func _ready() -> void:
	_beat("ready_start")
	game = load("res://scenes/main.tscn").instantiate()
	_beat("game_loaded")
	add_child(game)
	_beat("game_added")
	_run()


func _beat(tag: String) -> void:
	var f := FileAccess.open("res://.tmp/probe_screen_hb.txt", FileAccess.WRITE_READ)
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
	print("PROBE_SCREEN saved=", path)


func _run() -> void:
	_beat("run_start")
	await get_tree().create_timer(2.0).timeout
	_beat("after_2s_timer")
	var vp := get_viewport().get_visible_rect().size
	var touch_ui := bool(game.call("_touch_ui_enabled"))
	var insets: Vector4 = game.call("_compute_safe_insets")
	var prefix := "screen_touch" if touch_ui else "screen_desktop"
	print("PROBE_SCREEN vp=", vp, " touch_ui=", touch_ui, " insets=", insets,
		" handheld_orientation=", ProjectSettings.get_setting("display/window/handheld/orientation"),
		" keep_screen_on=", ProjectSettings.get_setting("display/window/handheld/keep_screen_on"))
	var results := {}
	# Select panel must fit inside the viewport (with margins).
	var panel: PanelContainer = game.get("select_panel")
	var prect := panel.get_global_rect()
	results["select_fits"] = prect.position.x >= 0.0 and prect.position.y >= 0.0 and prect.end.x <= vp.x + 1.0 and prect.end.y <= vp.y + 1.0
	print("PROBE_SCREEN select_rect=", prect, " fits=", results["select_fits"])
	# The top message is hidden while the select panel is open (it would
	# overlap the panel title on phones with a top safe-area inset).
	var msg0: Label = game.get("message_label")
	results["message_hidden_in_select"] = not msg0.visible
	await _grab("res://shots/" + prefix + "_01_select.png")

	# Start the game and photograph the in-game HUD.
	game.call("select_hero", 0) # 赵统
	await get_tree().create_timer(1.0).timeout
	game.call("reset_camera_view")
	await get_tree().create_timer(0.5).timeout
	vp = get_viewport().get_visible_rect().size
	var skill: Button = game.get("skill_button")
	var srect := skill.get_global_rect()
	var bottom: HBoxContainer = game.get("bottom_bar")
	var brect := bottom.get_global_rect()
	var hud: PanelContainer = game.get("hud_panel")
	var hrect := hud.get_global_rect()
	var help: Label = game.get("help_label")
	var helprect := help.get_global_rect()
	var msg: Label = game.get("message_label")
	var mrect := msg.get_global_rect()
	print("PROBE_SCREEN skill_rect=", srect, " bottom_rect=", brect, " hud_rect=", hrect, " help_rect=", helprect, " msg_rect=", mrect)
	var want_h := 64.0 if touch_ui else 46.0
	results["skill_button_height"] = is_equal_approx(srect.size.y, want_h)
	# Non-vacuous: the bar must really sit on screen in the bottom strip,
	# not above the viewport (a negative rect would pass a bare end.y test).
	results["bottom_inside_safe"] = brect.position.y > vp.y * 0.5 and brect.end.y <= vp.y - 18.0 - insets.w + 1.0 and brect.position.x >= 16.0 + insets.x - 1.0
	results["hud_inside_safe"] = hrect.position.x >= 16.0 + insets.x - 1.0 and hrect.position.y >= 14.0 + insets.y - 1.0
	results["help_inside_safe"] = helprect.end.x <= vp.x - 16.0 - insets.z + 1.0 and helprect.position.y > vp.y * 0.5
	results["message_centered"] = absf(mrect.position.x - (vp.x - 640.0) / 2.0) < 2.0 and is_equal_approx(mrect.position.y, 16.0 + insets.y)
	print("PROBE_SCREEN skill_h=", srect.size.y, " want=", want_h)
	print("PROBE_SCREEN SUMMARY ", results)
	_beat("summary_printed")
	await _grab("res://shots/" + prefix + "_02_hud.png")
	_beat("done")
	get_tree().quit()
