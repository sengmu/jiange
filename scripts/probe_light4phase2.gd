extends Node3D
## Rev 4 crystal-banding DETERMINISTIC phase study: freeze main's
## _process (stops crystal spin + light/emission pulse), then step
## CrystalGroup.rotation.y through fixed angles and shoot f at each.
## Switch combos come from --combo=<name>; angles from --steps=<n>.
## Run: xvfb-run godot --path . res://scenes/probe_light4phase2.tscn -- --quality=0 --tag=px_base --combo=base

var game: Node
var tag: String = "x"
var combo: String = "base"
var steps: int = 8


func _grab(path: String) -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
	print("PROBE_PX saved=", path)


func _set_cam(target: Vector3, dist: float) -> void:
	var dir: Vector3 = game.get("cam_dir")
	game.set("cam_target", target)
	game.set("cam_dist", dist)
	game.set("cam_dir", dir)
	game.call("_apply_camera")


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--tag="):
			tag = a.trim_prefix("--tag=")
		if a.begins_with("--combo="):
			combo = a.trim_prefix("--combo=")
		if a.begins_with("--steps="):
			steps = int(a.trim_prefix("--steps="))
	game = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	_run()


func _run() -> void:
	await get_tree().create_timer(2.5).timeout
	game.call("select_hero", 0)
	await get_tree().create_timer(1.0).timeout
	game.set_process(false)
	var cl = game.get("crystal_light")
	match combo:
		"coreoff":
			cl.shadow_enabled = false
		"cb_a":
			cl.set("shadow_bias", 0.05)
			cl.set("shadow_normal_bias", 1.0)
		"deband":
			get_viewport().use_debanding = true
		"coreoff_deband":
			cl.shadow_enabled = false
			get_viewport().use_debanding = true
		"cba_deband":
			cl.set("shadow_bias", 0.05)
			cl.set("shadow_normal_bias", 1.0)
			get_viewport().use_debanding = true
		"glowoff":
			game.get("env_ref").glow_enabled = false
	var group = game.get("crystal_group")
	_set_cam(Vector3(-70, 0, 0), 19.0)
	await get_tree().create_timer(0.6).timeout
	for k in range(steps):
		if group != null:
			group.rotation.y = TAU * float(k) / float(steps)
		await get_tree().create_timer(0.35).timeout
		await _grab("res://shots/light_%s_a%d.png" % [tag, k])
	get_tree().quit()
