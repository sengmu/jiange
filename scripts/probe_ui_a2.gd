extends Node3D
## UI-A2 geometry probe (2026-11-15, 0.1.44 geometry-fix round):
## prints get_global_rect() of the HUD controls under the touch layout,
## unprojects the world Label3D "新城" to a screen rect, and captures:
##  1 shots/uiA2_select.png   — select panel (touch layout)
##  2 shots/uiA2_hud.png      — battle HUD, default camera
##  3 shots/uiA2_joystick.png — joystick engaged (bronze ring evidence)
## Run: xvfb-run godot --path . --resolution 1920x864 res://scenes/probe_ui_a2.tscn -- --touch-ui --quality=0

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
	print("PROBE_UI_A2 saved=", path)


func _rect_str(c: Control) -> String:
	if c == null:
		return "null"
	var r := c.get_global_rect()
	return "[P:(%.1f,%.1f) S:(%.1f,%.1f) E:(%.1f,%.1f)]" % [r.position.x, r.position.y, r.size.x, r.size.y, r.end.x, r.end.y]


func _print_rects(tag: String) -> void:
	var vp := get_viewport().get_visible_rect().size
	print("GEO ", tag, " vp=", vp)
	for pair in [["message_label", "message_label"], ["_minimap", "_minimap"], ["_big_skill_button", "_big_skill_button"], ["inv_row", "inv_row"], ["_action_col", "_action_col"], ["bottom_bar", "bottom_bar"], ["hud_panel", "hud_panel"]]:
		var c = game.get(pair[1])
		print("GEO ", tag, " ", pair[0], " ", _rect_str(c as Control))
	_print_newcity(tag)


func _find_label3d(n: Node, text: String) -> Label3D:
	if n is Label3D and (n as Label3D).text == text:
		return n as Label3D
	for ch in n.get_children():
		var f := _find_label3d(ch, text)
		if f != null:
			return f
	return null


func _print_newcity(tag: String) -> void:
	var lab := _find_label3d(game, "新城")
	var cam: Camera3D = game.get("camera")
	if lab == null or cam == null:
		print("GEO ", tag, " newcity label_or_cam_null")
		return
	var pos := lab.global_position
	var origin := cam.unproject_position(pos)
	var ppu := cam.unproject_position(pos + cam.global_transform.basis.x).distance_to(origin)
	if ppu < 0.01:
		ppu = 40.0
	# Project finding (Rev 3): Label3D text hangs DOWN from its origin
	# (origin = top-centre). "新城" = 2 glyphs at 108pt * 0.02 = 2.16 world
	# units tall; outline inflates the visual box by roughly a third.
	var w_world := 2.0 * 2.16 * 1.18
	var h_world := 2.16 * 1.36
	var r := Rect2(origin - Vector2(w_world * 0.5 * ppu, 0.0), Vector2(w_world * ppu, h_world * ppu))
	print("GEO ", tag, " newcity_screen_rect=", r, " ppu=", ppu)
	var hp := (game.get("hud_panel") as Control).get_global_rect()
	print("GEO ", tag, " newcity_vs_hud_intersects=", r.intersects(hp), " hud=", hp)


func _run() -> void:
	await get_tree().create_timer(2.5).timeout
	_print_rects("select")
	await _grab("res://shots/uiA2_select.png")
	game.call("_on_hero_button", 0)
	await get_tree().create_timer(0.3).timeout
	game.call("select_hero", 0)
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
	_print_rects("battle")
	await _grab("res://shots/uiA2_hud.png")
	# Joystick engaged state (bronze ring evidence, missing in 0.1.43).
	var joy = game.get("_joy")
	var vp := get_viewport().get_visible_rect().size
	if joy != null:
		joy.call("engage", Vector2(vp.x * 0.16, vp.y * 0.70))
		joy.call("drag_to", Vector2(vp.x * 0.16 + 42.0, vp.y * 0.70 - 30.0))
		await get_tree().create_timer(0.4).timeout
		await _grab("res://shots/uiA2_joystick.png")
		joy.call("disengage")
	print("PROBE_UI_A2 done")
	get_tree().quit()
