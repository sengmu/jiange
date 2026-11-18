extends Node3D
## Residual-piece probe (2026-11-14 round, visual item 程序化残件替换):
## photographs the three residual pieces at close range plus the two
## standard framings, before/after the rebuild. Tag comes from the CLI:
##   xvfb-run godot --path . res://scenes/probe_residual.tscn -- --tag=before
## Run: xvfb-run godot --path . res://scenes/probe_residual.tscn -- --quality=0 --tag=before

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
	print("PROBE_RESIDUAL saved=", path)

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

var default_dir: Vector3 = Vector3.ZERO

func _shot_dir(target: Vector3, dist: float, dir: Vector3, path: String) -> void:
	game.set("cam_target", target)
	game.set("cam_dist", dist)
	game.set("cam_dir", dir)
	game.call("_apply_camera")
	await get_tree().create_timer(0.6).timeout
	await _grab(path)
	game.set("cam_dir", default_dir)

func _run() -> void:
	await get_tree().create_timer(2.5).timeout
	game.call("select_hero", 0) # 赵统
	await get_tree().create_timer(1.0).timeout
	game.call("reset_camera_view")
	await get_tree().create_timer(0.6).timeout
	default_dir = game.get("cam_dir")
	await _grab("res://shots/residual_%s_a.png" % tag)
	await _shot(Vector3(0, 0, 0), 150.0, "res://shots/residual_%s_b.png" % tag)
	await _shot(Vector3(-56, 0, 0), 30.0, "res://shots/residual_%s_gate.png" % tag)
	# Rev 4: lintel front evidence — level view from the field (east)
	# straight at the gate beam/bracket stack, plus a far rift shot
	# proving the purple mouth silhouette survives at distance.
	await _shot_dir(Vector3(-56, 5.2, 0), 15.0, Vector3(1, 0.22, 0).normalized(), "res://shots/residual_%s_gatefront.png" % tag)
	await _shot(Vector3(34, 0, -13), 24.0, "res://shots/residual_%s_pad.png" % tag)
	await _shot(Vector3(77, 0, -26), 26.0, "res://shots/residual_%s_rift_n.png" % tag)
	await _shot(Vector3(77, 2.0, -26), 55.0, "res://shots/residual_%s_riftfar.png" % tag)
	await _shot(Vector3(77, 0, 26), 26.0, "res://shots/residual_%s_rift_s.png" % tag)
	# Composition round: wing + foreground evidence framings.
	await _shot(Vector3(-70, 2, 14), 46.0, "res://shots/residual_%s_wingw.png" % tag)
	await _shot(Vector3(20, 2, -2), 52.0, "res://shots/residual_%s_winge.png" % tag)
	await _shot(Vector3(-12, 2, 24), 44.0, "res://shots/residual_%s_front.png" % tag)
	get_tree().quit()
