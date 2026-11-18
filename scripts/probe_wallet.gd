extends Node3D

var game: Node

func _ready() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	_run()

func _grab(path: String) -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	print("PROBE_WALLET saved=", path)

func _run() -> void:
	await get_tree().create_timer(2.5).timeout
	await _grab("res://shots/wallet_select.png")
	game.call("_open_wallet_panel")
	await get_tree().create_timer(0.6).timeout
	await _grab("res://shots/wallet_panel.png")
	game.call("_close_wallet_panel")
	game.call("_on_hero_button", 0)
	game.call("select_hero", 0)
	await get_tree().create_timer(1.0).timeout
	game.set("gold", 5000)
	game.call("_start_wave", 3)
	await get_tree().create_timer(0.6).timeout
	var guard := 0
	while not (game.get("spawn_queue") as Array).is_empty() and guard < 160:
		game.call("_spawn_from_queue")
		guard += 1
	await get_tree().create_timer(1.2).timeout
	game.call("reset_camera_view")
	await get_tree().create_timer(0.5).timeout
	await _grab("res://shots/wallet_hud.png")
	print("PROBE_WALLET done")
	get_tree().quit()
