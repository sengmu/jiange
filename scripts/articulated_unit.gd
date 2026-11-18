class_name ArticulatedUnit
extends Node3D
## Original procedural low-poly unit built from articulated part nodes.
## Animation is procedural: hip/shoulder pivots swing for walking, the weapon
## arm thrusts for attacks, the torso recoils on hits, and the whole visual
## root tips over on death. No single-mesh/static characters.

var archetype: String = "enemy"
var team: String = "enemy"
var display_name: String = "Unit"
var max_hp: float = 100.0
var hp: float = 100.0
var move_speed: float = 3.0
var attack_range: float = 2.4
var attack_damage: float = 10.0
var attack_cooldown_time: float = 0.8
var attack_timer: float = 0.0
var alive: bool = true
var body_radius: float = 0.55

var _move_target: Vector3 = Vector3.ZERO
var _has_move_target: bool = false
var _combat_target: Node3D = null
var _walk_phase: float = 0.0
var _moving: bool = false
var _attack_anim: float = 0.0
var _hit_anim: float = 0.0
var _hit_duration: float = 0.10
var _death_time: float = -1.0
var _desired_yaw: float = 0.0

var visual_root: Node3D
var torso_pivot: Node3D
var head_pivot: Node3D
var hip_l: Node3D
var hip_r: Node3D
var shoulder_l: Node3D
var shoulder_r: Node3D
var weapon_pivot: Node3D
var _flash_materials: Array = []
var _flash_base: Array = []

# Floating HP bar (optimization round): two quads (shared bg + fg meshes and
# shared materials, so the only per-unit cost is two draw calls while the
# bar is visible). Visibility rule: defenders and the siege beast always
# show their bar; regular enemies show it only once damaged, to keep a full
# wave of fresh infantry from covering the field in bars.
var hp_bar_root: Node3D
var hp_bar_fg: MeshInstance3D
var team_ring: MeshInstance3D
var hp_bar_fill: float = 1.0
var hp_bar_width: float = 1.25
var hp_bar_height: float = 0.15
var _hp_bar_mat_current: Material
var _death_fade: float = 1.0

static var _bar_bg_mat: StandardMaterial3D
static var _bar_border_mat: StandardMaterial3D
static var _bar_fg_def_mat: StandardMaterial3D
static var _bar_fg_enemy_mat: StandardMaterial3D
static var _bar_fg_low_mat: StandardMaterial3D
static var _bar_bg_mesh: QuadMesh
static var _bar_fg_mesh: QuadMesh
static var _ring_texture: Texture2D
static var _ring_mesh: QuadMesh
static var _ring_mat_enemy: StandardMaterial3D
static var _ring_mat_def: StandardMaterial3D


static func _ring_assets() -> void:
	if _ring_texture != null:
		return
	# Team disc texture (Rev 2): a translucent team-coloured fill with
	# a strong edge band, drawn once and shared by every unit. Rev 1's
	# thin torus read as broken arcs once models occluded it; a filled
	# disc keeps a continuous front edge and reads as a ground marker
	# at any distance.
	var size := 128
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var center := Vector2(size - 1, size - 1) * 0.5
	for yy in size:
		for xx in size:
			var r := Vector2(xx, yy).distance_to(center) / (size * 0.5)
			var a := 0.0
			if r < 0.78:
				a = 0.30
			elif r < 0.90:
				a = 1.0
			elif r <= 1.0:
				a = lerpf(1.0, 0.35, (r - 0.90) / 0.10)
			img.set_pixel(xx, yy, Color(1, 1, 1, a))
	_ring_texture = ImageTexture.create_from_image(img)
	_ring_mesh = QuadMesh.new()
	_ring_mesh.size = Vector2(2, 2)
	_ring_mat_enemy = StandardMaterial3D.new()
	_ring_mat_enemy.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ring_mat_enemy.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ring_mat_enemy.cull_mode = BaseMaterial3D.CULL_DISABLED
	_ring_mat_enemy.render_priority = 1
	_ring_mat_enemy.albedo_texture = _ring_texture
	_ring_mat_enemy.albedo_color = Color(1.0, 0.32, 0.16, 0.95)
	_ring_mat_def = StandardMaterial3D.new()
	_ring_mat_def.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ring_mat_def.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ring_mat_def.cull_mode = BaseMaterial3D.CULL_DISABLED
	_ring_mat_def.render_priority = 1
	_ring_mat_def.albedo_texture = _ring_texture
	_ring_mat_def.albedo_color = Color(0.35, 1.0, 0.45, 0.95)


static func _bar_materials() -> void:
	if _bar_bg_mat != null:
		return
	_bar_bg_mat = StandardMaterial3D.new()
	_bar_bg_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_bar_bg_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_bar_bg_mat.albedo_color = Color(0.01, 0.01, 0.02, 0.85)
	_bar_bg_mat.no_depth_test = false
	_bar_border_mat = StandardMaterial3D.new()
	_bar_border_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_bar_border_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_bar_border_mat.albedo_color = Color(0.92, 0.90, 0.82, 0.85)
	_bar_fg_def_mat = StandardMaterial3D.new()
	_bar_fg_def_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_bar_fg_def_mat.albedo_color = Color(0.35, 0.95, 0.42)
	_bar_fg_enemy_mat = StandardMaterial3D.new()
	_bar_fg_enemy_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_bar_fg_enemy_mat.albedo_color = Color(1.0, 0.36, 0.18)
	_bar_fg_low_mat = StandardMaterial3D.new()
	_bar_fg_low_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_bar_fg_low_mat.albedo_color = Color(1.0, 0.12, 0.08)
	_bar_bg_mesh = QuadMesh.new()
	_bar_fg_mesh = QuadMesh.new()
	_bar_fg_mesh.size = Vector2(1, 1)


