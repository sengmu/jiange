extends Node3D
## Rev 5 (light) diagnostic battery: single-variable toggles for
## debt (a) near-base pale rectangle, (b) ground/crystal banding,
## (d) core spill floor, (e) gate coupling matrix, (f) cliff fill reach.
## Runtime-only: no production defaults are changed.
## Run: xvfb-run godot --path . res://scenes/probe_light5diag.tscn -- --quality=0

var game: Node
var world_mis: Array = []
var merged_mis: Array = []


func _grab(path: String) -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
	print("PROBE_L5D saved=", path)


func _set_cam(target: Vector3, dist: float) -> void:
	var dir: Vector3 = game.get("cam_dir")
	game.set("cam_target", target)
	game.set("cam_dist", dist)
	game.set("cam_dir", dir)
	game.call("_apply_camera")


func _collect() -> void:
	world_mis.clear()
	merged_mis.clear()
	var wr = game.get("world_root")
	var stack: Array = [wr]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if n is MeshInstance3D:
			if String(n.name).begins_with("MergedStatic"):
				merged_mis.append(n)
			else:
				world_mis.append(n)
	print("L5D collected originals=", world_mis.size(), " merged=", merged_mis.size())


func _set_unmerged(on: bool) -> void:
	for m in merged_mis:
		(m as MeshInstance3D).visible = not on
	for m in world_mis:
		(m as MeshInstance3D).visible = on


func _hide_match(substr: String) -> int:
	var n := 0
	for m in world_mis:
		if String((m as Node).name).contains(substr):
			(m as MeshInstance3D).visible = false
			n += 1
	return n


func _shot(name: String) -> void:
	await get_tree().create_timer(0.45).timeout
	await _grab("res://shots/l5d_%s.png" % name)


func _run() -> void:
	await get_tree().create_timer(2.5).timeout
	game.call("select_hero", 0)
	await get_tree().create_timer(1.0).timeout
	_collect()
	var sun = game.get("sun_light")
	var cam = game.get("camera")
	# ---- f view battery (core close-up) ----
	_set_cam(Vector3(-70, 0, 0), 19.0)
	await get_tree().create_timer(0.6).timeout
	# ray -> ground-plane prints for the rectangle hunt
	for px in [Vector2(208, 477), Vector2(250, 450), Vector2(330, 455), Vector2(150, 500)]:
		var o: Vector3 = (cam as Camera3D).project_ray_origin(px)
		var d: Vector3 = (cam as Camera3D).project_ray_normal(px)
		for h in [0.0, 0.0555, 0.06]:
			if absf(d.y) > 0.001:
				var t: float = (h - o.y) / d.y
				var p: Vector3 = o + d * t
				print("L5D ray px=", px, " h=", h, " world=", Vector2(snappedf(p.x, 0.1), snappedf(p.z, 0.1)))
	await _shot("f_base")
	sun.shadow_enabled = false
	await _shot("f_sunoff")
	sun.shadow_enabled = true
	sun.light_energy = 0.0
	await _shot("f_sunzero")
	sun.light_energy = 0.50
	game.get("env_ref").glow_enabled = false
	await _shot("f_glowoff")
	game.get("env_ref").glow_enabled = true
	# core contribution floor (debt d): core omnis off + pool discs hidden
	var cl = game.get("crystal_light")
	var cf = game.get("core_fill_light")
	var cw = game.get("core_wash_light")
	cl.light_energy = 0.0
	cf.light_energy = 0.0
	cw.light_energy = 0.0
	var pooled := 0
	for m in world_mis:
		if String((m as Node).name).contains("CoreLightPool"):
			(m as MeshInstance3D).visible = false
			pooled += 1
	print("L5D pool discs hidden=", pooled)
	await _shot("f_coreoff")
	cl.light_energy = 3.4
	cf.light_energy = 1.05
	cw.light_energy = 0.8
	# unmerged difference tests (debt a)
	_set_unmerged(true)
	await _shot("f_unmerged")
	for spec in [["nocenter", "RoadCenter"], ["noribbon", "RoadRibbon"], ["nojoint", "RoadJoint"], ["noapron", "RoadApron"], ["nopavedisc", "CourtyardPaveDisc"], ["noground", "GroundSurface"], ["nocore", "SealCore"]]:
		_set_unmerged(true)
		var hn := _hide_match(spec[1])
		print("L5D hide ", spec[1], " count=", hn)
		await _shot("f_" + spec[0])
	_set_unmerged(true)
	sun.shadow_enabled = false
	await _shot("f_unmerged_sunoff")
	sun.shadow_enabled = true
	_set_unmerged(false)
	# ---- h view (guard feet; ground banding) ----
	var guard = game.get("general")
	if is_instance_valid(guard):
		_set_cam((guard as Node3D).global_position, 11.0)
		await get_tree().create_timer(0.6).timeout
		await _shot("h_base")
		sun.shadow_enabled = false
		await _shot("h_sunoff")
		sun.shadow_enabled = true
	# ---- e view gate coupling matrix (debt e) ----
	_set_cam(Vector3(-59, 0, -13), 14.0)
	await get_tree().create_timer(0.6).timeout
	await _shot("e_base")
	var cool = game.get("cool_fill_light")
	cool.light_energy = 0.0
	await _shot("e_cooloff")
	cool.light_energy = 0.80
	var gf = game.get("gate_front_fill_light")
	gf.light_energy = 0.0
	await _shot("e_frontoff")
	gf.light_energy = 6.5
	var gs = game.get("gate_fill_light")
	gs.light_energy = 0.0
	await _shot("e_sideoff")
	gs.light_energy = 3.0
	sun.shadow_enabled = false
	await _shot("e_sunoff")
	sun.shadow_enabled = true
	# ---- c view cliff fill reach (debt f) ----
	_set_cam(Vector3(-58, 0, 0), 58.0)
	await get_tree().create_timer(0.6).timeout
	await _shot("c_base")
	var ff = game.get("cliff_fill_light")
	ff.light_energy = 0.0
	await _shot("c_cliffoff")
	ff.light_energy = 5.8
	ff.spot_angle = 48.0
	await _shot("c_cliffwide")
	ff.spot_angle = 36.0
	ff.position = Vector3(-86, 5, 0)
	ff.look_at(Vector3(-97, 0, -2), Vector3.UP)
	await _shot("c_cliffwest")
	get_tree().quit()


func _ready() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	_run()
