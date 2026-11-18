extends Node3D
## Rev 4 lighting diagnostics: f (seal core / cliff foot) + h (guard
## feet) only, with the same runtime switches as probe_light.gd
## (--sun=prop:value, --core-shadow-off, --glow-off,
## --core-contact-off, --hide=pattern) plus a printout of the sun's
## shadow parameters so trial logs record the actual baseline.
## Run: xvfb-run godot --path . res://scenes/probe_light4diag.tscn -- --quality=0 --tag=band_t0

var game: Node
var tag: String = "x"


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
	print("PROBE_DIAG saved=", path)


func _set_cam(target: Vector3, dist: float) -> void:
	var dir: Vector3 = game.get("cam_dir")
	game.set("cam_target", target)
	game.set("cam_dist", dist)
	game.set("cam_dir", dir)
	game.call("_apply_camera")


func _run() -> void:
	await get_tree().create_timer(2.5).timeout
	var sun = game.get("sun_light")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--sun="):
			var kv = arg.trim_prefix("--sun=").split(":")
			sun.set(kv[0], float(kv[1]))
		if arg == "--core-shadow-off":
			game.get("crystal_light").shadow_enabled = false
		if arg == "--glow-off":
			game.get("env_ref").glow_enabled = false
		if arg == "--core-contact-off":
			var core = game.find_child("SealCore", true, false)
			if core != null:
				core.get_node("ContactShadow").visible = false
		if arg.begins_with("--hide="):
			for node in game.find_children(arg.trim_prefix("--hide="), "", true, false):
				if node is VisualInstance3D: node.visible = false
	print("DIAG sun bias=", sun.get("shadow_bias"), " normal_bias=", sun.get("shadow_normal_bias"),
		" blur=", sun.get("shadow_blur"), " opacity=", sun.get("shadow_opacity"),
		" mode=", sun.get("directional_shadow_mode"), " maxdist=", sun.get("directional_shadow_max_distance"),
		" split1=", sun.get("directional_shadow_split_1"), " split2=", sun.get("directional_shadow_split_2"))
	game.call("select_hero", 0)
	await get_tree().create_timer(1.0).timeout
	_set_cam(Vector3(-70, 0, 0), 19.0)
	await get_tree().create_timer(0.6).timeout
	await _grab("res://shots/light_%s_f.png" % tag)
	var guard = game.get("general")
	if is_instance_valid(guard):
		_set_cam((guard as Node3D).global_position, 11.0)
		await get_tree().create_timer(0.6).timeout
		await _grab("res://shots/light_%s_h.png" % tag)
	get_tree().quit()
