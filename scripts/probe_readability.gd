extends Node3D
## Readability probe (2026-11-14 round, visual item 单位可读性):
## stages a mid-field combat cluster (hero + guard vs infantry/archers/
## beast/boss at mixed HP) and photographs it at the classic framing,
## max zoom-out, and two close ranges so team colours, HP bars, the
## selection ring and hero-vs-minion size difference can be judged.
## Tag comes from the CLI:
##   xvfb-run godot --path . res://scenes/probe_readability.tscn -- --quality=0 --tag=before

var game: Node
var tag: String = "before"
var pins: Dictionary = {}

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
	print("PROBE_READABILITY saved=", path)

func _set_cam(target: Vector3, dist: float) -> void:
	var dir: Vector3 = game.get("cam_dir")
	game.set("cam_target", target)
	game.set("cam_dist", dist)
	game.set("cam_dir", dir)
	game.call("_apply_camera")

func _pin_all() -> void:
	for u in pins:
		if is_instance_valid(u):
			(u as Node3D).set("global_position", pins[u])
	game.set("selected", true)

func _shot(target: Vector3, dist: float, path: String) -> void:
	_set_cam(target, dist)
	await get_tree().create_timer(0.5).timeout
	_pin_all()
	await _grab(path)

func _drain_queue() -> void:
	var guard := 0
	while not (game.get("spawn_queue") as Array).is_empty() and guard < 160:
		game.call("_spawn_from_queue")
		guard += 1

func _run() -> void:
	await get_tree().create_timer(2.5).timeout
	game.call("select_hero", 0) # 赵统
	await get_tree().create_timer(0.5).timeout
	game.call("_start_wave", 6)
	await get_tree().create_timer(0.5).timeout
	_drain_queue()
	await get_tree().create_timer(0.5).timeout
	# --- Stage the combat cluster mid-field (south lane, x ~ -30) ---
	var hero: Node3D = game.get("strategist")
	var general: Node3D = game.get("general")
	if hero != null:
		hero.set("global_position", Vector3(-33, 0, 4))
	if general != null:
		general.set("global_position", Vector3(-35.5, 0, 8.5))
	var inf_spots := [Vector3(-27, 0, 2), Vector3(-25.5, 0, 5.5), Vector3(-28.5, 0, 7.5), Vector3(-24, 0, 3.5)]
	var inf_hp := [1.0, 0.55, 0.22, 0.8]
	var arch_spots := [Vector3(-22.5, 0, 0), Vector3(-22.5, 0, 9.5)]
	var arch_hp := [0.6, 1.0]
	var ii := 0
	var ai := 0
	var boss_done := false
	var beast_done := false
	for e in game.get("enemies"):
		if not is_instance_valid(e) or not bool(e.get("alive")):
			continue
		var arch := String(e.get("archetype"))
		if arch == "enemy" and ii < inf_spots.size():
			e.set("global_position", inf_spots[ii])
			e.set("hp", float(e.get("max_hp")) * inf_hp[ii])
			ii += 1
		elif arch == "archer" and ai < arch_spots.size():
			e.set("global_position", arch_spots[ai])
			e.set("hp", float(e.get("max_hp")) * arch_hp[ai])
			ai += 1
		elif arch == "boss" and not boss_done:
			e.set("global_position", Vector3(-18.5, 0, 12))
			e.set("hp", float(e.get("max_hp")) * 0.45)
			boss_done = true
		elif arch == "beast" and not beast_done:
			e.set("global_position", Vector3(-19, 0, 3.5))
			e.set("hp", float(e.get("max_hp")) * 0.7)
			beast_done = true
	game.set("selected", true)
	# Pin the staged cluster: post-calibration combat is lethal and
	# lane AI marches the extras off-frame within seconds (the Rev 3
	# before-run lost the hero and the boss before the e shot).
	pins.clear()
	if hero != null:
		hero.set("max_hp", 20000.0)
		hero.set("hp", 20000.0)
		pins[hero] = hero.get("global_position")
	if general != null:
		pins[general] = general.get("global_position")
	for e in game.get("enemies"):
		if is_instance_valid(e) and bool(e.get("alive")):
			pins[e] = e.get("global_position")
	await get_tree().create_timer(0.8).timeout
	# --- Report the measured facts the item is judged on ---
	if hero != null:
		var hm: Node = hero.get_node_or_null("VisualRoot/PackModel")
		var hs: Vector3 = (hm as Node3D).scale if hm != null else Vector3.ZERO
		print("PROBE_READABILITY hero_scale=", hs)
	for e in game.get("enemies"):
		if is_instance_valid(e) and bool(e.get("alive")):
			var em: Node = e.get_node_or_null("VisualRoot/PackModel")
			var es: Vector3 = (em as Node3D).scale if em != null else Vector3.ZERO
			print("PROBE_READABILITY unit=", String(e.get("archetype")), " scale=", es, " bar_w=", float(e.get("hp_bar_width")), " bar_h=", float(e.get("hp_bar_height")))
			break
	game.call("reset_camera_view")
	await get_tree().create_timer(0.6).timeout
	_pin_all()
	await _grab("res://shots/readability_%s_a.png" % tag)
	await _shot(Vector3(0, 0, 0), 150.0, "res://shots/readability_%s_b.png" % tag)
	await _shot(Vector3(-27, 0, 5), 22.0, "res://shots/readability_%s_c.png" % tag)
	await _shot(Vector3(-31, 0, 5), 13.0, "res://shots/readability_%s_d.png" % tag)
	await _shot(Vector3(-18.5, 0, 10), 20.0, "res://shots/readability_%s_e.png" % tag)
	# Rev 4: newcity sign framing (sign + leader line + town in one frame).
	await _shot(Vector3(-64, 0, -24), 46.0, "res://shots/readability_%s_f.png" % tag)
	get_tree().quit()
