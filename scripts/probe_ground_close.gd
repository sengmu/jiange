extends Node3D
## Ground close-ups (diagnostic for VISUAL_AUDIT P1-1 residuals): two
## near-camera shots of the exact spots Codex keeps flagging, hero
## selected first so no select panel covers the ground.
##  BL (.tmp/close_bl.png): training-zone grass south-west of the base
##      wall (world ~(-52, 0, 33)) — "dark triangular spikes" spot.
##  RB (.tmp/close_rb.png): east bend road by the plaza (world ~(52, 0, 8))
##      — "flat road interior / clean arc edge" spot.
## Run: xvfb-run godot --path . res://scenes/probe_ground_close.tscn

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
	print("PROBEGROUNDCLOSE saved=", path)


func _frame_at(target: Vector3, dist: float) -> void:
	var off := Vector3(0.0, 81.92, 57.36)
	game.set("cam_target", target)
	game.set("cam_dist", dist)
	game.set("cam_dir", off / off.length())
	game.call("_apply_camera")


func _run() -> void:
	await get_tree().create_timer(2.0).timeout
	game.call("select_hero", 0)
	await get_tree().create_timer(1.0).timeout
	_frame_at(Vector3(-52.0, 0.0, 33.0), 42.0)
	await _grab("res://.tmp/close_bl.png")
	_frame_at(Vector3(52.0, 0.0, 8.0), 42.0)
	await _grab("res://.tmp/close_rb.png")
	get_tree().quit()
