extends Node3D
## Beast orientation probe: steep top-down view of the siege beast
## marching toward -X. Long axis vs travel direction is unambiguous
## from above. Run: xvfb-run godot --path . res://scenes/probe3.tscn

const BeastScript: GDScript = preload("res://scripts/siege_beast.gd")

var _cam: Camera3D
var _beast: ArticulatedUnit


func _ready() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.07, 0.06, 0.09)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.45, 0.42, 0.40)
	env.ambient_light_energy = 0.7
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -20, 0)
	sun.light_energy = 1.0
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
	# Heading marker: a red plank lying along the -X travel direction.
	var marker := MeshInstance3D.new()
	var mm := BoxMesh.new()
	mm.size = Vector3(14, 0.06, 0.5)
	marker.mesh = mm
	marker.position = Vector3(-2, 0.03, 0)
	var rm := StandardMaterial3D.new()
	rm.albedo_color = Color(0.7, 0.15, 0.12)
	marker.material_override = rm
	add_child(marker)

	_beast = BeastScript.new()
	_beast.configure("beast", "enemy", "Beast", 900.0, 1.6, 4.4, 30.0, 1.4)
	_beast.position = Vector3(6, 0, 0)
	add_child(_beast)
	_beast.move_to(Vector3(-10, 0, 0))

	_cam = Camera3D.new()
	_cam.fov = 40.0
	_cam.position = Vector3(0, 17, 7.5)
	add_child(_cam)
	_cam.look_at(Vector3(0, 0, 0), Vector3.UP)
	_run()


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
	print("PROBE3 saved ", path, " beast_x=", _beast.global_position.x)


func _run() -> void:
	await get_tree().create_timer(1.1).timeout
	await _shot("res://shots/probe3_top_a.png")
	await get_tree().create_timer(1.1).timeout
	await _shot("res://shots/probe3_top_b.png")
	get_tree().quit()
