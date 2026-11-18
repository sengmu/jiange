extends Node3D
## Camera-fix captures: instances the real game scene.
##  A (shots/camera_classic_a.png): new classic War3 default framing at
##     wave-1 start.
##  B (shots/camera_classic_b.png): wave-2 mid-battle, units on the road,
##     new framing.
##  Compare pair: at the same battle moment as B, the OLD pre-fix default
##  framing is staged by writing the old constants into the camera vars
##  (.tmp/cam_old_frame.png), then reset_camera_view() restores the new
##  default for B. Wave jump is capture staging through the game's own
##  _start_wave(), same convention as the built-in SLICE_CAPTURE probes.
## Run: xvfb-run godot --path . res://scenes/probe_cam.tscn

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
	print("PROBECAM saved=", path)


func _set_old_camera() -> void:
	var tgt := Vector3(-6.5, 0.0, -4.5)
	var off := Vector3(-33.0, 14.5, 24.6) - tgt
	game.set("cam_target", tgt)
	game.set("cam_dist", off.length())
	game.set("cam_dir", off / off.length())
	game.call("_apply_camera")


func _run() -> void:
	# A: wave-1 start under the new default framing (game boots into wave 1).
	await get_tree().create_timer(3.2).timeout
	await _grab("res://shots/camera_classic_a.png")
	# Advance to wave 2 (staging) and poll until the road is populated.
	game.call("_start_wave", 2)
	var waited := 0.0
	var ready := false
	while waited < 60.0 and not ready:
		await get_tree().create_timer(0.25).timeout
		waited += 0.25
		var on_road := 0
		for e in game.call("alive_enemies"):
			var ex: float = e.global_position.x
			if ex >= -8.0 and ex <= 24.0:
				on_road += 1
		if on_road >= 6:
			ready = true
	print("PROBECAM wave2 poll waited=", waited, " ready=", ready)
	# Same moment: OLD framing first, then reset to the new default for B.
	_set_old_camera()
	await _grab("res://.tmp/cam_old_frame.png")
	game.call("reset_camera_view")
	await _grab("res://shots/camera_classic_b.png")
	get_tree().quit()
