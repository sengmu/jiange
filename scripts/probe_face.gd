extends Node3D
## Facing probe: renders the Knight from +Z and -Z (rotation 0) and the
## siege ram from a 3/4 view, so the parent can settle model forward axes.
## Run: xvfb-run godot --path . res://scenes/probe_face.tscn

var _cam: Camera3D


func _ready() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.05, 0.06, 0.12)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.45, 0.48, 0.60)
	env.ambient_light_energy = 0.9
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, -30, 0)
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	add_child(sun)
	var ground := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(40, 0.2, 40)
	ground.mesh = bm
	ground.position = Vector3(0, -0.1, 0)
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.25, 0.24, 0.22)
	ground.material_override = gm
	add_child(ground)

	var knight: Node3D = load("res://assets/kaykit_char/Knight.glb").instantiate()
	knight.position = Vector3(-4, 0, 0)
	add_child(knight)
	var ram: Node3D = load("res://assets/kenney_castle/siege-ram.glb").instantiate()
	ram.position = Vector3(4, 0, 0)
	ram.scale = Vector3.ONE * 1.6
	add_child(ram)
	var ballista: Node3D = load("res://assets/kenney_castle/siege-ballista.glb").instantiate()
	ballista.position = Vector3(4, 0, -7)
	ballista.scale = Vector3.ONE * 1.6
	add_child(ballista)

	_cam = Camera3D.new()
	_cam.fov = 40.0
	add_child(_cam)
	_run()


func _shot(cam_pos: Vector3, target: Vector3, path: String) -> void:
	_cam.position = cam_pos
	_cam.look_at(target, Vector3.UP)
	await get_tree().create_timer(0.35).timeout
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
	print("PROBEFACE saved ", path)


func _run() -> void:
	await get_tree().create_timer(0.6).timeout
	# Knight from +Z side: face visible here iff the model faces +Z at rest.
	await _shot(Vector3(-4, 1.5, 5.2), Vector3(-4, 1.1, 0), "res://shots/probe_knight_from_plusZ.png")
	# Knight from -Z side.
	await _shot(Vector3(-4, 1.5, -5.2), Vector3(-4, 1.1, 0), "res://shots/probe_knight_from_minusZ.png")
	# Siege ram 3/4 from (+X,+Z) and from (-X,+Z): tells which end is the ram head.
	await _shot(Vector3(9.5, 3.0, 5.5), Vector3(4, 0.8, 0), "res://shots/probe_ram_a.png")
	await _shot(Vector3(-1.5, 3.0, 5.5), Vector3(4, 0.8, 0), "res://shots/probe_ram_b.png")
	# Ballista 3/4 view.
	await _shot(Vector3(9.0, 3.0, -1.5), Vector3(4, 0.8, -7), "res://shots/probe_ballista.png")
	get_tree().quit()
