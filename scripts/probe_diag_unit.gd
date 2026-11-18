extends Node3D
## Diagnostic 8: where did the hat vertices land for a walking enemy?
var game: Node

func _ready() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	_run()

func _run() -> void:
	await get_tree().create_timer(2.0).timeout
	game.call("select_hero", 0)
	game.call("_start_wave", 1)
	await get_tree().create_timer(2.5).timeout
	var units_root: Node = game.get("units_root")
	for u in units_root.get_children():
		if String(u.get("archetype")) != "enemy":
			continue
		var model: Node = u.get_node_or_null("VisualRoot/PackModel")
		for child in model.get_children():
			if child is MeshInstance3D:
				var mi := child as MeshInstance3D
				var info := "DIAG8 " + mi.name + " skin=" + str(mi.skin != null)
				for si in mi.mesh.get_surface_count():
					var arrs := mi.mesh.surface_get_arrays(si)
					var bones: Array = arrs[Mesh.ARRAY_BONES] if arrs.size() > Mesh.ARRAY_BONES else []
					var distinct: Dictionary = {}
					for b in bones:
						distinct[int(b)] = true
					info += " | s%d verts=%d bones=%s" % [si, (arrs[Mesh.ARRAY_VERTEX] as Array).size(), str(distinct.keys())]
				print(info)
		break
	get_tree().quit()
