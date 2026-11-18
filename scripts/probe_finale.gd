extends Node3D
# Finale probe: wave 20, spawn the three Simas, teleport 司马懿 into
# 上方谷 so the fire trap springs, then frame him in the flame ring.

var game: Node
var frames := 0


func _ready() -> void:
	var packed: PackedScene = load("res://scenes/main.tscn")
	game = packed.instantiate()
	add_child(game)
	game.set("_perf_enabled", false)


func _process(_delta: float) -> void:
	frames += 1
	if frames == 10:
		game.call("select_hero", 0)
		game.call("_start_wave", 20)
		game.set("spawn_queue", [])
		game.set("current_boss_list", game.call("bosses_for_wave", 20))
		game.set("boss_spawn_index", 0)
		var yi: Node = null
		for i in range(3):
			var b = game.call("_spawn_enemy_of_type", "boss")
			if b.display_name == "司马懿":
				yi = b
		yi.global_position = Vector3(85, 0, -37)
		game.call("_update_finale", 0.1)
		var dir: Vector3 = game.get("cam_dir")
		game.set("cam_target", Vector3(85, 0, -37))
		game.set("cam_dist", 30.0)
		game.set("cam_dir", dir)
		game.call("_apply_camera")
	elif frames == 40:
		_snap("res://shots/finale_trap.png")
		print("PROBE_FINALE trapped=", game.get("yi_trapped"), " flames=", (game.get("finale_flames") as Array).size())
		get_tree().quit()


func _snap(path: String) -> void:
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
	print("PROBE_FINALE saved=", path)
