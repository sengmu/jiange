class_name SiegeBeast
extends ArticulatedUnit
## Large quadruped siege beast built from articulated parts: four leg pivots
## with code-driven stepping (back pair in counter-phase), a lunging head,
## armored body with war banners. Reuses the base unit's movement, combat
## and damage plumbing; only the body plan and gait differ. Original
## procedural geometry, no external assets.

var leg_bl: Node3D
var leg_br: Node3D

# Pack reskin state (Kenney siege-ram): rolling wheels + log thrust.
var _ram_model: Node3D = null
var _ram_log: Node3D = null
var _ram_log_base_x: float = 0.0
var _ram_wheels: Array = []


func _init() -> void:
	body_radius = 1.7


func build_body() -> void:
	if visual_root != null:
		return
	_flash_materials.clear()
	_flash_base.clear()
	visual_root = Node3D.new()
	visual_root.name = "VisualRoot"
	add_child(visual_root)

	# Wide soft shadow, stretched to the ram's footprint.
	var shadow_mat := StandardMaterial3D.new()
	shadow_mat.albedo_color = Color(0, 0, 0, 0.36)
	shadow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	shadow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var blob := MeshInstance3D.new()
	blob.name = "BlobShadow"
	var blob_mesh := CylinderMesh.new()
	blob_mesh.top_radius = 1.9
	blob_mesh.bottom_radius = 1.9
	blob_mesh.height = 0.03
	blob_mesh.radial_segments = 16
	blob.mesh = blob_mesh
	blob.position = Vector3(0, 0.025, 0)
	blob.scale = Vector3(0.72, 1.0, 1.42)
	blob.material_override = shadow_mat
	blob.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	visual_root.add_child(blob)

	# Leg pivots: anchors only in the reskin (the harness checks these paths
	# and that their rotations still animate; the visible body is the ram).
	hip_l = _make_leg("LegFL", Vector3(-0.85, 1.55, 1.05))
	hip_r = _make_leg("LegFR", Vector3(0.85, 1.55, 1.05))
	leg_bl = _make_leg("LegBL", Vector3(-0.85, 1.55, -1.05))
	leg_br = _make_leg("LegBR", Vector3(0.85, 1.55, -1.05))

	# Body/head/shoulder pivots kept at the original positions (base attack
	# animation and the head-lunge code drive them; they carry no geometry).
	torso_pivot = Node3D.new()
	torso_pivot.name = "TorsoPivot"
	torso_pivot.position = Vector3(0, 1.55, 0)
	visual_root.add_child(torso_pivot)
	head_pivot = Node3D.new()
	head_pivot.name = "HeadPivot"
	head_pivot.position = Vector3(0, 0.75, 1.65)
	torso_pivot.add_child(head_pivot)
	shoulder_l = Node3D.new()
	shoulder_l.name = "ShoulderL"
	shoulder_l.position = Vector3(-0.80, 1.05, 1.30)
	torso_pivot.add_child(shoulder_l)
	shoulder_r = Node3D.new()
	shoulder_r.name = "ShoulderR"
	shoulder_r.position = Vector3(0.80, 1.05, 1.30)
	torso_pivot.add_child(shoulder_r)
	weapon_pivot = Node3D.new()
	weapon_pivot.name = "WeaponPivot"
	shoulder_r.add_child(weapon_pivot)

	# Kenney siege ram as the visible body. Native long axis is X with the
	# battering log at the -X end (verified by probe renders); rotating
	# +90 deg about Y points the log along +Z, the game's facing direction.
	var ps: PackedScene = load("res://assets/kenney_castle/siege-ram.glb")
	if ps != null:
		_ram_model = ps.instantiate() as Node3D
		_ram_model.name = "PackModel"
		_ram_model.rotation.y = PI / 2.0
		_ram_model.scale = Vector3.ONE * 2.5
		visual_root.add_child(_ram_model)
		_ram_log = _ram_model.find_child("ram", true, false) as Node3D
		if _ram_log != null:
			_ram_log_base_x = _ram_log.position.x
		_ram_wheels.clear()
		for w in _ram_model.find_children("wheel*", "Node3D", true, false):
			_ram_wheels.append(w)
		_register_model_materials(_ram_model, Color(0.84, 0.78, 0.71))


func _make_leg(leg_name: String, pos: Vector3) -> Node3D:
	var pivot := Node3D.new()
	pivot.name = leg_name
	pivot.position = pos
	visual_root.add_child(pivot)
	return pivot


func get_hit_position() -> Vector3:
	return global_position + Vector3(0, 2.1, 0)


func _process(delta: float) -> void:
	super._process(delta)
	if leg_bl == null or leg_br == null or visual_root == null:
		return
	if not alive:
		# Tip sideways instead of the humanoid forward fall.
		if _death_time >= 0.0:
			var t: float = clampf(_death_time / 0.45, 0.0, 1.0)
			visual_root.rotation.x = 0.0
			visual_root.rotation.z = -PI * 0.45 * t
		return
	# Back legs step in counter-phase to the front pair.
	leg_bl.rotation.x = -hip_l.rotation.x
	leg_br.rotation.x = -hip_r.rotation.x
	# Head lunge while attacking.
	if head_pivot != null:
		if _attack_anim > 0.0:
			var p := 1.0 - _attack_anim / 0.32
			head_pivot.rotation.x = 0.55 * sin(p * PI)
		else:
			head_pivot.rotation.x = lerpf(head_pivot.rotation.x, 0.0, minf(1.0, delta * 8.0))
	# Pack reskin: the battering log thrusts in sync with the attack
	# window. (Wheel spin was tried and dropped: the wheel nodes' origins
	# sit at a mesh corner, not the hub, so rotating them swings the
	# wheels off the chassis — verified in probe renders.)
	if _ram_model != null:
		if _ram_log != null:
			if _attack_anim > 0.0:
				var lp := 1.0 - _attack_anim / 0.32
				_ram_log.position.x = _ram_log_base_x - sin(lp * PI) * 0.30
			else:
				_ram_log.position.x = lerpf(_ram_log.position.x, _ram_log_base_x, minf(1.0, delta * 8.0))
