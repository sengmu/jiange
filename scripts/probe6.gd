extends Node3D
## Fast core-color check: instances the real game scene and grabs the
## default-camera frame a few seconds in (seal core in frame, wave 1
## marching). Run: xvfb-run godot --path . res://scenes/probe6.tscn


func _ready() -> void:
	var game: Node = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	_run()


func _run() -> void:
	await get_tree().create_timer(3.0).timeout
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("res://shots/probe6_core_final.png")
	print("PROBE6 saved")
	get_tree().quit()
