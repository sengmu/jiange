extends Node3D
## Rev 4 square-boundary hunt round 3: direct references only
## (member vars / exact unique names), f view, one variable per shot.
## Run: xvfb-run godot --path . res://scenes/probe_light4rect.tscn -- --quality=0

var game: Node


func _grab(path: String) -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
	print("PROBE_RECT saved=", path)


func _set_cam(target: Vector3, dist: float) -> void:
	var dir: Vector3 = game.get("cam_dir")
	game.set("cam_target", target)
	game.set("cam_dist", dist)
	game.set("cam_dir", dir)
	game.call("_apply_camera")


func _ready() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	_run()


func _run() -> void:
	await get_tree().create_timer(2.5).timeout
	game.call("select_hero", 0)
	await get_tree().create_timer(1.0).timeout
	_set_cam(Vector3(-70, 0, 0), 19.0)
	await get_tree().create_timer(0.6).timeout
	await _grab("res://shots/light_rect_none.png")
	var sun = game.get("sun_light")
	sun.shadow_enabled = false
	await get_tree().create_timer(0.35).timeout
	await _grab("res://shots/light_rect_sunoff.png")
	sun.shadow_enabled = true
	game.get("crystal_light").shadow_enabled = false
	await get_tree().create_timer(0.35).timeout
	await _grab("res://shots/light_rect_coreoff.png")
	sun.shadow_enabled = false
	await get_tree().create_timer(0.35).timeout
	await _grab("res://shots/light_rect_dualoff.png")
	sun.shadow_enabled = true
	game.get("crystal_light").shadow_enabled = true
	var gs = game.get("ground_surface")
	if gs != null:
		gs.visible = false
	await get_tree().create_timer(0.35).timeout
	await _grab("res://shots/light_rect_gs_off.png")
	if gs != null:
		gs.visible = true
	var core = game.find_child("SealCore", true, false)
	if core != null:
		core.visible = false
	await get_tree().create_timer(0.35).timeout
	await _grab("res://shots/light_rect_corehide.png")
	get_tree().quit()
