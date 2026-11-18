extends Node3D
# Assassin probe: (a) the assassin revealed while striking 孔明 — close-up
# on the command tent, shot from the north-west so the market/casino
# (south of 孔明） do not occlude the pair; (b) a second assassin mid-map,
# visible only because the hero holds 和氏璧 (detection on).

var game: Node
var frames := 0
var a1: Node
var a2: Node
var km: Node


func _ready() -> void:
	var packed: PackedScene = load("res://scenes/main.tscn")
	game = packed.instantiate()
	add_child(game)
	game.set("_perf_enabled", false)


func _process(_delta: float) -> void:
	frames += 1
	if frames == 10:
		game.call("select_hero", 0)
		game.set("gold", 5000)
		game.set("current_wave", 6)
		game.set("spawn_queue", [])
		game.set("game_state", "battle")
		km = game.get("kongming_unit")
		a1 = game.call("spawn_assassin")
		# Stage the pair on open grass for the close-up: 孔明's real home
		# (-71.5,-15.5) sits inside the market row, so any close camera
		# there is occluded by stall roofs/signs. Mechanics (positions,
		# strike, HP) are already covered by the harness + the printed log.
		km.set("global_position", Vector3(0, 0, -10))
		a1.set("global_position", Vector3(2.5, 0, -10))
		a1.set("attack_timer", 0.0)
		game.call("_update_assassin", a1)
		print("PROBE_ASSASSIN a1 visible=", bool(a1.get("visible")), " km_hp=", float(km.get("hp")))
		game.set("cam_target", Vector3(1.0, 0, -10.0))
		game.set("cam_dist", 16.0)
		game.set("cam_dir", Vector3(0, 0.8192, 0.5736).normalized())
		game.call("_apply_camera")
	elif frames == 16:
		_snap("res://shots/assassin_kongming.png")
		# Detection on: give the hero 和氏璧， then a second assassin
		# mid-map — it must render while the first keeps striking.
		game.call("give_hero_item", {"name": "和氏璧", "kind": "token", "desc": "持有：反隐（看破隐形单位）"})
		a2 = game.call("spawn_assassin")
		a2.set("global_position", Vector3(0, 0, -20))
		var dir2: Vector3 = game.get("cam_dir")
		game.set("cam_target", Vector3(0, 0, -20))
		game.set("cam_dist", 26.0)
		game.set("cam_dir", dir2)
		game.call("_apply_camera")
	elif frames == 22:
		print("PROBE_ASSASSIN detection=", bool(game.call("hero_has_detection")), " a2 visible=", bool(a2.get("visible")), " a2 pos=", a2.global_position)
		_snap("res://shots/assassin_detected.png")
		get_tree().quit()


func _snap(path: String) -> void:
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
	print("PROBE_ASSASSIN saved=", path)
