extends Node3D
## Edge & vista probe （边缘与远景）: photographs the classic full-field
## view, a pulled-far view (whole tray + surroundings) and a north
## backdrop close view, so rim sealing / mountain layering / fog
## depth can be judged before vs after. Tag via --tag=<name>.
## Run: xvfb-run godot --path . res://scenes/probe_edge.tscn -- --tag=before

var game: Node
var _tag := "before"
var _hide_near := false
var _hide_slabs := false


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--tag="):
			_tag = arg.trim_prefix("--tag=")
		if arg == "--hide-near":
			_hide_near = true
		if arg == "--hide-slabs":
			_hide_slabs = true
	game = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	_run()


func _grab(path: String) -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
	print("PROBE_EDGE saved=", path)


func _shot(tag: String, target: Vector3, dist: float) -> void:
	var dir: Vector3 = game.get("cam_dir")
	game.set("cam_target", target)
	game.set("cam_dist", dist)
	game.set("cam_dir", dir)
	game.call("_apply_camera")
	await get_tree().create_timer(0.35).timeout
	await _grab("res://shots/edge_%s_%s.png" % [_tag, tag])


func _run() -> void:
	await get_tree().create_timer(2.5).timeout
	game.call("select_hero", 0) # dismiss the hero-select panel
	await get_tree().create_timer(0.8).timeout
	await _shot("a", Vector3(-10, 0, 0), 100.0) # classic full field
	await _shot("b", Vector3(0, 0, 0), 150.0) # pulled far: the whole tray (CAM_MAX_DIST)
	if _hide_near:
		# Edge Rev 4 diagnostic: hide the north near-rim group (cliff
		# band + rim rock wall + foot boulders) and re-shoot b, so the
		# mid/far layers can be judged on their own before surgery.
		for node in game.find_children("*", "MeshInstance3D", true, false):
			var n := node as MeshInstance3D
			var nm := n.name
			var gp := n.global_position
			if nm == "NorthCliff" or ((nm.begins_with("RockWallMass") or nm.begins_with("RockCap") or nm.begins_with("RockFacet") or nm.begins_with("RockWedge") or nm == "Boulder") and gp.z < -40.0):
				n.visible = false
		await _shot("bn", Vector3(0, 0, 0), 150.0)
	if _hide_slabs:
		# Edge Rev 4 diagnostic: identify the dark quad in the s view.
		for node in game.find_children("*", "MeshInstance3D", true, false):
			var n2 := node as MeshInstance3D
			if n2.name.begins_with("OuterSlab") or n2.name == "OuterApron":
				n2.visible = false
		await _shot("sq", Vector3(0, 0, 56), 74.0)
	await _shot("c", Vector3(0, 0, -30), 62.0) # north rim + mountains close
	await _shot("s", Vector3(0, 0, 56), 74.0) # south rim profile: field -> terrace -> outer descent
	print("PROBE_EDGE done tag=", _tag)
	get_tree().quit()
