extends Node3D
# Skills probe: 木鹿大王 casts 妖术 (hex) on a foe standing next to the
# hero — frame the shrunken, disabled enemy. Proves the status engine
# renders, not just the harness numbers. (Hero 11 is password-locked,
# so unlock first — same trap that stalled the harness in Test 48.)

var game: Node
var frames := 0
var foe: Node = null
var hits := 0


func _ready() -> void:
	var packed: PackedScene = load("res://scenes/main.tscn")
	game = packed.instantiate()
	add_child(game)
	game.set("_perf_enabled", false)


func _process(_delta: float) -> void:
	frames += 1
	if frames == 10:
		game.call("try_unlock_hero", "muludawang")
		game.call("select_hero", 11)
		game.set("spawn_queue", [])
		game.call("_spawn_enemy")
		foe = null
		for e in game.get("enemies"):
			if is_instance_valid(e) and bool(e.get("alive")) and String(e.get("archetype")) == "enemy":
				foe = e
				break
		var strat: Node = game.get("strategist")
		foe.set("global_position", strat.global_position + Vector3(5, 0, 0))
		game.set("skill_cooldown", 0.0)
		hits = int(game.call("cast_hero_skill"))
		var dir: Vector3 = game.get("cam_dir")
		game.set("cam_target", foe.global_position)
		game.set("cam_dist", 26.0)
		game.set("cam_dir", dir)
		game.call("_apply_camera")
	elif frames == 14:
		# 早拍：妖术目标站在英雄身边会被箭塔/守将集火，0.5 秒就可能被打死；第 14 帧（约 0.07 秒后）必定还活着。
		_snap("res://shots/skills_hex.png")
		if is_instance_valid(foe):
			print("PROBE_SKILLS hits=", hits, " foe_scale_x=", float(foe.get("scale").x), " disabled=", bool(game.call("_unit_disabled", foe)))
		else:
			print("PROBE_SKILLS foe_freed_before_snap hits=", hits)
		get_tree().quit()


func _snap(path: String) -> void:
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
	print("PROBE_SKILLS saved=", path)
