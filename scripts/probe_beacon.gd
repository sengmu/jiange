extends Node3D
## One-off: isolated selection-beacon render check on open ground.
var game: Node3D
func _ready() -> void:
	await get_tree().process_frame
	var ps: PackedScene = load("res://scenes/main.tscn")
	game = ps.instantiate()
	add_child(game)
	await get_tree().process_frame
	game.set("cam_target", Vector3(30, 0, 0))
	game.set("cam_dist", 16.0)
	game.set("cam_dir", Vector3(0, 0.81, 0.59).normalized())
	game.call("_apply_camera")
	game.call("select_hero", 0)
	var hero: Node = game.get("strategist")
	hero.set("global_position", Vector3(30, 0, 0))
	var ring: Node3D = game.get("selection_ring")
	print("PROBE_BEACON ring=", ring)
	for ch in ring.get_children():
		var mi := ch as MeshInstance3D
		if mi:
			var m := mi.material_override as StandardMaterial3D
			if m:
				print("PROBE_BEACON child=", mi.name, " albedo=", m.albedo_color, " emission_on=", m.emission_enabled, " emission=", m.emission, " energy=", m.emission_energy_multiplier if m.emission_enabled else -1.0)
			else:
				print("PROBE_BEACON child=", mi.name, " NO_MATERIAL_OVERRIDE")
		else:
			print("PROBE_BEACON child=", ch.name, " type=", ch.get_class())
	await get_tree().create_timer(1.2).timeout
	hero.set("global_position", Vector3(30, 0, 0))
	await get_tree().create_timer(0.3).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://shots/beacon_iso.png")
	print("PROBE_BEACON saved")
	get_tree().quit()
