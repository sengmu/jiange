extends SceneTree
## Asset probe: union AABB (bind pose) + animation clip info for pack assets.
## Run: godot --headless --path . --script res://Test/probe_assets.gd

const ITEMS: Array = [
	"res://assets/kaykit_char/Knight.glb",
	"res://assets/kaykit_char/Barbarian.glb",
	"res://assets/kaykit_char/Mage.glb",
	"res://assets/kaykit_char/Rogue_Hooded.glb",
	"res://assets/kaykit_weapons/sword_1handed.gltf",
	"res://assets/kaykit_weapons/axe_1handed.gltf",
	"res://assets/kaykit_weapons/staff.gltf",
	"res://assets/kaykit_weapons/crossbow_2handed.gltf",
	"res://assets/kaykit_weapons/quiver.gltf",
	"res://assets/kaykit_weapons/shield_square_color.gltf",
	"res://assets/kaykit_weapons/shield_round_barbarian.gltf",
	"res://assets/kenney_castle/tower-square-base.glb",
	"res://assets/kenney_castle/tower-square-mid.glb",
	"res://assets/kenney_castle/tower-square-top.glb",
	"res://assets/kenney_castle/tower-square-top-roof.glb",
	"res://assets/kenney_castle/tower-square.glb",
	"res://assets/kenney_castle/flag-banner-long.glb",
	"res://assets/kenney_castle/flag.glb",
	"res://assets/kenney_castle/tree-large.glb",
	"res://assets/kenney_castle/tree-small.glb",
	"res://assets/kenney_castle/rocks-large.glb",
	"res://assets/kenney_castle/rocks-small.glb",
	"res://assets/kenney_castle/siege-ram.glb",
	"res://assets/kenney_castle/siege-ballista.glb",
	"res://assets/kenney_td/detail-crystal.glb",
	"res://assets/kenney_td/detail-crystal-large.glb",
	"res://assets/kaykit_hex/buildings/neutral/wall_straight.gltf",
	"res://assets/kaykit_hex/buildings/neutral/wall_straight_gate.gltf",
	"res://assets/kaykit_hex/buildings/red/building_tower_A_red.gltf",
	"res://assets/kaykit_hex/decoration/props/flag_red.gltf",
	"res://assets/kaykit_hex/decoration/props/tent.gltf",
	"res://assets/kaykit_hex/decoration/props/crate_A_big.gltf",
	"res://assets/kaykit_hex/decoration/props/crate_A_small.gltf",
	"res://assets/kaykit_hex/decoration/props/barrel.gltf",
	"res://assets/kaykit_hex/decoration/props/sack.gltf",
	"res://assets/kaykit_hex/decoration/nature/tree_single_A.gltf",
	"res://assets/kaykit_hex/decoration/nature/trees_A_large.gltf",
	"res://assets/kaykit_hex/decoration/nature/rock_single_A.gltf",
	"res://assets/kaykit_tiles/base/hex_grass.gltf",
	"res://assets/kaykit_tiles/roads/hex_road_A.gltf",
]

const CLIPS_OF_INTEREST: Array = [
	"Idle", "Walking_A", "Running_A", "1H_Melee_Attack_Chop", "2H_Ranged_Shoot",
	"Spellcast_Shoot", "Hit_A", "Death_A", "Death_B",
]


func _union_aabb(n: Node, root_xf: Transform3D, acc: Dictionary) -> void:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		if mi.mesh != null:
			var local_aabb: AABB = mi.get_aabb()
			var xf: Transform3D = mi.global_transform * root_xf
			var world_aabb: AABB = xf * local_aabb
			if not acc.has("aabb"):
				acc["aabb"] = world_aabb
			else:
				acc["aabb"] = (acc["aabb"] as AABB).merge(world_aabb)
	for c in n.get_children():
		_union_aabb(c, root_xf, acc)


func _find_anim(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n
	for c in n.get_children():
		var r := _find_anim(c)
		if r != null:
			return r
	return null


func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame
	for path in ITEMS:
		var ps: PackedScene = load(path)
		if ps == null:
			print("PROBE MISSING ", path)
			continue
		var inst: Node3D = ps.instantiate()
		root.add_child(inst)
		await process_frame
		var acc: Dictionary = {}
		_union_aabb(inst, Transform3D.IDENTITY, acc)
		if acc.has("aabb"):
			var a: AABB = acc["aabb"]
			print("PROBE %s size=(%.2f, %.2f, %.2f) min=(%.2f, %.2f, %.2f) max=(%.2f, %.2f, %.2f)" % [
				path.get_file(), a.size.x, a.size.y, a.size.z,
				a.position.x, a.position.y, a.position.z,
				a.end.x, a.end.y, a.end.z])
		else:
			print("PROBE %s NO_MESH" % path.get_file())
		var ap := _find_anim(inst)
		if ap != null:
			var parts: Array = []
			for clip in CLIPS_OF_INTEREST:
				if ap.has_animation(clip):
					var anim := ap.get_animation(clip)
					parts.append("%s(len=%.2f loop=%d)" % [clip, anim.length, anim.loop_mode])
			print("PROBE   clips: ", ", ".join(parts))
		inst.queue_free()
		await process_frame
	print("PROBE DONE")
	quit(0)