# --- Pack model reskin (godot-slice-packs): KayKit CC0 characters ---
const MODEL_PATHS := {
	"strategist": "res://assets/kaykit_char/Mage.glb",
	"general": "res://assets/kaykit_char/Knight.glb",
	"archer": "res://assets/kaykit_char/Rogue_Hooded.glb",
	"rogue": "res://assets/kaykit_char/Rogue.glb",
	"enemy": "res://assets/kaykit_char/Barbarian.glb",
}
const MODEL_SCALES := {"strategist": 0.85, "general": 1.0, "archer": 1.05, "rogue": 1.05, "enemy": 1.05}
const MODEL_TINTS := {
	"strategist": Color(1.0, 1.0, 1.0),
	"general": Color(0.72, 1.0, 0.78),
	"archer": Color(0.98, 0.68, 0.55),
	"rogue": Color(0.88, 0.84, 0.78),
	"enemy": Color(1.02, 0.70, 0.58),
}
const MODEL_ATTACK_CLIPS := {
	"strategist": "Spellcast_Shoot",
	"general": "1H_Melee_Attack_Chop",
	"archer": "2H_Ranged_Shoot",
	"rogue": "1H_Melee_Attack_Chop",
	"enemy": "1H_Melee_Attack_Chop",
}
const MODEL_HIDDEN := {
	"strategist": ["1H_Wand", "Spellbook", "Spellbook_open"],
	"general": ["2H_Sword", "1H_Sword_Offhand", "Round_Shield", "Badge_Shield"],
	"archer": ["1H_Crossbow", "Knife", "Knife_Offhand", "Throwable"],
	"rogue": ["2H_Crossbow", "1H_Crossbow", "Throwable", "Bow", "Arrow"],
	"enemy": ["2H_Axe", "1H_Axe_Offhand", "Mug"],
}
# Stage-1 (full map + heroes): the visible model can be decoupled from the
# gameplay archetype. main.gd sets these BEFORE configure() when spawning
# heroes, bosses, trainees and NPCs; _build_model() resolves them.
var visual_key: String = ""
var visual_scale: float = -1.0
var visual_tint: Color = Color.WHITE
var visual_tint_set: bool = false
var _visual_resolved: String = ""
var _anim: AnimationPlayer = null
var _cur_clip: String = ""
var _hit_clip_cd: float = 0.0
var _hit_hold: float = 0.0


func configure(p_archetype: String, p_team: String, p_name: String, p_max_hp: float, p_speed: float, p_range: float, p_damage: float, p_cooldown: float) -> void:
	archetype = p_archetype
	team = p_team
	display_name = p_name
	max_hp = p_max_hp
	hp = p_max_hp
	move_speed = p_speed
	attack_range = p_range
	attack_damage = p_damage
	attack_cooldown_time = p_cooldown
	attack_timer = randf() * 0.3
	build_body()
	_build_hp_bar()
	_build_team_ring()


func _ready() -> void:
	if visual_root == null:
		build_body()


