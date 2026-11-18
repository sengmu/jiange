extends Node3D
## Unit staging probe (reskin verification): march, melee engagement,
## spellcast, crossbow shot, beast march + ram thrust, death fall.
## Run: xvfb-run godot --path . --resolution 1280x720 res://scenes/probe2.tscn

const UnitScript: GDScript = preload("res://scripts/articulated_unit.gd")
const BeastScript: GDScript = preload("res://scripts/siege_beast.gd")

var _cam: Camera3D
var _knight: ArticulatedUnit
var _barb: ArticulatedUnit
var _mage: ArticulatedUnit
var _rogue: ArticulatedUnit
var _beast: ArticulatedUnit
var _engaged := false


func _ready() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.07, 0.06, 0.09)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.40, 0.36, 0.34)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38, -35, 0)
	sun.light_color = Color(1.0, 0.75, 0.55)
	sun.light_energy = 0.95
	sun.shadow_enabled = true
	add_child(sun)
	var ground := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(46, 0.2, 30)
	ground.mesh = bm
	ground.position = Vector3(0, -0.1, 0)
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.23, 0.22, 0.20)
	ground.material_override = gm
	add_child(ground)

	_knight = UnitScript.new()
	_knight.configure("general", "player", "Knight", 500.0, 3.2, 2.2, 10.0, 1.0)
	_knight.position = Vector3(-6, 0, 2)
	add_child(_knight)
	_knight.move_to(Vector3(9, 0, 2))

	_barb = UnitScript.new()
	_barb.configure("enemy", "enemy", "Barb", 500.0, 2.6, 2.2, 10.0, 1.0)
	_barb.position = Vector3(6, 0, 2)
	add_child(_barb)
	_barb.move_to(Vector3(-9, 0, 2))

	_mage = UnitScript.new()
	_mage.configure("strategist", "player", "Mage", 500.0, 2.4, 20.0, 10.0, 1.0)
	_mage.position = Vector3(-6.5, 0, -3.5)
	add_child(_mage)
	_mage.face_towards(Vector3(10, 0, -3.5))

	_rogue = UnitScript.new()
	_rogue.configure("archer", "enemy", "Rogue", 500.0, 2.4, 12.0, 10.0, 1.0)
	_rogue.position = Vector3(-3.0, 0, -3.5)
	add_child(_rogue)
	_rogue.face_towards(Vector3(10, 0, -3.5))

	_beast = BeastScript.new()
	_beast.configure("beast", "enemy", "Beast", 900.0, 1.35, 4.4, 30.0, 1.4)
	_beast.position = Vector3(8.5, 0, -5.5)
	add_child(_beast)
	_beast.move_to(Vector3(-10, 0, -5.5))

	var ballista: Node3D = load("res://assets/kenney_castle/siege-ballista.glb").instantiate()
	ballista.position = Vector3(3.5, 0, -8.6)
	ballista.scale = Vector3.ONE * 1.6
	add_child(ballista)

	_cam = Camera3D.new()
	_cam.fov = 42.0
	add_child(_cam)
	_run()


func _shot(cam_pos: Vector3, target: Vector3, path: String) -> void:
	_cam.position = cam_pos
	_cam.look_at(target, Vector3.UP)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
	print("PROBE2 saved ", path)


func _wide() -> Vector3:
	return Vector3(0, 0.6, -0.5)


func _run() -> void:
	await get_tree().create_timer(0.7).timeout
	# Ballista front check: viewed from +Z.
	await _shot(Vector3(3.5, 1.3, -4.2), Vector3(3.5, 0.7, -8.6), "res://shots/probe2_ballista_front.png")
	# March frame.
	await _shot(Vector3(0, 4.6, 12.5), _wide(), "res://shots/probe2_march.png")
	# Wait for the melee pair to close, then engage them.
	var guard := 0
	while not _engaged and guard < 40:
		await get_tree().create_timer(0.15).timeout
		guard += 1
		if is_instance_valid(_knight) and is_instance_valid(_barb):
			if _knight.global_position.distance_to(_barb.global_position) < 2.8:
				_engaged = true
				_knight.stop_moving()
				_barb.stop_moving()
				_knight.set_combat_target(_barb)
				_barb.set_combat_target(_knight)
				_knight.begin_attack()
				_barb.begin_attack()
				_mage.play_attack()
				_rogue.play_attack()
	await get_tree().create_timer(0.38).timeout
	await _shot(Vector3(0, 4.6, 12.5), _wide(), "res://shots/probe2_combat.png")
	# Beast: stop it in view and make it ram twice.
	await get_tree().create_timer(1.2).timeout
	if is_instance_valid(_beast):
		_beast.stop_moving()
		_beast.face_towards(_beast.global_position + Vector3(-1, 0, 0))
		_beast.begin_attack()
	await get_tree().create_timer(0.16).timeout
	await _shot(Vector3(0, 4.6, 12.5), _wide(), "res://shots/probe2_beast_ram.png")
	# Death fall of the knight.
	await get_tree().create_timer(0.9).timeout
	if is_instance_valid(_knight):
		_knight.start_death()
	await get_tree().create_timer(0.55).timeout
	await _shot(Vector3(0, 4.6, 12.5), _wide(), "res://shots/probe2_death.png")
	get_tree().quit()
