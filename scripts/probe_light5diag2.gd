extends Node3D
## Rev 5 (light) diagnostic battery #2: c view FIRST (camera drift guard),
## gate fill re-aim coupling tests, AABB-candidate hide test for the
## near-base pale patch, sun shadow bias sweep on the f view.
## Runtime-only: no production defaults are changed.

var game: Node
var world_mis: Array = []
var merged_mis: Array = []


func _grab(path: String) -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
	print("PROBE_L5D2 saved=", path)


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


func _set_unmerged(on: bool) -> void:
	for m in merged_mis:
		(m as MeshInstance3D).visible = not on
	for m in world_mis:
		(m as MeshInstance3D).visible = on


func _shot(name: String) -> void:
	await get_tree().create_timer(0.45).timeout
	await _grab("res://shots/l5d2_%s.png" % name)


func _run() -> void:
	await get_tree().create_timer(2.5).timeout
	game.call("select_hero", 0)
	await get_tree().create_timer(1.0).timeout
	_collect()
	var sun = game.get("sun_light")
	print("L5D2 sun bias=", sun.shadow_bias, " normal_bias=", sun.shadow_normal_bias)
	# ---- c view FIRST: cliff fill variants ----
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
	ff.position = Vector3(-84, 6, -6)
	ff.look_at(Vector3(-95, 0, 0), Vector3.UP)
	await _shot("c_cliffwest")
	ff.position = Vector3(-74, 7, 0)
	ff.look_at(Vector3(-88, 0, -2), Vector3.UP)
	ff.light_energy = 9.0
	await _shot("c_cliffhot")
	ff.light_energy = 5.8
	# ---- e view: gate fill re-aim tests ----
	_set_cam(Vector3(-59, 0, -13), 14.0)
	await get_tree().create_timer(0.6).timeout
	await _shot("e_base")
	var gf = game.get("gate_front_fill_light")
	gf.spot_range = 52.0
	await _shot("e_frontrange")
	gf.position = Vector3(-38, 6, 10)
	gf.look_at(Vector3(-57, 3, -2), Vector3.UP)
	await _shot("e_frontmove")
	var gs = game.get("gate_fill_light")
	gs.light_energy = 4.5
	gs.spot_range = 44.0
	await _shot("e_sideboost")
	# ---- f view: patch AABB candidates + sun bias sweep ----
	_set_cam(Vector3(-70, 0, 0), 19.0)
	await get_tree().create_timer(0.6).timeout
	await _shot("f_base")
	sun.shadow_normal_bias = 1.2
	await _shot("f_nb12")
	sun.shadow_normal_bias = 2.0
	await _shot("f_nb20")
	sun.shadow_normal_bias = 0.6
	sun.shadow_bias = 0.1
	await _shot("f_b10")
	sun.shadow_bias = 0.03
	_set_unmerged(true)
	await _shot("f_unmerged")
	var probe_box := AABB(Vector3(-77.2, -0.05, 1.2), Vector3(1.6, 0.2, 2.0))
	var cands: Array = []
	for m in world_mis:
		var mi := m as MeshInstance3D
		var ab := mi.get_aabb()
		var gxf := mi.global_transform
		var corners: Array = []
		for cx in [0.0, 1.0]:
			for cy in [0.0, 1.0]:
				for cz in [0.0, 1.0]:
					corners.append(gxf * (ab.position + Vector3(ab.size.x * cx, ab.size.y * cy, ab.size.z * cz)))
		var mn: Vector3 = corners[0]
		var mx: Vector3 = corners[0]
		for p in corners:
			mn = mn.min(p)
			mx = mx.max(p)
		var gab := AABB(mn, mx - mn)
		if gab.intersects(probe_box):
			var mat_name := "?"
			if mi.material_override != null and mi.material_override is StandardMaterial3D:
				var sm := mi.material_override as StandardMaterial3D
				mat_name = str(sm.albedo_color)
			print("L5D2 cand name=", mi.name, " mesh=", mi.mesh.get_class() if mi.mesh != null else "null", " aabb=", gab, " albedo=", mat_name)
			cands.append(mi)
	print("L5D2 candidates=", cands.size())
	var idx := 0
	for mi in cands:
		(mi as MeshInstance3D).visible = false
		await _shot("f_cand%d" % idx)
		(mi as MeshInstance3D).visible = true
		idx += 1
	get_tree().quit()


func _ready() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	_run()
