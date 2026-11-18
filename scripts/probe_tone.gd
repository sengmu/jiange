extends Node3D
## Global-tone captures (2026-11-14 round, visual item 全局色调):
## instances the real game scene and photographs three framings at the
## same battle moment, before/after the dusk-grade parameter change.
##  1 shots/tone_a.png — default classic camera, wave-1 start (赵统).
##  2 shots/tone_b.png — whole map pulled back to 150.
##  3 shots/tone_c.png — base/gate mid shot: seal core, gatehouse,
##     road, shadow detail (target -58,0,0 dist 58).
## Run: xvfb-run godot --path . res://scenes/probe_tone.tscn -- --quality=0
## (manual tier 0 locks shadows+glow on; auto step-down disabled.)

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
	print("PROBE_TONE saved=", path)


func _set_cam(target: Vector3, dist: float) -> void:
	var dir: Vector3 = game.get("cam_dir")
	game.set("cam_target", target)
	game.set("cam_dist", dist)
	game.set("cam_dir", dir)
	game.call("_apply_camera")


func _run() -> void:
	await get_tree().create_timer(2.5).timeout
	game.call("select_hero", 0) # 赵统
	await get_tree().create_timer(1.0).timeout
	game.call("reset_camera_view")
	await get_tree().create_timer(0.6).timeout
	await _grab("res://shots/tone_%s_a.png" % tag)
	_set_cam(Vector3(0, 0, 0), 150.0)
	await get_tree().create_timer(0.6).timeout
	await _grab("res://shots/tone_%s_b.png" % tag)
	_set_cam(Vector3(-58, 0, 0), 58.0)
	await get_tree().create_timer(0.6).timeout
	await _grab("res://shots/tone_%s_c.png" % tag)
	# 全局色调 Rev 4: watchtower close-up for stone split-face sampling
	# (same framing probe_broken used for broken_tower).
	_set_cam(Vector3(-50, 0, -13), 26.0)
	await get_tree().create_timer(0.6).timeout
	await _grab("res://shots/tone_%s_tower.png" % tag)
	get_tree().quit()
