extends Node3D
## Rift6 diagnostic (temporary): world AABBs of north-rift rocks + energy
## nodes, projected into the rift_n / riftfar probe cameras to identify
## which rock occludes the energy lower tip on screen.

var game: Node

func _ready() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	_run()

func _world_aabb(root: Node) -> AABB:
	var out := AABB()
	var first := true
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D:
			var mi := n as MeshInstance3D
			if mi.mesh != null:
				var ab: AABB = mi.global_transform * mi.get_aabb()
				if first:
					out = ab
					first = false
				else:
					out = out.merge(ab)
		for c in n.get_children():
			stack.append(c)
	return out

func _screen_bbox(cam: Camera3D, ab: AABB) -> Rect2:
	var pts: Array = []
	for i in range(8):
		var corner := ab.position + Vector3(
			ab.size.x if (i & 1) else 0.0,
			ab.size.y if (i & 2) else 0.0,
			ab.size.z if (i & 4) else 0.0)
		if cam.is_position_behind(corner):
			return Rect2()
		pts.append(cam.unproject_position(corner))
	var r := Rect2(pts[0], Vector2.ZERO)
	for p in pts:
		r = r.expand(p)
	return r

func _report(cam: Camera3D, label: String, portal: Node3D, rocks: Array) -> void:
	var gt: Transform3D = portal.global_transform
	var tips := {
		"core_bottom": gt * Vector3(0.10, -2.50, 0.09),
		"shard_bottom": gt * Vector3(-0.14, -2.35, 0.34),
		"void_bottom": gt * Vector3(0.0, -3.45, 0.0),
		"core_center": gt * Vector3(0.10, 0.0, 0.09),
	}
	print("RIFT6DIAG cam=", label)
	for k in tips.keys():
		var w: Vector3 = tips[k]
		var sp := cam.unproject_position(w)
		print("RIFT6DIAG tip ", k, " world=", w, " screen=", sp, " camdist=", snappedf(cam.global_position.distance_to(w), 0.01))
	for r in rocks:
		var ab := _world_aabb(r)
		var bb := _screen_bbox(cam, ab)
		var centre := ab.get_center()
		var cd := snappedf(cam.global_position.distance_to(centre), 0.01)
		var covers := ""
		for k in tips.keys():
			var sp := cam.unproject_position(tips[k])
			if bb.has_point(sp):
				covers += k + "(tipdist=" + str(snappedf(cam.global_position.distance_to(tips[k]), 0.01)) + ",rockdist=" + str(cd) + ") "
		print("RIFT6DIAG rock ", r.name, " aabb_min=", ab.position, " aabb_max=", ab.end, " screen=", bb, " covers: ", covers)

func _run() -> void:
	await get_tree().create_timer(2.5).timeout
	game.call("select_hero", 0)
	await get_tree().create_timer(1.0).timeout
	game.call("reset_camera_view")
	await get_tree().create_timer(0.5).timeout
	var cam: Camera3D = game.get("camera")
	var portal := game.find_child("RiftPortal", true, false) as Node3D
	print("RIFT6DIAG portal pos=", portal.global_position)
	var rocks: Array = []
	for n in game.find_children("RiftMouthRockN*", "Node3D", true, false):
		rocks.append(n)
	for n in game.find_children("RiftFrameRockN*", "Node3D", true, false):
		rocks.append(n)
	# energy node AABBs
	for en in ["RiftVoid", "RiftVoidB", "RiftCore", "RiftFunnel", "RiftInnerGlow", "RiftShard", "RiftVortexRing"]:
		var node := portal.find_child(en, false, false)
		if node != null:
			print("RIFT6DIAG energy ", en, " aabb=", _world_aabb(node))
	# neighbours near the north portal (trees etc.)
	var wr: Node = game.get("world_root")
	var ppos := portal.global_position
	for n in wr.get_children():
		if n is Node3D and n != portal:
			var d: Vector3 = (n as Node3D).global_position - ppos
			d.y = 0.0
			if d.length() < 11.0:
				print("RIFT6DIAG neighbour ", n.name, " pos=", (n as Node3D).global_position)
	# rift_n camera
	game.set("cam_target", Vector3(77, 0, -26))
	game.set("cam_dist", 26.0)
	game.call("_apply_camera")
	await get_tree().create_timer(0.3).timeout
	_report(cam, "rift_n", portal, rocks)
	# riftfar camera
	game.set("cam_target", Vector3(77, 2.0, -26))
	game.set("cam_dist", 55.0)
	game.call("_apply_camera")
	await get_tree().create_timer(0.3).timeout
	_report(cam, "riftfar", portal, rocks)
	get_tree().quit()
