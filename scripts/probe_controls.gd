extends Node3D
## Controls-revamp probe (2026-11-14 手游操作改版): runs the game in
## touch-UI mode, photographs the HUD (minimap + big skill button),
## then holds a joystick drag so the hero runs. Since 17:04 the camera
## is FREE (user call): it must not trail the hero; a later drag pan
## must persist. Run:
##   xvfb-run godot --path . res://scenes/probe_controls.tscn -- --touch-ui

var game: Node


func _ready() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	_run()


func _touch(index: int, pos: Vector2, pressed: bool) -> InputEventScreenTouch:
	var ev := InputEventScreenTouch.new()
	ev.index = index
	ev.position = pos
	ev.pressed = pressed
	return ev


func _drag(index: int, pos: Vector2, rel: Vector2) -> InputEventScreenDrag:
	var ev := InputEventScreenDrag.new()
	ev.index = index
	ev.position = pos
	ev.relative = rel
	return ev


func _grab(path: String) -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
	print("PROBE_CONTROLS saved=", path)


func _run() -> void:
	await get_tree().create_timer(2.5).timeout
	game.call("select_hero", 0) # 赵统
	await get_tree().create_timer(1.0).timeout
	game.call("_start_wave", 3)
	await get_tree().create_timer(0.6).timeout
	var guard := 0
	while not (game.get("spawn_queue") as Array).is_empty() and guard < 160:
		game.call("_spawn_from_queue")
		guard += 1
	await get_tree().create_timer(1.2).timeout
	await _grab("res://shots/controls_a_overview.png")
	var vp := get_viewport().get_visible_rect().size
	var strat: Node3D = game.get("strategist")
	print("PROBE_CONTROLS hero_before=", strat.global_position, " cam_target=", game.get("cam_target"))
	var origin := vp * Vector2(0.20, 0.72)
	game.call("_unhandled_input", _touch(0, origin, true))
	for i in range(5):
		game.call("_unhandled_input", _drag(0, origin + Vector2(22.0 * float(i + 1), 8.0 * float(i + 1)), Vector2(22, 8)))
		await get_tree().create_timer(0.12).timeout
	await get_tree().create_timer(1.4).timeout
	await _grab("res://shots/controls_b_joystick.png")
	print("PROBE_CONTROLS hero_after=", strat.global_position, " cam_target=", game.get("cam_target"), " joy_index=", game.get("_joy_index"))
	game.call("_unhandled_input", _touch(0, origin + Vector2(110, 40), false))
	await get_tree().create_timer(0.8).timeout
	await _grab("res://shots/controls_c_released.png")
	print("PROBE_CONTROLS hero_final=", strat.global_position, " cam_target=", game.get("cam_target"))
	# Free camera: drag on the battlefield pans, and it stays panned.
	var pan_from: Vector3 = game.get("cam_target")
	var pan_start := vp * Vector2(0.72, 0.45)
	game.call("_unhandled_input", _touch(1, pan_start, true))
	for i in range(5):
		game.call("_unhandled_input", _drag(1, pan_start + Vector2(-28.0 * float(i + 1), 0), Vector2(-28, 0)))
	game.call("_unhandled_input", _touch(1, pan_start + Vector2(-140, 0), false))
	await get_tree().create_timer(0.9).timeout
	var pan_to: Vector3 = game.get("cam_target")
	print("PROBE_CONTROLS free_pan ", pan_from, " -> ", pan_to, " moved=", pan_from.distance_to(pan_to))
	await _grab("res://shots/controls_d_panned.png")
	get_tree().quit()
