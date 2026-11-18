extends Node3D
# Tower probe: build all six tower types on pads 0..5, upgrade pad 0
# to Lv3, frame the plaza pad row so the six distinct tower heads and
# the gold level pips are visible. Proves the tower system renders.

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
		game.set("gold", 5000)
		var types: Array = ["arrow", "frost", "thunder", "stone", "flame", "crossbow"]
		for i in range(6):
			var ok: bool = game.call("build_tower", i, types[i])
			print("PROBE_TOWERS build pad=", i, " type=", types[i], " ok=", ok)
		game.call("upgrade_tower", 0)
		game.call("upgrade_tower", 0)
		var pads: Array = game.get("pads")
		var t0 = pads[0].get("tower")
		if t0 != null:
			print("PROBE_TOWERS pad0 level=", int(t0.get("level", -1)), " dmg=", float(t0.get("dmg", -1.0)))
		# Frame all six pads: they span x -20..34, z -16..16 — pull wide.
		var dir: Vector3 = game.get("cam_dir")
		game.set("cam_target", Vector3(7, 0, 0))
		game.set("cam_dist", 58.0)
		game.set("cam_dir", dir)
		game.call("_apply_camera")
	elif frames == 16:
		_snap("res://shots/towers_six.png")
		# Second frame: the western pads 4/5 (stone/flame row) up closer.
		game.set("cam_target", Vector3(-14, 0, 0))
		game.set("cam_dist", 34.0)
		game.call("_apply_camera")
	elif frames == 22:
		_snap("res://shots/towers_six_b.png")
		get_tree().quit()


func _snap(path: String) -> void:
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
	print("PROBE_TOWERS saved=", path)
