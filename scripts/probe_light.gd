extends Node3D
## Light/shadow captures (2026-11-14 round, visual item 光影丰富度；
## Rev 3 2026-11-15 adds --tag and close-ups for contact-shadow scale):
##  a default camera, b pulled back 150, c base/gate mid shot,
##  d hero feet close-up, e gate tower foot close-up,
##  f seal-core base / cliff foot close-up, g north rift mouth close-up.
## Run: xvfb-run godot --path . res://scenes/probe_light.tscn -- --quality=0 --tag=rev3before

var game: Node
var tag: String = "x"
var noplinth: bool = false


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--tag="):
			tag = a.trim_prefix("--tag=")
	game = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	_run()


func _grab(path: String) -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
	print("PROBE_LIGHT saved=", path)


func _set_cam(target: Vector3, dist: float) -> void:
	var dir: Vector3 = game.get("cam_dir")
	game.set("cam_target", target)
	game.set("cam_dist", dist)
	game.set("cam_dir", dir)
	game.call("_apply_camera")


# Rev 4 diagnostics: hide only team/selection rings; missing nodes are optional.
func _set_plinth_rings_visible(value: bool) -> void:
	for unit_key in ["strategist", "general"]:
		var unit = game.get(unit_key)
		if is_instance_valid(unit):
			var ring = unit.find_child("TeamRing", true, false)
			if ring != null:
				ring.visible = value
	var selection = game.find_child("SelectionRing", true, false)
	if selection != null:
		selection.visible = value


func _run() -> void:
	await get_tree().create_timer(2.5).timeout
	# Rev 4 diagnostics: runtime-only single-variable controls, no production defaults.
	for arg in OS.get_cmdline_user_args():
		if arg == "--noplinth":
			noplinth = true
		if arg.begins_with("--sun="):
			var kv = arg.trim_prefix("--sun=").split(":")
			game.get("sun_light").set(kv[0], float(kv[1]))
		if arg == "--core-shadow-off":
			game.get("crystal_light").shadow_enabled = false
		if arg == "--glow-off":
			game.get("env_ref").glow_enabled = false
		if arg == "--core-contact-off":
			var core = game.find_child("SealCore", true, false)
			if core != null:
				core.get_node("ContactShadow").visible = false
		if arg == "--lantern-off":
			# 全局色调 Rev 4: gate-lantern on/off comparison frames
			# (runtime-only diagnostic; production defaults untouched).
			for lname in ["GateLanternL", "GateLanternR"]:
				var ln = game.find_child(lname, true, false)
				if ln != null:
					ln.set("light_energy", 0.0)
		if arg.begins_with("--hide="):
			for node in game.find_children(arg.trim_prefix("--hide="), "", true, false):
				if node is VisualInstance3D: node.visible = false
	game.call("select_hero", 0) # 赵统
	await get_tree().create_timer(1.0).timeout
	game.call("reset_camera_view")
	await get_tree().create_timer(0.6).timeout
	await _grab("res://shots/light_%s_a.png" % tag)
	_set_cam(Vector3(0, 0, 0), 150.0)
	await get_tree().create_timer(0.6).timeout
	await _grab("res://shots/light_%s_b.png" % tag)
	_set_cam(Vector3(-58, 0, 0), 58.0)
	await get_tree().create_timer(0.6).timeout
	await _grab("res://shots/light_%s_c.png" % tag)
	var hero = game.get("strategist")
	if is_instance_valid(hero):
		_set_cam((hero as Node3D).global_position, 11.0)
		await get_tree().create_timer(0.6).timeout
		await _grab("res://shots/light_%s_d.png" % tag)
		if noplinth:
			_set_plinth_rings_visible(false)
			await _grab("res://shots/light_%s_d2.png" % tag)
	_set_cam(Vector3(-59, 0, -13), 14.0)
	await get_tree().create_timer(0.6).timeout
	await _grab("res://shots/light_%s_e.png" % tag)
	_set_cam(Vector3(-70, 0, 0), 19.0)
	await get_tree().create_timer(0.6).timeout
	await _grab("res://shots/light_%s_f.png" % tag)
	_set_cam(Vector3(75, 0, -26), 17.0)
	await get_tree().create_timer(0.6).timeout
	await _grab("res://shots/light_%s_g.png" % tag)
	var guard = game.get("general")
	if is_instance_valid(guard):
		_set_cam((guard as Node3D).global_position, 11.0)
		await get_tree().create_timer(0.6).timeout
		if noplinth:
			_set_plinth_rings_visible(true)
		await _grab("res://shots/light_%s_h.png" % tag)
		if noplinth:
			_set_plinth_rings_visible(false)
			await _grab("res://shots/light_%s_h2.png" % tag)
	get_tree().quit()