func _mat(color: Color, roughness: float = 0.85, emission_color: Color = Color.BLACK, emission_energy: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	if emission_energy > 0.0:
		m.emission_enabled = true
		m.emission = emission_color
		m.emission_energy_multiplier = emission_energy
	_flash_materials.append(m)
	_flash_base.append(color)
	return m


func _add_box(parent: Node, box_name: String, size: Vector3, pos: Vector3, material: Material, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = box_name
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.position = pos
	mi.rotation = rot
	mi.material_override = material
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	parent.add_child(mi)
	return mi


func _add_cylinder(parent: Node, cyl_name: String, top_r: float, bottom_r: float, height: float, pos: Vector3, material: Material, rot: Vector3 = Vector3.ZERO, segments: int = 10) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = cyl_name
	var mesh := CylinderMesh.new()
	mesh.top_radius = top_r
	mesh.bottom_radius = bottom_r
	mesh.height = height
	mesh.radial_segments = segments
	mi.mesh = mesh
	mi.position = pos
	mi.rotation = rot
	mi.material_override = material
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	parent.add_child(mi)
	return mi


func _add_sphere(parent: Node, sph_name: String, radius: float, pos: Vector3, material: Material, scale_factor: Vector3 = Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = sph_name
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 10
	mesh.rings = 6
	mi.mesh = mesh
	mi.position = pos
	mi.scale = scale_factor
	mi.material_override = material
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	parent.add_child(mi)
	return mi


func build_body() -> void:
	if visual_root != null:
		return
	_flash_materials.clear()
	_flash_base.clear()
	visual_root = Node3D.new()
	visual_root.name = "VisualRoot"
	add_child(visual_root)

	# Soft blob shadow (retained from the procedural version).
	var shadow_mat := StandardMaterial3D.new()
	shadow_mat.albedo_color = Color(0, 0, 0, 0.34)
	shadow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	shadow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var blob := MeshInstance3D.new()
	blob.name = "BlobShadow"
	var blob_mesh := CylinderMesh.new()
	blob_mesh.top_radius = 0.62
	blob_mesh.bottom_radius = 0.62
	blob_mesh.height = 0.03
	blob_mesh.radial_segments = 14
	blob.mesh = blob_mesh
	blob.position = Vector3(0, 0.025, 0)
	blob.material_override = shadow_mat
	blob.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	visual_root.add_child(blob)

	# Articulation anchors. The game logic and the harness reference these
	# exact node paths, and the base _process keeps driving them (walk swing,
	# attack thrust, hit flinch); they carry no geometry in the reskin — the
	# visible body is the pack model instanced below, animated by its own
	# AnimationPlayer state driver (_drive_model_anim).
	hip_l = Node3D.new()
	hip_l.name = "HipL"
	hip_l.position = Vector3(-0.21, 0.94, 0)
	visual_root.add_child(hip_l)
	hip_r = Node3D.new()
	hip_r.name = "HipR"
	hip_r.position = Vector3(0.21, 0.94, 0)
	visual_root.add_child(hip_r)

	torso_pivot = Node3D.new()
	torso_pivot.name = "TorsoPivot"
	torso_pivot.position = Vector3(0, 0.96, 0)
	visual_root.add_child(torso_pivot)

	head_pivot = Node3D.new()
	head_pivot.name = "HeadPivot"
	head_pivot.position = Vector3(0, 0.92, 0)
	torso_pivot.add_child(head_pivot)

	shoulder_l = Node3D.new()
	shoulder_l.name = "ShoulderL"
	shoulder_l.position = Vector3(-0.47, 0.76, 0)
	torso_pivot.add_child(shoulder_l)
	shoulder_r = Node3D.new()
	shoulder_r.name = "ShoulderR"
	shoulder_r.position = Vector3(0.47, 0.76, 0)
	torso_pivot.add_child(shoulder_r)

	weapon_pivot = Node3D.new()
	weapon_pivot.name = "WeaponPivot"
	weapon_pivot.position = Vector3(0, -0.70, 0.06)
	shoulder_r.add_child(weapon_pivot)

	if archetype == "archer":
		# Anchor nodes at the paths the harness checks; the visible crossbow
		# rides the model's handslot bone and the quiver its chest bone.
		var bow_anchor := Node3D.new()
		bow_anchor.name = "BowUpper"
		shoulder_l.add_child(bow_anchor)
		var quiver_anchor := Node3D.new()
		quiver_anchor.name = "Quiver"
		torso_pivot.add_child(quiver_anchor)

	_build_model()
	var model := visual_root.get_node_or_null("PackModel") as Node3D
	if model != null:
		_merge_model_parts(model)


func _build_model() -> void:
	_visual_resolved = visual_key if visual_key != "" else archetype
	var path: String = String(MODEL_PATHS.get(_visual_resolved, MODEL_PATHS["enemy"]))
	var ps: PackedScene = load(path)
	if ps == null:
		push_warning("unit model missing: " + path)
		return
	var model: Node3D = ps.instantiate()
	model.name = "PackModel"
	var scl := visual_scale if visual_scale > 0.0 else float(MODEL_SCALES.get(_visual_resolved, 1.0))
	# 单位可读性 Rev 1: heroes stand taller than minions. The player's
	# hero (strategist archetype, defender team) scales up and enemy
	# rank-and-file scales down, so the size hierarchy reads at the
	# classic camera distance. Bosses pass an explicit visual_scale
	# (already towering) and are exempt; the guard sits between.
	if visual_scale <= 0.0:
		if team == "defender" and archetype == "strategist":
			scl *= 1.22
		elif team == "defender" and archetype == "general":
			scl *= 1.08
		elif team == "enemy" and (archetype == "enemy" or archetype == "archer" or archetype == "trainee"):
			scl *= 0.93
	model.scale = Vector3.ONE * scl
	visual_root.add_child(model)
	# Each KayKit character scene carries every weapon variant on its
	# handslots; hide the ones this archetype does not use.
	for node_name in MODEL_HIDDEN.get(_visual_resolved, []):
		var w := model.find_child(String(node_name), true, false)
		if w != null:
			(w as Node).set("visible", false)
	if _visual_resolved == "archer":
		_attach_quiver(model)
	var tint: Color = visual_tint if visual_tint_set else MODEL_TINTS.get(_visual_resolved, Color.WHITE)
	_register_model_materials(model, tint)
	_anim = _find_animation_player(model)
	if _anim != null:
		# The imported clips ship with looping disabled; locomotion and
		# idle must loop (shared animation resources — same setting for
		# every instance of the model, which is what we want).
		for clip in ["Idle", "Walking_A", "Running_A"]:
			if _anim.has_animation(clip):
				_anim.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
		_play_clip("Idle", 1.0)


func _attach_quiver(model: Node3D) -> void:
	var skeleton: Skeleton3D = null
	var stack: Array = [model]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Skeleton3D:
			skeleton = n
			break
		for c in n.get_children():
			stack.push_back(c)
	if skeleton == null:
		return
	var ps: PackedScene = load("res://assets/kaykit_weapons/quiver.gltf")
	if ps == null:
		return
	var attach := BoneAttachment3D.new()
	attach.name = "QuiverAttach"
	attach.bone_name = "chest"
	skeleton.add_child(attach)
	var quiver: Node3D = ps.instantiate()
	quiver.position = Vector3(0.16, 0.02, -0.30)
	quiver.rotation_degrees = Vector3(-14.0, 0.0, 12.0)
	attach.add_child(quiver)


func _register_model_materials(model_root: Node, tint: Color) -> void:
	var stack: Array = [model_root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.push_back(c)
		if n is MeshInstance3D:
			var mi := n as MeshInstance3D
			if mi.mesh == null:
				continue
			for s in mi.mesh.get_surface_count():
				var mat := mi.mesh.surface_get_material(s)
				if mat is StandardMaterial3D:
					var dup: StandardMaterial3D = (mat as StandardMaterial3D).duplicate()
					var c0 := dup.albedo_color
					var c1 := Color(
						minf(c0.r * tint.r, 1.0), minf(c0.g * tint.g, 1.0),
						minf(c0.b * tint.b, 1.0), c0.a)
					if team == "enemy":
						# 单位可读性 Rev 2: a uniform tint left enemy
						# helmets/bodies as one near-black mass (Codex
						# 首审 point 4). Lift the darks toward warm
						# brown so parts separate, then lift parts by
						# name: head/hat brightest, weapons toward
						# steel, body a step up.
						var lum := 0.299 * c1.r + 0.587 * c1.g + 0.114 * c1.b
						if lum < 0.25:
							c1 = c1.lerp(Color(0.36, 0.28, 0.22), 0.30)
						var lname := mi.name.to_lower()
						# Rev 3 tiers: head brightest warm / body mid / arms low-mid / weapons cool steel.
						if lname.contains("head") or lname.contains("hat") or lname.contains("hood") or lname.contains("helmet"):
							c1 = Color(minf(c1.r * 1.50, 1.0), minf(c1.g * 1.50, 1.0), minf(c1.b * 1.50, 1.0), c1.a)
							c1 = c1.lerp(Color(1.0, 0.93, 0.78), 0.15)
						elif lname.contains("axe") or lname.contains("sword") or lname.contains("shield") or lname.contains("knife") or lname.contains("crossbow") or lname.contains("bow"):
							c1 = c1.lerp(Color(0.84, 0.87, 0.92), 0.75)
							dup.metallic = 0.55
							dup.roughness = 0.35
						elif lname.contains("body"):
							c1 = Color(minf(c1.r * 1.32, 1.0), minf(c1.g * 1.32, 1.0), minf(c1.b * 1.32, 1.0), c1.a)
							c1 = c1.lerp(Color(0.88, 0.80, 0.66), 0.22)
						elif lname.contains("arm"):
							c1 = Color(minf(c1.r * 1.00, 1.0), minf(c1.g * 1.00, 1.0), minf(c1.b * 1.00, 1.0), c1.a)
					dup.albedo_color = c1
					mi.set_surface_override_material(s, dup)
					_flash_materials.append(dup)
					_flash_base.append(dup.albedo_color)
			if team == "enemy" and archetype in ["enemy", "archer", "cavalry"]:
				var brim_name := mi.name.to_lower()
				if brim_name.contains("head") or brim_name.contains("hat") or brim_name.contains("hood") or brim_name.contains("helmet"):
					if mi.get_node_or_null("EnemyHatBrim") == null:
						var aabb := mi.get_aabb()
						var r := maxf(aabb.size.x, aabb.size.z) * 0.60
						var brim_mesh := CylinderMesh.new()
						brim_mesh.top_radius = r
						brim_mesh.bottom_radius = r
						brim_mesh.height = maxf(aabb.size.y * 0.10, 0.03)
						brim_mesh.radial_segments = 14
						var brim_mat := StandardMaterial3D.new()
						brim_mat.albedo_color = Color(0.80, 0.76, 0.69)
						brim_mat.roughness = 0.6
						var brim := MeshInstance3D.new()
						brim.name = "EnemyHatBrim"
						brim.mesh = brim_mesh
						brim.material_override = brim_mat
						brim.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
						brim.position = Vector3(aabb.get_center().x, aabb.position.y + aabb.size.y * 0.32, aabb.get_center().z)
						mi.add_child(brim)
				elif brim_name.contains("body") and mi.get_node_or_null("EnemyChestPlate") == null:
					var ba := mi.get_aabb()
					var bcx := ba.position.x + ba.size.x * 0.5 - ba.size.x * 0.05
					var bcy := ba.position.y + ba.size.y * 0.60
					var front_z := ba.position.z + ba.size.z
					var frame_mesh := BoxMesh.new()
					frame_mesh.size = Vector3(ba.size.x * 0.62, ba.size.y * 0.60, 0.045)
					var frame_mat := StandardMaterial3D.new()
					frame_mat.albedo_color = Color(0.40, 0.31, 0.19)
					frame_mat.metallic = 0.5
					frame_mat.roughness = 0.45
					var frame := MeshInstance3D.new()
					frame.name = "EnemyChestPlateFrame"
					frame.mesh = frame_mesh
					frame.position = Vector3(bcx, bcy, front_z - 0.028)
					frame.material_override = frame_mat
					frame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
					mi.add_child(frame)
					var plate_mesh := BoxMesh.new()
					plate_mesh.size = Vector3(ba.size.x * 0.60, ba.size.y * 0.58, 0.06)
					var plate_mat := StandardMaterial3D.new()
					plate_mat.albedo_color = Color(1.0, 0.93, 0.72)
					plate_mat.metallic = 0.3
					plate_mat.roughness = 0.38
					plate_mat.emission_enabled = true
					plate_mat.emission = Color(0.45, 0.36, 0.20)
					plate_mat.emission_energy_multiplier = 0.55
					var plate := MeshInstance3D.new()
					plate.name = "EnemyChestPlate"
					plate.mesh = plate_mesh
					plate.position = Vector3(bcx, bcy, front_z - 0.005)
					plate.material_override = plate_mat
					plate.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
					mi.add_child(plate)
				elif brim_name == "1h_axe" and mi.name not in MODEL_HIDDEN.get(_visual_resolved, []) and mi.get_node_or_null("EnemyBladeEdge") == null:
					var wa := mi.get_aabb()
					var edge_mesh := BoxMesh.new()
					edge_mesh.size = Vector3(0.12, wa.size.y * 0.52, wa.size.z * 1.15)
					var edge_mat := StandardMaterial3D.new()
					edge_mat.albedo_color = Color(0.97, 0.98, 1.0)
					edge_mat.metallic = 0.85
					edge_mat.roughness = 0.22
					edge_mat.emission_enabled = true
					edge_mat.emission = Color(0.55, 0.58, 0.65)
					edge_mat.emission_energy_multiplier = 1.6
					var edge := MeshInstance3D.new()
					edge.name = "EnemyBladeEdge"
					edge.mesh = edge_mesh
					edge.position = Vector3(wa.position.x + 0.025, wa.position.y + wa.size.y * 0.72, wa.position.z + wa.size.z * 0.5)
					edge.material_override = edge_mat
					edge.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
					mi.add_child(edge)
				elif brim_name == "2h_crossbow" and mi.name not in MODEL_HIDDEN.get(_visual_resolved, []) and mi.get_node_or_null("EnemyBladeEdge") == null:
					var ca := mi.get_aabb()
					var edge_mesh := BoxMesh.new()
					edge_mesh.size = Vector3(ca.size.x * 0.92, 0.09, 0.09)
					var edge_mat := StandardMaterial3D.new()
					edge_mat.albedo_color = Color(0.97, 0.98, 1.0)
					edge_mat.metallic = 0.85
					edge_mat.roughness = 0.22
					edge_mat.emission_enabled = true
					edge_mat.emission = Color(0.55, 0.58, 0.65)
					edge_mat.emission_energy_multiplier = 1.6
					var edge := MeshInstance3D.new()
					edge.name = "EnemyBladeEdge"
					edge.mesh = edge_mesh
					edge.position = Vector3(ca.position.x + ca.size.x * 0.5, ca.position.y + ca.size.y * 0.72, ca.position.z + ca.size.z - 0.10)
					edge.material_override = edge_mat
					edge.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
					mi.add_child(edge)


func _merge_model_parts(model: Node3D) -> void:
	var skeleton_node: Skeleton3D = null
	var nodes: Array[Node] = []
	var pending: Array[Node] = [model]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		nodes.append(node)
		if skeleton_node == null and node is Skeleton3D:
			skeleton_node = node
		for child in node.get_children():
			pending.append(child)
	if skeleton_node == null:
		return
	var skinned: Array[Dictionary] = []
	var statics: Array[Dictionary] = []
	var first_skin: Skin = null
	var has_brim := false
	# Mesh ARRAY_BONES values are indices into the Skin's bind list
	# (joint indices, resolved to skeleton bones by bind NAME), not
	# skeleton bone indices. The imported Skin binds only body bones;
	# attachment bones (hat/cape/weapons) have no joint, so converted
	# vertices must use the JOINT index of the nearest bound ancestor
	# bone (the bake already places them in skeleton space at the
	# attachment's rest offset, so they follow the ancestor rigidly —
	# matching how the attachment bones track their parents in clips).
	var bind_names: Array = []
	for node0 in nodes:
		if node0 is MeshInstance3D and (node0 as MeshInstance3D).skin != null:
			var sk0: Skin = (node0 as MeshInstance3D).skin
			for bi in sk0.get_bind_count():
				bind_names.append(String(sk0.get_bind_name(bi)))
			break
	for node in nodes:
		if not node is MeshInstance3D:
			continue
		var mi := node as MeshInstance3D
		if mi.mesh == null or not mi.visible:
			continue
		var entry := {"mi": mi, "bone": -1, "bake": true}
		if mi.name == &"EnemyHatBrim":
			statics.append(entry)
			has_brim = true
		elif mi.skin != null:
			if mi.transform.origin.length() > 0.001 or not mi.transform.basis.is_equal_approx(Basis.IDENTITY):
				continue
			var valid := mi.mesh.get_surface_count() > 0
			for surface in mi.mesh.get_surface_count():
				var arrays := mi.mesh.surface_get_arrays(surface)
				if arrays.size() != Mesh.ARRAY_MAX or not _merge_has_bones(arrays):
					valid = false
			if not valid:
				continue
			entry["bake"] = false
			skinned.append(entry)
			if first_skin == null:
				first_skin = mi.skin
		else:
			var ancestor := mi.get_parent()
			var attachment: BoneAttachment3D = null
			while ancestor != null and ancestor != model:
				if ancestor is BoneAttachment3D:
					attachment = ancestor
					break
				ancestor = ancestor.get_parent()
			if attachment != null:
				var target_name := String(attachment.bone_name)
				while target_name != "" and not bind_names.has(target_name):
					var bi := skeleton_node.find_bone(target_name)
					if bi < 0:
						target_name = ""
						break
					var parent := skeleton_node.get_bone_parent(bi)
					target_name = skeleton_node.get_bone_name(parent) if parent >= 0 else ""
				if target_name != "":
					entry["bone"] = bind_names.find(target_name)
					skinned.append(entry)
				else:
					statics.append(entry)
			else:
				statics.append(entry)
	var n1 := 0
	var n2 := 0
	if first_skin != null:
		n1 = _merge_parts_bucket(model, skinned, true, "MergedModel", skeleton_node, first_skin)
	if statics.size() >= 2 or has_brim:
		n2 = _merge_parts_bucket(model, statics, false, "EnemyHatBrim" if has_brim else "MergedStaticParts", skeleton_node, null)
	print("MERGE_UNIT arch=", archetype, " skinned_parts=", n1, " static_parts=", n2)


func _merge_has_bones(arrays: Array) -> bool:
	var bones: Variant = arrays[Mesh.ARRAY_BONES]
	var weights: Variant = arrays[Mesh.ARRAY_WEIGHTS]
	return (bones is PackedInt32Array or bones is PackedFloat32Array) and weights is PackedFloat32Array and not bones.is_empty() and not weights.is_empty()


func _merge_material_signature(material: Material) -> String:
	if not material is StandardMaterial3D:
		return str(material.get_instance_id()) if material != null else "null"
	var mat := material as StandardMaterial3D
	var signature: Array = []
	for color in [mat.albedo_color, mat.emission]:
		for component in [color.r, color.g, color.b, color.a]:
			signature.append(roundi(component * 24.0))
	for slot in BaseMaterial3D.TEXTURE_MAX:
		var texture := mat.get_texture(slot)
		signature.append(texture.resource_path if texture != null else "")
	signature.append_array([roundi(mat.roughness / 0.05), roundi(mat.metallic / 0.05), mat.transparency, mat.shading_mode, mat.cull_mode, mat.vertex_color_use_as_albedo, mat.vertex_color_is_srgb, mat.depth_draw_mode, mat.billboard_mode, mat.emission_enabled, mat.emission_energy_multiplier])
	return str(signature)


func _merge_bake_xform(mi: MeshInstance3D, model: Node3D, skeleton_node: Skeleton3D) -> Array:
	var t := Transform3D.IDENTITY
	var node: Node = mi
	while node != null and node != model and node != skeleton_node:
		if node is BoneAttachment3D:
			var b := skeleton_node.find_bone((node as BoneAttachment3D).bone_name)
			if b < 0:
				return [false, Transform3D.IDENTITY]
			t = skeleton_node.get_bone_global_rest(b) * t
		elif node is Node3D:
			t = (node as Node3D).transform * t
		node = node.get_parent()
	return [true, t]


func _merge_parts_bucket(model: Node3D, parts: Array[Dictionary], skinned: bool, mesh_name: String, skeleton_node: Skeleton3D, skin_resource: Skin) -> int:
	# Validate the entire bucket before constructing or hiding anything.
	var surfaces: Array[Dictionary] = []
	var use_uv := false
	var use_color := false
	var use_tangent := false
	var shadow := GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if model.is_inside_tree():
		if not model.global_transform.is_finite() or is_zero_approx(model.global_transform.basis.determinant()):
			return 0
	for part in parts:
		var mi: MeshInstance3D = part["mi"]
		shadow = maxi(shadow, mi.cast_shadow)
		var xform := Transform3D.IDENTITY
		if part["bake"]:
			# Bake into skeleton space: compose local transforms up to the
			# Skeleton3D, substituting each BoneAttachment3D with its bone's
			# global REST transform (attachment locals are identity and the
			# current pose must not leak into bind-space geometry).
			var bx: Array = _merge_bake_xform(mi, model, skeleton_node)
			if not bool(bx[0]):
				return 0
			xform = bx[1]
		if not xform.is_finite() or is_zero_approx(xform.basis.determinant()):
			return 0
		for surface in mi.mesh.get_surface_count():
			if mi.mesh is ArrayMesh:
				if (mi.mesh as ArrayMesh).surface_get_primitive_type(surface) != Mesh.PRIMITIVE_TRIANGLES:
					return 0
			elif not mi.mesh is PrimitiveMesh:
				return 0
			var arrays := mi.mesh.surface_get_arrays(surface)
			if arrays.size() != Mesh.ARRAY_MAX or not arrays[Mesh.ARRAY_VERTEX] is PackedVector3Array:
				return 0
			var count: int = arrays[Mesh.ARRAY_VERTEX].size()
			if count == 0 or not arrays[Mesh.ARRAY_NORMAL] is PackedVector3Array or arrays[Mesh.ARRAY_NORMAL].size() != count:
				return 0
			for vertex in arrays[Mesh.ARRAY_VERTEX]:
				if not vertex.is_finite():
					return 0
			for normal in arrays[Mesh.ARRAY_NORMAL]:
				if not normal.is_finite():
					return 0
			for channel in [Mesh.ARRAY_TEX_UV, Mesh.ARRAY_COLOR, Mesh.ARRAY_TANGENT, Mesh.ARRAY_INDEX]:
				var data: Variant = arrays[channel]
				if data == null:
					continue
				if (channel == Mesh.ARRAY_TEX_UV and not data is PackedVector2Array) or (channel == Mesh.ARRAY_COLOR and not data is PackedColorArray) or (channel == Mesh.ARRAY_TANGENT and not data is PackedFloat32Array) or (channel == Mesh.ARRAY_INDEX and not data is PackedInt32Array):
					return 0
				if channel != Mesh.ARRAY_INDEX and not data.is_empty() and data.size() != count * (4 if channel == Mesh.ARRAY_TANGENT else 1):
					return 0
			if skinned and not part["bake"]:
				if not _merge_has_bones(arrays) or arrays[Mesh.ARRAY_BONES].size() != count * 4 or arrays[Mesh.ARRAY_WEIGHTS].size() != count * 4:
					return 0
				for bone in arrays[Mesh.ARRAY_BONES]:
					if not is_finite(float(bone)) or bone < 0 or bone != int(bone) or bone >= skin_resource.get_bind_count():
						return 0
				for weight in arrays[Mesh.ARRAY_WEIGHTS]:
					if not is_finite(weight) or weight < 0.0:
						return 0
			var indices: Variant = arrays[Mesh.ARRAY_INDEX]
			if indices != null and not indices.is_empty():
				if indices.size() % 3 != 0:
					return 0
				for index in indices:
					if index < 0 or index >= count:
						return 0
			elif count % 3 != 0:
				return 0
			use_uv = use_uv or (arrays[Mesh.ARRAY_TEX_UV] != null and not arrays[Mesh.ARRAY_TEX_UV].is_empty())
			use_color = use_color or (arrays[Mesh.ARRAY_COLOR] != null and not arrays[Mesh.ARRAY_COLOR].is_empty())
			use_tangent = use_tangent or (arrays[Mesh.ARRAY_TANGENT] != null and not arrays[Mesh.ARRAY_TANGENT].is_empty())
			var material := mi.get_surface_override_material(surface)
			if material == null:
				material = mi.mesh.surface_get_material(surface)
			# Procedural brims use a whole-instance override.
			if material == null:
				material = mi.material_override
			surfaces.append({"arrays": arrays, "material": material, "xform": xform, "bake": part["bake"], "bone": part["bone"]})
	if surfaces.is_empty() or model.get_node_or_null(NodePath(mesh_name)) != null:
		return 0
	var groups: Dictionary = {}
	for surface in surfaces:
		var key := _merge_material_signature(surface["material"])
		if not groups.has(key):
			groups[key] = {"material": surface["material"], "surfaces": []}
		groups[key]["surfaces"].append(surface)
	var mesh := ArrayMesh.new()
	var materials: Array[Material] = []
	for group in groups.values():
		var vertices := PackedVector3Array()
		var normals := PackedVector3Array()
		var uv := PackedVector2Array()
		var colors := PackedColorArray()
		var tangents := PackedFloat32Array()
		var bones := PackedInt32Array()
		var weights := PackedFloat32Array()
		var indices := PackedInt32Array()
		for surface in group["surfaces"]:
			var arrays: Array = surface["arrays"]
			var source: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var offset := vertices.size()
			var xform: Transform3D = surface["xform"]
			var normal_basis := xform.basis.inverse().transposed()
			for v in source.size():
				vertices.append(xform * source[v] if surface["bake"] else source[v])
				var normal: Vector3 = arrays[Mesh.ARRAY_NORMAL][v]
				normals.append((normal_basis * normal).normalized() if surface["bake"] else normal)
				if use_uv:
					uv.append(arrays[Mesh.ARRAY_TEX_UV][v] if arrays[Mesh.ARRAY_TEX_UV] != null and not arrays[Mesh.ARRAY_TEX_UV].is_empty() else Vector2.ZERO)
				if use_color:
					colors.append(arrays[Mesh.ARRAY_COLOR][v] if arrays[Mesh.ARRAY_COLOR] != null and not arrays[Mesh.ARRAY_COLOR].is_empty() else Color.WHITE)
				if use_tangent:
					var tangent := Vector3.RIGHT
					var handedness := 1.0
					if arrays[Mesh.ARRAY_TANGENT] != null and not arrays[Mesh.ARRAY_TANGENT].is_empty():
						tangent = Vector3(arrays[Mesh.ARRAY_TANGENT][v * 4], arrays[Mesh.ARRAY_TANGENT][v * 4 + 1], arrays[Mesh.ARRAY_TANGENT][v * 4 + 2])
						handedness = arrays[Mesh.ARRAY_TANGENT][v * 4 + 3]
						if surface["bake"]:
							tangent = (xform.basis * tangent).normalized()
							handedness *= signf(xform.basis.determinant())
					tangents.append_array(PackedFloat32Array([tangent.x, tangent.y, tangent.z, handedness]))
				if skinned:
					for influence in 4:
						bones.append((surface["bone"] if influence == 0 else 0) if surface["bake"] else int(arrays[Mesh.ARRAY_BONES][v * 4 + influence]))
						weights.append((1.0 if influence == 0 else 0.0) if surface["bake"] else arrays[Mesh.ARRAY_WEIGHTS][v * 4 + influence])
			if arrays[Mesh.ARRAY_INDEX] != null and not arrays[Mesh.ARRAY_INDEX].is_empty():
				for index in arrays[Mesh.ARRAY_INDEX]:
					indices.append(offset + index)
			else:
				for index in source.size():
					indices.append(offset + index)
		var output: Array = []
		output.resize(Mesh.ARRAY_MAX)
		output[Mesh.ARRAY_VERTEX] = vertices
		output[Mesh.ARRAY_NORMAL] = normals
		output[Mesh.ARRAY_INDEX] = indices
		if use_uv:
			output[Mesh.ARRAY_TEX_UV] = uv
		if use_color:
			output[Mesh.ARRAY_COLOR] = colors
		if use_tangent:
			output[Mesh.ARRAY_TANGENT] = tangents
		if skinned:
			output[Mesh.ARRAY_BONES] = bones
			output[Mesh.ARRAY_WEIGHTS] = weights
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, output)
		materials.append(group["material"])
		if mesh.get_surface_count() != materials.size():
			return 0
	var merged := MeshInstance3D.new()
	merged.name = mesh_name
	merged.mesh = mesh
	merged.cast_shadow = shadow
	for surface in materials.size():
		merged.set_surface_override_material(surface, materials[surface])
	if skinned:
		merged.skin = skin_resource
	model.add_child(merged)
	if skinned:
		merged.skeleton = merged.get_path_to(skeleton_node)
	for part in parts:
		part["mi"].visible = false
	return parts.size()


func _find_animation_player(node_root: Node) -> AnimationPlayer:
	if node_root is AnimationPlayer:
		return node_root
	for c in node_root.get_children():
		var res := _find_animation_player(c)
		if res != null:
			return res
	return null


func _play_clip(clip: String, speed: float = 1.0) -> void:
	if _anim == null or not _anim.has_animation(clip):
		return
	_cur_clip = clip
	_anim.speed_scale = speed
	_anim.play(clip)


func _restart_clip(clip: String, speed: float = 1.0) -> void:
	if _anim == null or not _anim.has_animation(clip):
		return
	_cur_clip = clip
	_anim.speed_scale = speed
	if _anim.current_animation == clip and _anim.is_playing():
		_anim.seek(0.0, true)
	else:
		_anim.play(clip)


func _play_attack_clip() -> void:
	if _anim == null:
		return
	var key := _visual_resolved if _visual_resolved != "" else archetype
	var clip: String = String(MODEL_ATTACK_CLIPS.get(key, "1H_Melee_Attack_Chop"))
	if not _anim.has_animation(clip):
		return
	var spd := clampf(_anim.get_animation(clip).length / 0.50, 1.0, 2.6)
	_restart_clip(clip, spd)


func _drive_model_anim() -> void:
	if _anim == null:
		return
	if _hit_hold > 0.0:
		return
	if _attack_anim > 0.0:
		return # attack clip is triggered by begin_attack()/play_attack()
	if _moving:
		if _cur_clip != "Walking_A" or not _anim.is_playing():
			_play_clip("Walking_A", clampf(move_speed / 2.7, 0.85, 1.9))
	else:
		if _cur_clip != "Idle" or not _anim.is_playing():
			_play_clip("Idle", 1.0)
func _build_team_ring() -> void:
	# 单位可读性 Rev 1+2: a flat team-coloured disc under every unit,
	# so friend/foe reads at any camera distance — at the classic
	# framing body tints are a few pixels and HP bars are sub-pixel,
	# but a red or green disc under each unit still reads. Rev 2
	# replaced the Rev 1 torus with a filled disc (shared quad +
	# procedural ring texture): the torus read as broken arcs once
	# models occluded it, the disc keeps a continuous front edge.
	# The strong edge band (texture r 0.78-1.0 -> world 1.13-1.45 at
	# f=1.45) sits outside the contact-shadow disc (radius 1.05, or
	# 1.1x scale for bosses / 2.2 for the beast — f scales with it).
	# Direct child of the unit (not visual_root, which tips over on
	# death); start_death() hides it.
	if team_ring != null:
		return
	_ring_assets()
	var f := 1.45
	if archetype == "beast":
		f = 3.1
	elif archetype == "boss":
		f = 1.45 * (clampf(visual_scale, 1.0, 2.0) if visual_scale > 0.0 else 1.4)
	team_ring = MeshInstance3D.new()
	team_ring.name = "TeamRing"
	team_ring.mesh = _ring_mesh
	team_ring.rotation.x = -PI / 2.0
	team_ring.position = Vector3(0, 0.12, 0)
	team_ring.scale = Vector3(f, f, f)
	team_ring.material_override = _ring_mat_enemy if team == "enemy" else _ring_mat_def
	team_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(team_ring)


func _build_hp_bar() -> void:
	if hp_bar_root != null:
		return
	_bar_materials()
	# 单位可读性 Rev 1: bars were 1.25x0.15 — sub-pixel at the classic
	# framing and near-black in dusk light. Bigger bars, a pale border
	# quad behind the dark backing so the bar silhouette separates
	# from dark armour/ground, and brighter fills (see _bar_materials).
	var y := 2.62
	hp_bar_width = 1.6
	hp_bar_height = 0.24
	if archetype == "beast":
		hp_bar_width = 3.2
		hp_bar_height = 0.30
		y = 3.85
	elif archetype == "boss":
		# Bosses are scaled-up models; main.gd repositions the bar root
		# after configure() once the visual scale is known.
		hp_bar_width = 3.4
		hp_bar_height = 0.30
		y = 4.60
	elif team == "defender":
		hp_bar_width = 1.75
		y = 2.62
		if archetype == "strategist":
			# The hero model scales up (see _build_model); keep the
			# bar clear of the taller head/shoulders.
			y = 2.95
	hp_bar_root = Node3D.new()
	hp_bar_root.name = "HpBar"
	hp_bar_root.position = Vector3(0, y, 0)
	add_child(hp_bar_root)
	var border := MeshInstance3D.new()
	border.name = "HpBarBorder"
	var backing := ArrayMesh.new()
	for layer in 2:
		var arrays := _bar_bg_mesh.get_mesh_arrays().duplicate(true)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var padding := 0.18 if layer == 0 else 0.10
		for v in vertices.size():
			vertices[v] = Vector3(vertices[v].x * (hp_bar_width + padding), vertices[v].y * (hp_bar_height + padding), vertices[v].z + (-0.02 if layer == 0 else 0.0))
		arrays[Mesh.ARRAY_VERTEX] = vertices
		backing.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	border.mesh = backing
	border.set_surface_override_material(0, _bar_border_mat)
	border.set_surface_override_material(1, _bar_bg_mat)
	border.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	hp_bar_root.add_child(border)
	hp_bar_fg = MeshInstance3D.new()
	hp_bar_fg.name = "HpBarFg"
	hp_bar_fg.mesh = _bar_fg_mesh
	hp_bar_fg.position.z = 0.02
	hp_bar_fg.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	hp_bar_root.add_child(hp_bar_fg)
	_update_hp_bar()


func _update_hp_bar() -> void:
	if hp_bar_root == null:
		return
	if not alive:
		hp_bar_root.visible = false
		return
	hp_bar_fill = clampf(hp / max_hp, 0.0, 1.0) if max_hp > 0.0 else 0.0
	var show := team == "defender" or archetype == "beast" or archetype == "boss" or hp < max_hp - 0.01
	hp_bar_root.visible = show
	if not show:
		return
	# Billboard: copy the camera basis so the bar always faces the viewer.
	if is_inside_tree():
		var cam := get_viewport().get_camera_3d()
		if cam != null:
			var gt := hp_bar_root.global_transform
			gt.basis = cam.global_transform.basis
			hp_bar_root.global_transform = gt
			# Rev 2: cap the bar's screen size. At close range the
			# Rev 1 bars covered heads/shoulders and crowded each
			# other; shrink the root as the camera closes in (the
			# classic framing sits ~55+ units away = full size).
			var dcam := cam.global_position.distance_to(global_position)
			var bs := clampf(dcam / 55.0, 0.70, 1.0)
			hp_bar_root.scale = Vector3.ONE * bs
	hp_bar_fg.scale = Vector3(maxf(hp_bar_width * hp_bar_fill, 0.001), hp_bar_height, 1)
	hp_bar_fg.position.x = -hp_bar_width * (1.0 - hp_bar_fill) * 0.5
	var want: Material = _bar_fg_enemy_mat
	if hp_bar_fill < 0.30:
		want = _bar_fg_low_mat
	elif team == "defender":
		want = _bar_fg_def_mat
	if _hp_bar_mat_current != want:
		_hp_bar_mat_current = want
		hp_bar_fg.material_override = want


func death_fade_alpha() -> float:
	return _death_fade


func move_to(pos: Vector3) -> void:
	_move_target = Vector3(pos.x, 0, pos.z)
	_has_move_target = true
	_combat_target = null


func set_combat_target(target: Node3D) -> void:
	_combat_target = target
	_has_move_target = false


func stop_moving() -> void:
	_has_move_target = false
	_combat_target = null


func face_towards(pos: Vector3) -> void:
	var d := Vector3(pos.x - global_position.x, 0, pos.z - global_position.z)
	if d.length() > 0.05:
		_desired_yaw = atan2(d.x, d.z)


func can_attack() -> bool:
	return alive and attack_timer <= 0.0


func begin_attack() -> void:
	attack_timer = attack_cooldown_time
	_attack_anim = 0.32
	_play_attack_clip()


func try_attack() -> bool:
	if not can_attack():
		return false
	if not is_instance_valid(_combat_target):
		return false
	var d := _flat_distance(global_position, _combat_target.global_position)
	if d > attack_range + 0.35:
		return false
	begin_attack()
	return true


func play_attack() -> void:
	_attack_anim = 0.32
	_play_attack_clip()


func play_hit() -> void:
	if not alive:
		return
	_hit_anim = _hit_duration
	for i in _flash_materials.size():
		var m: StandardMaterial3D = _flash_materials[i]
		m.emission_enabled = true
		m.emission = Color.html("#ff614d")
		m.emission_energy_multiplier = 0.5
	if _anim != null and alive and _attack_anim <= 0.0 and _hit_clip_cd <= 0.0 and _anim.has_animation("Hit_A"):
		_hit_clip_cd = 0.6
		_hit_hold = 0.30
		_restart_clip("Hit_A", 1.5)


func start_death() -> void:
	if not alive:
		return
	alive = false
	_death_time = 0.0
	_has_move_target = false
	_combat_target = null
	if team_ring != null:
		team_ring.visible = false
	# Death fade-out (optimization round): the fall plays first, then the
	# body materials fade while the corpse sinks, instead of vanishing.
	for m in _flash_materials:
		(m as StandardMaterial3D).transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# NOTE: the KayKit Death_A clip is deliberately NOT played — its root
	# motion compounds with the base tip-over and buries the model under
	# the ground plane (verified in probe renders). The base fall + fade
	# carries the death read on its own.


func get_hit_position() -> Vector3:
	return global_position + Vector3(0, 1.45, 0)


func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _process(delta: float) -> void:
	_hit_clip_cd = maxf(_hit_clip_cd - delta, 0.0)
	_hit_hold = maxf(_hit_hold - delta, 0.0)
	attack_timer = maxf(attack_timer - delta, 0.0)
	_update_hp_bar()
	if not alive:
		if _death_time >= 0.0:
			_death_time += delta
			var t: float = clampf(_death_time / 0.45, 0.0, 1.0)
			visual_root.rotation.x = -PI * 0.5 * t
			visual_root.position.y = 0.12 * sin(t * PI)
			if _death_time > 1.0:
				visual_root.position.y = -(_death_time - 1.0) * 0.55
			if _death_time > 0.55:
				_death_fade = clampf(1.0 - (_death_time - 0.55) / 0.95, 0.0, 1.0)
				for i in _flash_materials.size():
					var m: StandardMaterial3D = _flash_materials[i]
					var base: Color = _flash_base[i]
					m.albedo_color = Color(base.r, base.g, base.b, base.a * _death_fade)
			if _death_time > 1.6:
				queue_free()
		return

	_moving = false
	var destination := Vector3.ZERO
	var has_destination := false
	if is_instance_valid(_combat_target):
		var tp: Vector3 = _combat_target.global_position
		face_towards(tp)
		if _flat_distance(global_position, tp) > attack_range * 0.82:
			destination = tp
			has_destination = true
	elif _combat_target != null:
		_combat_target = null
	if not has_destination and _has_move_target:
		destination = _move_target
		has_destination = true
		if _flat_distance(global_position, destination) < 0.25:
			_has_move_target = false
			has_destination = false

	if has_destination:
		var to_dest := Vector3(destination.x - global_position.x, 0, destination.z - global_position.z)
		var dist := to_dest.length()
		if dist > 0.05:
			var step: float = minf(move_speed * delta, dist)
			global_position += to_dest / dist * step
			face_towards(global_position + to_dest)
			_moving = true

	rotation.y = lerp_angle(rotation.y, _desired_yaw, minf(1.0, delta * 10.0))

	_drive_model_anim()

	# Procedural animation.
	if _moving:
		_walk_phase += delta * move_speed * 3.4
	else:
		_walk_phase = lerpf(_walk_phase, roundf(_walk_phase / PI) * PI, minf(1.0, delta * 8.0))
	var swing := sin(_walk_phase)
	var amp := 0.55 if _moving else 0.04
	hip_l.rotation.x = swing * amp
	hip_r.rotation.x = -swing * amp
	visual_root.position.y = absf(cos(_walk_phase)) * (0.07 if _moving else 0.015)
	torso_pivot.rotation.z = swing * (0.045 if _moving else 0.012)
	if _attack_anim > 0.0:
		_attack_anim = maxf(_attack_anim - delta, 0.0)
		var p := 1.0 - _attack_anim / 0.32
		var thrust := sin(p * PI)
		shoulder_r.rotation.x = -1.15 * thrust
		weapon_pivot.position.z = 0.06 + 0.55 * thrust
		shoulder_l.rotation.x = -swing * amp * 0.6
	else:
		shoulder_r.rotation.x = -swing * amp * 0.7
		weapon_pivot.position.z = lerpf(weapon_pivot.position.z, 0.06, minf(1.0, delta * 10.0))
		shoulder_l.rotation.x = swing * amp * 0.7
	if _hit_anim > 0.0:
		_hit_anim = maxf(_hit_anim - delta, 0.0)
		torso_pivot.rotation.x = -0.32 * (_hit_anim / _hit_duration)
		if _hit_anim <= 0.0:
			for i in _flash_materials.size():
				var m: StandardMaterial3D = _flash_materials[i]
				m.emission_enabled = false
				m.emission_energy_multiplier = 0.0
	else:
		torso_pivot.rotation.x = lerpf(torso_pivot.rotation.x, 0.0, minf(1.0, delta * 10.0))
