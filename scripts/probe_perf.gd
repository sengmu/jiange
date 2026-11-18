extends Node3D
## Performance probe (mobile round): verifies the quality tiers render
## for real — tier 0 (shadows + glow + all trees) vs tier 2 (no shadows,
## no glow, every 4th tree) — and photographs both. Also reports the
## measured llvmpipe FPS for the log; that number is a desktop software
## renderer figure and must NOT be quoted as a phone frame rate.
## Run: xvfb-run godot --path . --resolution 1280x720 res://scenes/probe_perf.tscn

var game: Node


func _ready() -> void:
	_beat("ready_start")
	game = load("res://scenes/main.tscn").instantiate()
	_beat("game_loaded")
	add_child(game)
	_beat("game_added")
	_run()


func _beat(tag: String) -> void:
	var f := FileAccess.open("res://.tmp/probe_perf_hb.txt", FileAccess.WRITE_READ)
	if f == null:
		return
	f.seek_end()
	f.store_line("%d frames=%d %s" % [Time.get_ticks_msec(), Engine.get_frames_drawn(), tag])
	f.close()


func _grab(path: String) -> void:
	_beat("grab_start " + path)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	_beat("grab_frames_done " + path)
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
	print("PROBE_PERF saved=", path)


func _tier_state() -> Dictionary:
	return {
		"tier": int(game.get("quality_tier")),
		"shadow": bool((game.get("sun_light") as DirectionalLight3D).shadow_enabled),
		"glow": bool((game.get("env_ref") as Environment).glow_enabled),
		"trees": int(game.call("count_visible_vegetation")),
		"fps_avg": float(game.get("_perf_fps_avg")),
	}


func _run() -> void:
	_beat("run_start")
	await get_tree().create_timer(2.0).timeout
	_beat("after_2s_timer")
	game.call("select_hero", 0) # 赵统
	await get_tree().create_timer(1.0).timeout
	game.call("reset_camera_view")
	await get_tree().create_timer(0.5).timeout
	var results := {}
	# Tier 0: explicit manual set (locks the auto guard for the probe).
	game.call("set_quality_tier", 0)
	await get_tree().create_timer(0.5).timeout
	var s0 := _tier_state()
	print("PROBE_PERF tier0=", s0)
	results["tier0_shadow_on"] = s0["shadow"] == true
	results["tier0_glow_on"] = s0["glow"] == true
	results["tier0_all_trees"] = s0["trees"] == 45
	await _grab("res://shots/perf_tier0_high.png")
	# Tier 2: shadows + glow off, every 4th tree.
	game.call("set_quality_tier", 2)
	await get_tree().create_timer(0.5).timeout
	var s2 := _tier_state()
	print("PROBE_PERF tier2=", s2)
	results["tier2_shadow_off"] = s2["shadow"] == false
	results["tier2_glow_off"] = s2["glow"] == false
	results["tier2_quarter_trees"] = s2["trees"] == 12
	await _grab("res://shots/perf_tier2_low.png")
	# The quality button must sit on screen in the bottom bar.
	var vp := get_viewport().get_visible_rect().size
	var qb: Button = game.get("quality_button")
	var qrect := qb.get_global_rect()
	results["quality_button_onscreen"] = qrect.position.x >= 0.0 and qrect.position.y > vp.y * 0.5 and qrect.end.x <= vp.x and qrect.end.y <= vp.y
	results["quality_button_label"] = "低" in qb.text
	print("PROBE_PERF quality_rect=", qrect, " vp=", vp)
	print("PROBE_PERF llvmpipe_fps_avg=", float(game.get("_perf_fps_avg")), " (software renderer only, not a phone number)")
	print("PROBE_PERF SUMMARY ", results)
	_beat("summary_printed")
	_beat("done")
	get_tree().quit()
