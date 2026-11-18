extends Node3D
## Identity probe (2026-11-14 round, visual item 三国身份强化):
## photographs the gate plaque, watchtower banner, wall caps, lanterns
## and flag glyphs at close range plus the two standard framings.
## Tag comes from the CLI:
##   xvfb-run godot --path . res://scenes/probe_identity.tscn -- --tag=before
## Run: xvfb-run godot --path . res://scenes/probe_identity.tscn -- --quality=0 --tag=before

var game: Node
var tag: String = "before"

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
	print("PROBE_IDENTITY saved=", path)

func _set_cam(target: Vector3, dist: float) -> void:
	var dir: Vector3 = game.get("cam_dir")
	game.set("cam_target", target)
	game.set("cam_dist", dist)
	game.set("cam_dir", dir)
	game.call("_apply_camera")

func _shot(target: Vector3, dist: float, path: String) -> void:
	_set_cam(target, dist)
	await get_tree().create_timer(0.6).timeout
	await _grab(path)

func _shot_dir(target: Vector3, dist: float, dir: Vector3, path: String) -> void:
	game.set("cam_target", target)
	game.set("cam_dist", dist)
	game.set("cam_dir", dir)
	game.call("_apply_camera")
	await get_tree().create_timer(0.6).timeout
	await _grab(path)

func _run() -> void:
	await get_tree().create_timer(2.5).timeout
	game.call("select_hero", 0) # 赵统
	await get_tree().create_timer(1.0).timeout
	game.call("reset_camera_view")
	await get_tree().create_timer(0.6).timeout
	await _grab("res://shots/identity_%s_a.png" % tag)
	await _shot(Vector3(0, 0, 0), 150.0, "res://shots/identity_%s_b.png" % tag)
	await _shot(Vector3(-56, 0, 0), 30.0, "res://shots/identity_%s_gate.png" % tag)
	await _shot(Vector3(-50, 0, -13), 18.0, "res://shots/identity_%s_tower.png" % tag)
	await _shot(Vector3(-71, 0, -15), 12.0, "res://shots/identity_%s_wall.png" % tag)
	await _shot(Vector3(-53.5, 0, 7.5), 13.0, "res://shots/identity_%s_flag.png" % tag)
	# Rev 4 evidence: 45-degree oblique flag close-up, unobstructed
	# oblique eave-corner view, full-lantern close-up (nothing clipped
	# by the frame top) — Rev 3 lost two points on missing evidence.
	await _shot_dir(Vector3(2.0, 3.2, -8.0), 9.0, Vector3(0.64, 0.30, 0.71), "res://shots/identity_%s_flag45.png" % tag)
	await _shot_dir(Vector3(-58.85, 6.3, 6.05), 13.0, Vector3(-0.45, 0.32, 0.83), "res://shots/identity_%s_eave.png" % tag)
	await _shot_dir(Vector3(-54.7, 4.35, -1.8), 4.5, Vector3(0.85, 0.12, -0.35), "res://shots/identity_%s_lantern.png" % tag)
	get_tree().quit()
