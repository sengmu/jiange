extends Node3D
## Touch-controls probe (mobile round): drives the real game scene with
## synthetic touch events and photographs the results at 1280x720.
##  1 shots/touch_01_selected.png — tap on the strategist selects him.
##  2 shots/touch_02_move.png     — tap on ground orders a move (marker up).
##  3 shots/touch_03_panzoom.png  — after one-finger drag pan + pinch zoom.
##  4 shots/touch_04_skill.png    — after tapping the skill button (cast).
## Button taps go through Input.parse_input_event (the real viewport
## pipeline), which only dispatches when a real window exists — hence this
## probe runs under xvfb, not in the headless harness.
## Run: xvfb-run godot --path . res://scenes/probe_touch.tscn

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


func _find_button(node: Node, text: String) -> Button:
	if node is Button and (node as Button).is_visible_in_tree() and (node as Button).text == text:
		return node as Button
	for child in node.get_children():
		var found := _find_button(child, text)
		if found != null:
			return found
	return null


func _grab(path: String) -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
	print("PROBE_TOUCH saved=", path)


func _run() -> void:
	await get_tree().create_timer(2.5).timeout
	game.call("select_hero", 0) # 赵统
	await get_tree().create_timer(1.2).timeout
	game.call("reset_camera_view")
	var vp := get_viewport().get_visible_rect().size
	var cam: Camera3D = game.get("camera")
	var strat: Node = game.get("strategist")
	var marker: Node3D = game.get("move_marker")
	var results := {}

	# 1 tap on the strategist selects him.
	game.set("selected", false)
	var strat_screen := cam.unproject_position(strat.global_position + Vector3(0, 1.2, 0))
	game.call("_unhandled_input", _touch(0, strat_screen, true))
	game.call("_unhandled_input", _touch(0, strat_screen, false))
	await get_tree().create_timer(0.2).timeout
	results["tap_select"] = bool(game.get("selected"))
	print("PROBE_TOUCH tap_select=", results["tap_select"], " strat_screen=", strat_screen, " vp=", vp)
	await _grab("res://shots/touch_01_selected.png")

	# 2 tap on empty ground orders a move: aim at clear ground east of
	# the hero by projection (valid under any camera — since 2026-11-14
	# 17:04 the touch camera is free and stays at the reset view here).
	marker.visible = false
	var move_screen := cam.unproject_position(strat.global_position + Vector3(12, 0, 0))
	game.call("_unhandled_input", _touch(0, move_screen, true))
	game.call("_unhandled_input", _touch(0, move_screen, false))
	await get_tree().create_timer(0.2).timeout
	results["tap_move"] = marker.visible
	print("PROBE_TOUCH tap_move_marker=", results["tap_move"])
	await _grab("res://shots/touch_02_move.png")

	# 3 drag pans, pinch zooms.
	var tgt0: Vector3 = game.get("cam_target")
	var dist0 := float(game.get("cam_dist"))
	var drag_start := vp * Vector2(0.5, 0.45)
	game.call("_unhandled_input", _touch(0, drag_start, true))
	for i in range(5):
		game.call("_unhandled_input", _drag(0, drag_start + Vector2(30.0 * float(i + 1), 0), Vector2(30, 0)))
	game.call("_unhandled_input", _touch(0, drag_start + Vector2(150, 0), false))
	var f0 := vp * Vector2(0.35, 0.5)
	var f1 := vp * Vector2(0.65, 0.5)
	game.call("_unhandled_input", _touch(0, f0, true))
	game.call("_unhandled_input", _touch(1, f1, true))
	game.call("_unhandled_input", _drag(0, vp * Vector2(0.30, 0.5), Vector2(-64, 0)))
	game.call("_unhandled_input", _drag(1, vp * Vector2(0.70, 0.5), Vector2(64, 0)))
	game.call("_unhandled_input", _touch(0, vp * Vector2(0.30, 0.5), false))
	game.call("_unhandled_input", _touch(1, vp * Vector2(0.70, 0.5), false))
	await get_tree().create_timer(0.3).timeout
	var tgt1: Vector3 = game.get("cam_target")
	var dist1 := float(game.get("cam_dist"))
	results["drag_pan"] = (tgt1 - tgt0).length() > 0.5
	results["pinch_zoom"] = dist1 < dist0 - 0.5
	print("PROBE_TOUCH drag_pan=", results["drag_pan"], " target ", tgt0, " -> ", tgt1, " pinch_zoom=", results["pinch_zoom"], " dist %.1f -> %.1f" % [dist0, dist1])
	await _grab("res://shots/touch_03_panzoom.png")

	# 4 HUD buttons through the real viewport pipeline: park a durable
	# enemy next to the strategist, tap the skill button, then restart.
	game.call("reset_camera_view")
	game.set("spawn_queue", [])
	game.call("_spawn_enemy")
	await get_tree().create_timer(0.5).timeout
	var foe: Node = null
	for e in game.get("enemies"):
		if is_instance_valid(e) and bool(e.get("alive")):
			foe = e
			break
	if foe != null:
		foe.set("max_hp", 99999.0)
		foe.set("hp", 99999.0)
		foe.set("global_position", strat.global_position + Vector3(6, 0, 0))
	game.set("skill_cooldown", 0.0)
	# Touch layout (2026-11-14 归类整合): the bar skill button is retired
	# in touch mode — the big round button is the skill control there.
	var skill_btn: Button = game.get("_big_skill_button") if bool(game.get("_touch_ui")) else game.get("skill_button")
	if skill_btn == null:
		skill_btn = game.get("skill_button")
	var skill_rect := skill_btn.get_global_rect()
	var skill_center := skill_rect.get_center() if skill_rect.size.x > 10.0 else Vector2(104, vp.y - 41)
	print("PROBE_TOUCH skill_rect=", skill_rect, " tap=", skill_center, " foe=", foe != null)
	Input.parse_input_event(_touch(0, skill_center, true))
	Input.parse_input_event(_touch(0, skill_center, false))
	await get_tree().create_timer(0.8).timeout
	results["skill_button"] = float(game.get("skill_cooldown")) > 0.0
	print("PROBE_TOUCH skill_button_cast=", results["skill_button"], " cooldown=", game.get("skill_cooldown"), " feedback=", game.get("last_chain_feedback"))
	await _grab("res://shots/touch_04_skill.png")
	var restart_btn := _find_button(game, "重开")
	if restart_btn != null:
		var rrect := restart_btn.get_global_rect()
		var rc := rrect.get_center() if rrect.size.x > 10.0 else Vector2(408, vp.y - 41)
		print("PROBE_TOUCH restart_rect=", rrect, " tap=", rc)
		Input.parse_input_event(_touch(0, rc, true))
		Input.parse_input_event(_touch(0, rc, false))
		await get_tree().create_timer(0.8).timeout
		results["restart_button"] = String(game.get("game_state")) == "select" and int(game.get("gold")) == 50
		print("PROBE_TOUCH restart_button_reset=", results["restart_button"], " state=", game.get("game_state"), " gold=", game.get("gold"))
	else:
		results["restart_button"] = false
		print("PROBE_TOUCH restart button not found")
	print("PROBE_TOUCH SUMMARY ", results)
	get_tree().quit()
