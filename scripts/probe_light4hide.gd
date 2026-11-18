extends Node3D
## Rev 4 square-boundary hunt: hide one candidate node group at a
## time and re-shoot the f view, to find which object draws the
## rectangular outline around the seal-core pedestal.
## Run: xvfb-run godot --path . res://scenes/probe_light4hide.tscn -- --quality=0

var game: Node


func _grab(path: String) -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
	print("PROBE_HIDE saved=", path)


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
	await _grab("res://shots/light_hidehunt_none.png")
	var patterns: Array = ["RoadApronCourtyard", "RoadRibbon*", "RoadCenter*", "GroundSurface", "CoreLightPool*", "RoadJoint*", "RoadApron*"]
	for pat in patterns:
		var nodes: Array = []
		for n in game.find_children(pat, "", true, false):
			if n is VisualInstance3D:
				nodes.append(n)
				n.visible = false
		await get_tree().create_timer(0.35).timeout
		var slug: String = pat.replace("*", "").to_lower()
		await _grab("res://shots/light_hidehunt_%s.png" % slug)
		for n in nodes:
			n.visible = true
		print("HIDEHUNT ", pat, " count=", nodes.size())
	get_tree().quit()
