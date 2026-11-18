extends Node3D
# Boss skills probe: 董卓 (wave 9) casts 天神下凡 next to the hero —
# frame the grown boss with his skill callout. Proves the boss skill
# engine renders, not just the harness numbers.

var game: Node
var frames := 0
var boss: Node = null
var scale0 := 0.0


func _ready() -> void:
	var packed: PackedScene = load("res://scenes/main.tscn")
	game = packed.instantiate()
	add_child(game)
	game.set("_perf_enabled", false)


func _process(_delta: float) -> void:
	frames += 1
	if frames == 10:
		game.call("select_hero", 0)
		game.set("spawn_queue", [])
		game.set("current_boss_list", game.call("bosses_for_wave", 9))
		game.set("boss_spawn_index", 0)
		boss = game.call("_spawn_enemy_of_type", "boss")
		var strat: Node = game.get("strategist")
		strat.set("global_position", Vector3(30, 0, 0))
		boss.set("global_position", Vector3(34, 0, 2))
		scale0 = float(boss.get("scale").x)
		game.call("cast_boss_skill", boss, "天神下凡", null)
		var dir: Vector3 = game.get("cam_dir")
		game.set("cam_target", boss.global_position)
		game.set("cam_dist", 26.0)
		game.set("cam_dir", dir)
		game.call("_apply_camera")
	elif frames == 14:
		_snap("res://shots/boss_transform.png")
		if is_instance_valid(boss):
			print("PROBE_BOSS scale_x=", float(boss.get("scale").x), " scale0=", scale0)
		else:
			print("PROBE_BOSS boss_freed_before_snap")
		get_tree().quit()


func _snap(path: String) -> void:
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
	print("PROBE_BOSS saved=", path)
