extends Node3D
## Rev 4 crystal-banding phase study: the seal crystal slowly turns,
## and the striped facet only appears at some phases — so shoot f
## three times across ~6 s and judge the worst phase. Switches:
## --core-shadow-off, --corebias=<bias>:<normal_bias>, --sun=k:v.
## Run: xvfb-run godot --path . res://scenes/probe_light4phase.tscn -- --quality=0 --tag=ph_base

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
	print("PROBE_PHASE saved=", path)


func _set_cam(target: Vector3, dist: float) -> void:
	var dir: Vector3 = game.get("cam_dir")
	game.set("cam_target", target)
	game.set("cam_dist", dist)
	game.set("cam_dir", dir)
	game.call("_apply_camera")


func _run() -> void:
	await get_tree().create_timer(2.5).timeout
	var cl = game.get("crystal_light")
	print("PHASE core bias=", cl.get("shadow_bias"), " normal_bias=", cl.get("shadow_normal_bias"),
		" range=", cl.get("omni_range"), " energy=", cl.get("light_energy"))
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--sun="):
			var kv = arg.trim_prefix("--sun=").split(":")
			game.get("sun_light").set(kv[0], float(kv[1]))
		if arg == "--core-shadow-off":
			cl.shadow_enabled = false
		if arg == "--sun-shadow-off":
			game.get("sun_light").shadow_enabled = false
		if arg == "--glow-off":
			game.get("env_ref").glow_enabled = false
		if arg == "--deband":
			get_viewport().use_debanding = true
		if arg.begins_with("--coreatt="):
			cl.omni_attenuation = float(arg.trim_prefix("--coreatt="))
		if arg.begins_with("--corebias="):
			var kv = arg.trim_prefix("--corebias=").split(":")
			cl.set("shadow_bias", float(kv[0]))
			cl.set("shadow_normal_bias", float(kv[1]))
	game.call("select_hero", 0)
	await get_tree().create_timer(1.0).timeout
	_set_cam(Vector3(-70, 0, 0), 19.0)
	await get_tree().create_timer(0.6).timeout
	await _grab("res://shots/light_%s_f.png" % tag)
	await get_tree().create_timer(3.0).timeout
	await _grab("res://shots/light_%s_f2.png" % tag)
	await get_tree().create_timer(3.0).timeout
	await _grab("res://shots/light_%s_f3.png" % tag)
	get_tree().quit()
