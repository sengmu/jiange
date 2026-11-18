extends SceneTree
## Headless functional harness for the Jiange 3D full-map build, stage 1
## (full map / hero select with 22-hero roster / 20 waves + boss chain /
## training zone). Recorded assertions only (no bare assert). Exit code
## 0 = all checks pass.
## Scenario setups that place units, set gold, drain the spawn queue or
## pre-damage the core are mechanism probes routed through the game's own
## functions; they are logged as probes, not as human playtest evidence.
## Stage-1 note: per-test geometry was re-based to the full map (core at
## (-72,0,0), two lanes, hero home (-62,0,6)); range/state checks encode
## the new layout deliberately, mirroring the earlier camera-check
## precedent — no check was silently dropped.

var passed: int = 0
var failed: int = 0
var failures: Array = []


func check(check_name: String, condition: bool, detail: String = "") -> void:
	if condition:
		passed += 1
		print("PASS  ", check_name, ("  " + detail) if detail != "" else "")
	else:
		failed += 1
		failures.append(check_name)
		push_error("FAIL  " + check_name + "  " + detail)
		print("FAIL  ", check_name, "  ", detail)


func wait_until(callable: Callable, timeout_sec: float) -> bool:
	var waited := 0.0
	while waited < timeout_sec:
		if bool(callable.call()):
			return true
		await create_timer(0.1).timeout
		waited += 0.1
	return bool(callable.call())


# Review round 13 (P1-5): a ward-crystal cluster counts as colored only
# if at least one of its shard surfaces carries a saturated, non-white
# albedo — a plain white sphere fails this (max-min channel spread
# near zero / near-white sum).
func _sampled_albedo(node: Node) -> Color:
	# Swap (0.1.66): modeled pieces carry their tint on the first
	# descendant MeshInstance3D's surface override material.
	if node == null:
		return Color(-1, -1, -1)
	for mi in node.find_children("*", "MeshInstance3D", true, false):
		var m: Material = (mi as MeshInstance3D).get_surface_override_material(0)
		if m == null:
			m = (mi as MeshInstance3D).material_override
		if m is StandardMaterial3D:
			return (m as StandardMaterial3D).albedo_color
	return Color(-1, -1, -1)

func _cluster_is_colored(root: Node) -> bool:
	if root == null:
		return false
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		for s in mi.mesh.get_surface_count():
			var m := mi.get_surface_override_material(s)
			if m is StandardMaterial3D:
				var c: Color = (m as StandardMaterial3D).albedo_color
				var mx := maxf(maxf(c.r, c.g), c.b)
				var mn := minf(minf(c.r, c.g), c.b)
				if mx - mn > 0.15 and c.r + c.g + c.b < 2.7:
					return true
	return false


func _initialize() -> void:
	_run()


func _make_game() -> Node:
	var packed: PackedScene = load("res://scenes/main.tscn")
	if packed == null:
		return null
	var game: Node = packed.instantiate()
	root.add_child(game)
	return game


# Probe helper: spawn everything left in the queue at once and kill every
# living enemy through the real damage pipeline until the wave resolves
# into intermission (or victory/defeat). Returns the end state.
func _clear_current_wave(game: Node) -> String:
	var guard := 0
	while guard < 400:
		if String(game.get("game_state")) != "battle":
			return String(game.get("game_state"))
		while not (game.get("spawn_queue") as Array).is_empty():
			game.call("_spawn_from_queue")
		for e in game.get("enemies"):
			if is_instance_valid(e) and bool(e.get("alive")):
				game.call("apply_damage", null, e, 9999.0, "harness_probe")
		await create_timer(0.15).timeout
		guard += 1
	return String(game.get("game_state"))


func _find_enemy(game: Node, archetype: String) -> Node:
	for e in game.get("enemies"):
		if is_instance_valid(e) and bool(e.get("alive")) and String(e.get("archetype")) == archetype:
			return e
	return null


# Mobile-round helpers: synthetic touch/mouse events fed through the game's
# own _unhandled_input (unit-level), plus a recursive button finder for
# the viewport-pipeline tap checks (skill / restart).
func _touch_event(index: int, pos: Vector2, pressed: bool) -> InputEventScreenTouch:
	var ev := InputEventScreenTouch.new()
	ev.index = index
	ev.position = pos
	ev.pressed = pressed
	return ev


func _drag_event(index: int, pos: Vector2, rel: Vector2) -> InputEventScreenDrag:
	var ev := InputEventScreenDrag.new()
	ev.index = index
	ev.position = pos
	ev.relative = rel
	return ev


func _mouse_button_event(button: MouseButton, pos: Vector2, pressed: bool) -> InputEventMouseButton:
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	ev.position = pos
	ev.pressed = pressed
	return ev


func _find_button(node: Node, text: String) -> Button:
	if node is Button and (node as Button).text == text:
		return node as Button
	for child in node.get_children():
		var found := _find_button(child, text)
		if found != null:
			return found
	return null


func _run() -> void:
	await process_frame
	print("== Jiange 3D full-map harness (stage 1) ==")
	print("Godot: ", Engine.get_version_info().get("string", "?"))

	# --- Test 1: project loads into hero select; selecting starts wave 1 ---
	var game := _make_game()
	check("scene_loads", game != null)
	if game == null:
		_finish()
		return
	await process_frame
	await process_frame
	check("initial_state_select", String(game.get("game_state")) == "select", "state=" + String(game.get("game_state")))
	check("roster_has_22_heroes", (game.get("HERO_ROSTER") as Array).size() == 22, "roster=" + str((game.get("HERO_ROSTER") as Array).size()))
	check("hidden_heroes_locked", bool(game.call("hero_is_locked", 9)) and bool(game.call("hero_is_locked", 11)) and bool(game.call("hero_is_locked", 14)))
	check("initial_gold_is_start", int(game.get("gold")) == 50, "gold=" + str(game.get("gold")))
	check("initial_core_hp_full", is_equal_approx(float(game.get("core_hp")), 520.0), "core_hp=" + str(game.get("core_hp")))
	check("message_hidden_while_select_panel_open", not (game.get("message_label") as Label).visible)
	# Unlock feedback must land inside the panel: the top message is
	# hidden while the select panel is open.
	(game.get("pw_edit") as LineEdit).text = "luboyan"
	game.call("_on_unlock_pressed")
	check("unlock_feedback_in_panel", String((game.get("hero_detail_label") as Label).text).contains("口令正确"))
	(game.get("pw_edit") as LineEdit).text = "wrong"
	game.call("_on_unlock_pressed")
	check("unlock_wrong_password_in_panel", String((game.get("hero_detail_label") as Label).text).contains("口令不对"))
	var selected_ok: bool = bool(game.call("select_hero", 4)) # 关兴
	check("select_hero_starts_run", selected_ok and String(game.get("game_state")) == "battle")
	check("message_shown_after_select", (game.get("message_label") as Label).visible)
	check("initial_wave_is_1", int(game.get("current_wave")) == 1, "wave=" + str(game.get("current_wave")))
	check("defenders_present", game.get("strategist") != null and game.get("general") != null)
	check("ten_build_pads_exist", (game.get("pads") as Array).size() == 10, "pads=" + str((game.get("pads") as Array).size()))
	check("wave1_queue_size", (game.get("spawn_queue") as Array).size() + int(game.get("spawned_count")) == 13, "queue=" + str((game.get("spawn_queue") as Array).size()))

	# --- Test 2: wave 1 spawns through the real spawn timer -----------------
	var spawned_ok: bool = await wait_until(func() -> bool: return int(game.call("alive_enemy_count")) >= 3, 10.0)
	check("wave_spawns_enemies", spawned_ok, "alive=" + str(game.call("alive_enemy_count")))

	# --- Test 3: articulated parts exist and animate while walking ---------
	var walker: Node = _find_enemy(game, "enemy")
	check("enemy_instance_found", walker != null)
	if walker != null:
		var hip_l: Node3D = walker.get_node_or_null("VisualRoot/HipL")
		var hip_r: Node3D = walker.get_node_or_null("VisualRoot/HipR")
		var shoulder_r: Node3D = walker.get_node_or_null("VisualRoot/TorsoPivot/ShoulderR")
		var weapon: Node3D = walker.get_node_or_null("VisualRoot/TorsoPivot/ShoulderR/WeaponPivot")
		check("articulated_parts_present", hip_l != null and hip_r != null and shoulder_r != null and weapon != null)
		if hip_l != null:
			var r0 := hip_l.rotation.x
			await create_timer(0.35).timeout
			var r1 := hip_l.rotation.x
			check("walk_leg_swing_animates", absf(r1 - r0) > 0.02, "hip_rot %.3f -> %.3f" % [r0, r1])

	# --- Test 4: chain lightning hits >= 3 through the real skill path -----
	var chain_ready: bool = await wait_until(func() -> bool: return int(game.call("alive_enemy_count")) >= 4, 20.0)
	check("four_enemies_alive_for_chain", chain_ready, "alive=" + str(game.call("alive_enemy_count")))
	# Probe: on the full map the hero starts in the base, far from the
	# lanes; stage him at the plaza where both lanes converge.
	var strat_t4: Node = game.get("strategist")
	var t4_saved_max_hp := 0.0
	var t4_saved_hp := 0.0
	if strat_t4 != null:
		strat_t4.set("global_position", Vector3(30, 0, 0))
		# Staging armor: the wait below can run ~60 s of live combat at the
		# lane convergence; a normal-HP hero can die before the group forms
		# (cast then refuses with strategist_down). Buff, restore after.
		t4_saved_max_hp = float(strat_t4.get("max_hp"))
		t4_saved_hp = float(strat_t4.get("hp"))
		strat_t4.set("max_hp", 20000.0)
		strat_t4.set("hp", 20000.0)
	# Wait for a genuinely chainable group, not just any scout in range:
	# on the full map the approach walk is ~15 s and per-unit speed
	# variance can stretch same-lane spacing past the 9.0 jump distance,
	# so a lone first-contact cast legitimately hits only 1 (observed
	# flaky 1-hit casts). Require >= 3 foes inside 21 of the hero with
	# consecutive gaps <= 8.5 — then cast through the real skill path.
	var in_range: bool = await wait_until(func() -> bool:
		var strat: Node3D = game.get("strategist")
		if strat == null or not is_instance_valid(strat):
			return false
		var near: Array = []
		for e in game.get("enemies"):
			if is_instance_valid(e) and bool(e.get("alive")):
				var d := Vector2(e.global_position.x - strat.global_position.x, e.global_position.z - strat.global_position.z).length()
				if d < 21.0:
					near.append(e)
		if near.size() < 3:
			return false
		near.sort_custom(func(a: Node3D, b: Node3D) -> bool:
			var da := Vector2(a.global_position.x - strat.global_position.x, a.global_position.z - strat.global_position.z).length()
			var db := Vector2(b.global_position.x - strat.global_position.x, b.global_position.z - strat.global_position.z).length()
			return da < db)
		var gap1 := Vector2(near[1].global_position.x - near[0].global_position.x, near[1].global_position.z - near[0].global_position.z).length()
		var gap2 := Vector2(near[2].global_position.x - near[1].global_position.x, near[2].global_position.z - near[1].global_position.z).length()
		return gap1 <= 8.5 and gap2 <= 8.5, 60.0)
	check("enemy_inside_chain_range", in_range)
	var events_before := int(game.get("last_damage_events"))
	var hits := int(game.call("_cast_chain_lightning"))
	check("chain_hits_at_least_3", hits >= 3, "hits=" + str(hits))
	check("chain_recorded_hit_count", int(game.get("last_chain_hit_count")) >= 3, "recorded=" + str(game.get("last_chain_hit_count")))
	check("chain_damage_events_flowed", int(game.get("last_damage_events")) > events_before)
	if strat_t4 != null and is_instance_valid(strat_t4) and t4_saved_max_hp > 0.0:
		strat_t4.set("max_hp", t4_saved_max_hp)
		strat_t4.set("hp", minf(t4_saved_hp, t4_saved_max_hp))

	# --- Test 5: killing an enemy pays its bounty in gold -------------------
	# Probe: park the hero in a far corner so his new auto-attacks cannot
	# score an unrelated bounty kill between the gold read and the kill.
	var strat_t5: Node = game.get("strategist")
	if strat_t5 != null:
		strat_t5.set("global_position", Vector3(-80, 0, -40))
	var gold_before := int(game.get("gold"))
	var victim: Node = _find_enemy(game, "enemy")
	check("bounty_victim_found", victim != null)
	if victim != null:
		var bounty := int(game.call("bounty_for", String(victim.get("archetype"))))
		game.call("apply_damage", null, victim, 9999.0, "harness_probe")
		await process_frame
		check("gold_increases_on_kill", int(game.get("gold")) == gold_before + bounty, "gold %d -> %d (bounty %d)" % [gold_before, int(game.get("gold")), bounty])

	# --- Test 6 (probe): damage the core so the repair check has room -------
	game.call("damage_core", 200.0, null)
	check("core_damaged_for_repair", is_equal_approx(float(game.get("core_hp")), 320.0), "core_hp=" + str(game.get("core_hp")))

	# --- Test 7 (probe): clear wave 1 -> intermission, wave counter holds ---
	var end_state := await _clear_current_wave(game)
	check("wave1_clear_enters_intermission", end_state == "intermission", "state=" + end_state)
	check("wave_counter_stays_1_in_intermission", int(game.get("current_wave")) == 1)
	game.set("intermission_timer", 999.0) # probe: hold the intermission open

	# --- Test 8: repair core deducts gold and heals --------------------------
	game.set("gold", 300)
	var repaired: bool = bool(game.call("repair_core"))
	check("repair_returns_true", repaired)
	check("repair_deducts_gold", int(game.get("gold")) == 220, "gold=" + str(game.get("gold")))
	check("repair_heals_core", is_equal_approx(float(game.get("core_hp")), 480.0), "core_hp=" + str(game.get("core_hp")))

	# --- Test 9: build a thunder tower on pad 0 ------------------------------
	var towers_before := (game.get("towers") as Array).size()
	var built: bool = bool(game.call("build_tower", 0, "thunder"))
	check("build_thunder_returns_true", built)
	check("build_deducts_gold", int(game.get("gold")) == 100, "gold=" + str(game.get("gold")))
	check("build_registers_tower", (game.get("towers") as Array).size() == towers_before + 1, "towers=" + str((game.get("towers") as Array).size()))
	var pads_now: Array = game.get("pads")
	check("pad0_marked_occupied", pads_now[0].get("tower") != null)

	# --- Test 10: insufficient gold blocks the build, no deduction -----------
	game.set("gold", 50)
	var blocked: bool = bool(game.call("build_tower", 1, "flame"))
	check("build_insufficient_gold_blocked", not blocked)
	check("build_blocked_keeps_gold", int(game.get("gold")) == 50, "gold=" + str(game.get("gold")))
	check("pad1_still_empty", pads_now[1].get("tower") == null)
	game.set("gold", 500)
	var built_flame: bool = bool(game.call("build_tower", 1, "flame"))
	check("build_flame_after_topup", built_flame and int(game.get("gold")) == 400, "gold=" + str(game.get("gold")))

	# --- Test 11: next wave advances the counter 1 -> 2 -----------------------
	game.call("_on_next_wave_pressed")
	await process_frame
	check("next_wave_advances_counter", int(game.get("current_wave")) == 2 and String(game.get("game_state")) == "battle", "wave=" + str(game.get("current_wave")) + " state=" + String(game.get("game_state")))

	# --- Test 12: built towers actually deal damage ---------------------------
	var tower_dmg_ok: bool = await wait_until(func() -> bool: return int(game.get("built_tower_damage_events")) > 0, 30.0)
	check("built_tower_damage_registers", tower_dmg_ok, "events=" + str(game.get("built_tower_damage_events")))

	# --- Test 13 (probe): clear wave 2, jump to wave 3 for the archer --------
	end_state = await _clear_current_wave(game)
	check("wave2_clear_enters_intermission", end_state == "intermission", "state=" + end_state)
	game.set("intermission_timer", 999.0)
	game.call("_start_wave", 3)
	await process_frame
	var guard := 0
	while _find_enemy(game, "archer") == null and guard < 30:
		game.call("_spawn_from_queue")
		guard += 1
	var archer: Node = _find_enemy(game, "archer")
	check("archer_spawns_in_wave3", archer != null)
	if archer != null:
		check("archer_has_bow_parts", archer.get_node_or_null("VisualRoot/TorsoPivot/ShoulderL/BowUpper") != null and archer.get_node_or_null("VisualRoot/TorsoPivot/Quiver") != null)
		# Probe isolation: stop further spawns, clear everyone else, park
		# the hero far away, place the archer at bow range of the core
		# (11.5 < 13 range) on the full-map geometry.
		game.set("spawn_queue", [])
		for e in game.get("enemies"):
			if is_instance_valid(e) and bool(e.get("alive")) and e != archer:
				game.call("apply_damage", null, e, 9999.0, "harness_probe")
		var strat_t13: Node = game.get("strategist")
		if strat_t13 != null:
			strat_t13.set("global_position", Vector3(30, 0, -14))
		archer.set("global_position", Vector3(-60.5, 0, 2))
		await process_frame
		var gen: Node = game.get("general")
		var gen_hp_before := float(gen.get("hp"))
		var core_hp_before := float(game.get("core_hp"))
		var archer_hurt_someone: bool = await wait_until(func() -> bool:
			return float(gen.get("hp")) < gen_hp_before or float(game.get("core_hp")) < core_hp_before, 18.0)
		check("archer_deals_damage", archer_hurt_someone, "general_hp %.0f -> %.0f core %.0f -> %.0f" % [gen_hp_before, float(gen.get("hp")), core_hp_before, float(game.get("core_hp"))])
		var archer_pos_a: Vector3 = archer.get("global_position")
		await create_timer(1.0).timeout
		var archer_pos_b: Vector3 = archer.get("global_position")
		var dist_core := Vector2(-72.0 - archer_pos_b.x, 0.0 - archer_pos_b.z).length()
		check("archer_holds_position_at_range", archer_pos_a.distance_to(archer_pos_b) < 0.6 and dist_core >= 5.0, "moved %.2f dist_to_core %.1f" % [archer_pos_a.distance_to(archer_pos_b), dist_core])

	# --- Test 14 (probe): wave 5 siege beast spawns, is articulated, hits core
	for e in game.get("enemies"):
		if is_instance_valid(e) and bool(e.get("alive")):
			game.call("apply_damage", null, e, 9999.0, "harness_probe")
	game.call("_start_wave", 5)
	await process_frame
	guard = 0
	while _find_enemy(game, "beast") == null and guard < 40:
		game.call("_spawn_from_queue")
		guard += 1
	var beast: Node = _find_enemy(game, "beast")
	check("beast_spawns_in_wave5", beast != null)
	if beast != null:
		check("beast_is_big", float(beast.get("max_hp")) >= 500.0, "max_hp=" + str(beast.get("max_hp")))
		check("beast_has_four_legs_and_head", beast.get_node_or_null("VisualRoot/LegFL") != null and beast.get_node_or_null("VisualRoot/LegFR") != null and beast.get_node_or_null("VisualRoot/LegBL") != null and beast.get_node_or_null("VisualRoot/LegBR") != null and beast.get_node_or_null("VisualRoot/TorsoPivot/HeadPivot") != null)
		var leg_bl: Node3D = beast.get_node_or_null("VisualRoot/LegBL")
		if leg_bl != null:
			var lr0 := leg_bl.rotation.x
			await create_timer(0.4).timeout
			var lr1 := leg_bl.rotation.x
			check("beast_leg_animates", absf(lr1 - lr0) > 0.02, "leg_rot %.3f -> %.3f" % [lr0, lr1])
		# Probe: park the heroes far away, walk the beast onto the core.
		var strat: Node = game.get("strategist")
		var gen2: Node = game.get("general")
		strat.set("global_position", Vector3(30, 0, 14))
		gen2.set("global_position", Vector3(30, 0, -14))
		beast.set("global_position", Vector3(-66, 0, 1.0))
		var core_before_beast := float(game.get("core_hp"))
		var beast_hit_core: bool = await wait_until(func() -> bool: return float(game.get("core_hp")) <= core_before_beast - 26.0, 12.0)
		check("beast_damages_core", beast_hit_core, "core %.0f -> %.0f" % [core_before_beast, float(game.get("core_hp"))])

	# --- Test 15 (probe): wave 20 spawns the Three Simas in order; clearing
	# the final wave wins the game (stage-1: 上方谷 event is stage 2) -------
	game.call("_start_wave", 20)
	await process_frame
	var spawn_guard := 0
	while not (game.get("spawn_queue") as Array).is_empty() and spawn_guard < 80:
		game.call("_spawn_from_queue")
		spawn_guard += 1
	var sima_names: Array = game.get("bosses_spawned_names")
	check("wave20_boss_order_three_simas", sima_names.size() >= 3 and String(sima_names[sima_names.size() - 3]) == "司马昭" and String(sima_names[sima_names.size() - 2]) == "司马师" and String(sima_names[sima_names.size() - 1]) == "司马懿", "names=" + str(sima_names))
	end_state = await _clear_current_wave(game)
	check("win_after_wave20_cleared", end_state == "victory", "state=" + end_state)

	# --- Test 16: restart returns to hero select; reselecting resets ---------
	game.call("restart_game")
	await process_frame
	await process_frame
	check("restart_returns_to_select", String(game.get("game_state")) == "select", "state=" + String(game.get("game_state")))
	check("restart_wave_reset", int(game.get("current_wave")) == 1, "wave=" + str(game.get("current_wave")))
	var reselect_ok: bool = bool(game.call("select_hero", 4))
	check("restart_reselect_starts_battle", reselect_ok and String(game.get("game_state")) == "battle")
	check("restart_gold_reset", int(game.get("gold")) == 50, "gold=" + str(game.get("gold")))
	check("restart_core_hp_reset", is_equal_approx(float(game.get("core_hp")), 520.0))
	check("restart_towers_removed", (game.get("towers") as Array).size() == 2, "towers=" + str((game.get("towers") as Array).size()))
	var pads_reset: Array = game.get("pads")
	var all_pads_empty := true
	for p in pads_reset:
		if p.get("tower") != null:
			all_pads_empty = false
	check("restart_pads_cleared", all_pads_empty)
	check("restart_enemies_cleared", int(game.call("alive_enemy_count")) == 0)
	game.free()

	# --- Test 17 (probe): defeat path — enemy attacks a weakened core ---------
	var game3 := _make_game()
	await process_frame
	await process_frame
	game3.call("select_hero", 0)
	await process_frame
	game3.call("_spawn_enemy")
	await process_frame
	var probe_enemy: Node = _find_enemy(game3, "enemy")
	check("lose_probe_enemy_spawned", probe_enemy != null)
	if probe_enemy != null:
		probe_enemy.set("global_position", Vector3(-69.5, 0, 0.5))
		game3.call("damage_core", 517.0, null)
		check("core_weakened_by_pipeline", is_equal_approx(float(game3.get("core_hp")), 3.0), "core_hp=" + str(game3.get("core_hp")))
		var defeat_ok: bool = await wait_until(func() -> bool: return String(game3.get("game_state")) == "defeat", 9.0)
		check("defeat_state_reached", defeat_ok, "state=" + String(game3.get("game_state")) + " core_hp=" + str(game3.get("core_hp")))
	game3.free()

	# --- Test 18 (optimization round): HP bars, feedback, camera, preview ---
	var game4 := _make_game()
	await process_frame
	await process_frame
	game4.call("select_hero", 0)
	await process_frame
	game4.set("spawn_queue", []) # probe: freeze further spawns for isolation
	game4.call("_spawn_enemy")
	game4.call("_spawn_enemy")
	await process_frame
	var foes: Array = []
	for e in game4.get("enemies"):
		if is_instance_valid(e) and bool(e.get("alive")):
			foes.append(e)
	check("opt_two_foes_spawned", foes.size() >= 2, "foes=" + str(foes.size()))
	if foes.size() >= 2:
		var foe_a: Node = foes[0]
		var foe_b: Node = foes[1]
		var bar_a: Node3D = foe_a.get_node_or_null("HpBar")
		check("hpbar_node_exists", bar_a != null)
		await process_frame
		check("hpbar_hidden_at_full_hp", bar_a != null and not bar_a.visible)
		game4.call("apply_damage", null, foe_a, 20.0, "harness_probe")
		await process_frame
		await process_frame
		check("hpbar_visible_after_damage", bar_a != null and bar_a.visible)
		var fill_now := float(foe_a.get("hp_bar_fill"))
		var fill_want := float(foe_a.get("hp")) / float(foe_a.get("max_hp"))
		check("hpbar_fill_matches_hp", absf(fill_now - fill_want) < 0.03, "fill %.3f want %.3f" % [fill_now, fill_want])
	# Heroes show their bars even at full HP.
	var strat4: Node = game4.get("strategist")
	var strat_bar: Node3D = strat4.get_node_or_null("HpBar") if strat4 != null else null
	await process_frame
	check("hero_hpbar_always_visible", strat_bar != null and strat_bar.visible)
	# Selection ring tracks the strategist; move order shows the marker.
	# (Checked while both foes still live: once the field is empty the wave
	# clears into intermission, where the ring is hidden by design.)
	var ring4: Node3D = game4.get("selection_ring")
	await process_frame
	var ring_ok := false
	if ring4 != null and strat4 != null:
		var rd := Vector2(ring4.global_position.x - strat4.global_position.x, ring4.global_position.z - strat4.global_position.z).length()
		ring_ok = ring4.visible and rd < 0.6
	check("selection_ring_tracks_strategist", ring_ok)
	game4.call("_issue_move_order", Vector2(760, 420))
	await process_frame
	var marker4: Node3D = game4.get("move_marker")
	check("move_order_marker_shows", marker4 != null and marker4.visible)
	if foes.size() >= 2:
		var foe_a2: Node = foes[0]
		var foe_b2: Node = foes[1]
		# Bounty popup spawns on a kill.
		var popups_before := int(game4.get("bounty_popups_spawned"))
		game4.call("apply_damage", null, foe_b2, 9999.0, "harness_probe")
		await process_frame
		check("bounty_popup_spawns_on_kill", int(game4.get("bounty_popups_spawned")) == popups_before + 1, "popups %d -> %d" % [popups_before, int(game4.get("bounty_popups_spawned"))])
		# Death: fall + fade instead of instant vanish.
		game4.call("apply_damage", null, foe_a2, 9999.0, "harness_probe")
		await create_timer(1.15).timeout
		var foe_still_there := is_instance_valid(foe_a2)
		check("death_body_lingers_for_fade", foe_still_there)
		if foe_still_there:
			var vr: Node3D = foe_a2.get_node_or_null("VisualRoot")
			check("death_fall_tips_over", vr != null and absf(vr.rotation.x) > 0.8, "rot_x=" + (str(vr.rotation.x) if vr != null else "null"))
			check("death_fade_alpha_drops", float(foe_a2.call("death_fade_alpha")) < 0.9, "alpha=" + str(foe_a2.call("death_fade_alpha")))
	# Camera: zoom changes the transform, pan moves the target, reset restores.
	var cam4: Camera3D = game4.get("camera")
	var dist0 := float(game4.get("cam_dist"))
	var pos0: Vector3 = cam4.global_position
	game4.call("camera_zoom_by", 0.75)
	await process_frame
	check("camera_zoom_changes_view", float(game4.get("cam_dist")) < dist0 - 0.5 and cam4.global_position.distance_to(pos0) > 0.5, "dist %.1f -> %.1f" % [dist0, float(game4.get("cam_dist"))])
	var tgt0: Vector3 = game4.get("cam_target")
	game4.call("camera_pan_by", Vector3(3, 0, 2))
	await process_frame
	var tgt1: Vector3 = game4.get("cam_target")
	check("camera_pan_moves_target", absf(tgt1.x - tgt0.x - 3.0) < 0.01 and absf(tgt1.z - tgt0.z - 2.0) < 0.01, "target %s -> %s" % [str(tgt0), str(tgt1)])
	game4.call("reset_camera_view")
	await process_frame
	# Expected reset target updated in stage 1: the classic War3
	# south-camera framing now targets the full-map default
	# Vector3(-24, 0, 0) at distance 100 (was (1.9, 0, 2.0) / 64 on the
	# one-screen slice).
	check("camera_reset_restores", absf(float(game4.get("cam_dist")) - dist0) < 0.01 and (game4.get("cam_target") as Vector3).distance_to(Vector3(-24, 0, 0)) < 0.01)
	game4.free()

	# --- Test 19 (optimization round): chain feedback + wave preview --------
	var game5 := _make_game()
	await process_frame
	await process_frame
	game5.call("select_hero", 10) # 马谡 — the chain-lightning hero
	await process_frame
	var wave_lbl: Label = game5.get("wave_label")
	await process_frame
	check("battle_hud_shows_spawn_and_alive", wave_lbl != null and wave_lbl.text.contains("待出场") and wave_lbl.text.contains("场上"), "text=" + (wave_lbl.text if wave_lbl != null else "null"))
	game5.set("spawn_queue", []) # probe: exactly one enemy for the cast below
	game5.call("_spawn_enemy")
	await process_frame
	var lone: Node = _find_enemy(game5, "enemy")
	check("chain_lone_enemy_ready", lone != null)
	if lone != null:
		var strat5: Node3D = game5.get("strategist")
		lone.set("global_position", strat5.global_position + Vector3(6, 0, 0))
		game5.set("skill_cooldown", 0.0)
		var hits_one := int(game5.call("_cast_chain_lightning"))
		check("chain_single_target_casts", hits_one == 1, "hits=" + str(hits_one))
		check("chain_few_targets_feedback", String(game5.get("last_chain_feedback")) == "few_targets", "feedback=" + String(game5.get("last_chain_feedback")))
		var hits_cd := int(game5.call("_cast_chain_lightning"))
		check("chain_cooldown_feedback", hits_cd == 0 and String(game5.get("last_chain_feedback")) == "cooldown", "hits=" + str(hits_cd) + " feedback=" + String(game5.get("last_chain_feedback")))
	# Wave preview text must match the real next-wave queue composition.
	var q2: Array = game5.call("_build_wave_queue", 2)
	var q2_infantry := 0
	for k in q2:
		if String(k) == "infantry":
			q2_infantry += 1
	var preview2 := String(game5.call("wave_preview_text", 2))
	check("wave_preview_matches_queue", preview2.contains("×%d" % q2_infantry), "preview=" + preview2 + " queue_infantry=" + str(q2_infantry))
	var end5 := await _clear_current_wave(game5)
	check("opt_wave1_clear_intermission", end5 == "intermission", "state=" + end5)
	game5.set("intermission_timer", 999.0)
	await process_frame
	await process_frame
	var prev_lbl: Label = game5.get("wave_preview_label")
	check("intermission_preview_label_shows_next_wave", prev_lbl != null and prev_lbl.visible and prev_lbl.text.contains("下一波") and prev_lbl.text.contains("×%d" % q2_infantry), "text=" + (prev_lbl.text if prev_lbl != null else "null"))
	game5.free()

	# --- Test 20 (stage 1): unlock / hero stats / XP / skills / lanes /
	# wave-1 boss / training pen ------------------------------------------
	var game6 := _make_game()
	await process_frame
	await process_frame
	check("unlock_wrong_password_rejected", not bool(game6.call("try_unlock_hero", "wrongpw")))
	check("unlock_luboyan_opens_luxun", bool(game6.call("try_unlock_hero", "luboyan")) and not bool(game6.call("hero_is_locked", 9)))
	var sel_gs: bool = bool(game6.call("select_hero", 5)) # 关索 — generic str kit
	check("guansuo_selects", sel_gs)
	var gs_stats: Dictionary = game6.call("hero_stats_at", 5, 1)
	# 0.1.52 改判: HP 666.0 -> 992.0 (420+26*22); damage 31.1 unchanged.
	check("guansuo_stats_from_roster", is_equal_approx(float(gs_stats["hp"]), 992.0) and is_equal_approx(float(gs_stats["damage"]), 31.1), "hp=" + str(gs_stats["hp"]) + " dmg=" + str(gs_stats["damage"]))
	game6.call("hero_gain_xp", 95)
	check("xp_level_up_to_2", int(game6.get("hero_level")) == 2, "level=" + str(game6.get("hero_level")))
	var gs_stats2: Dictionary = game6.call("hero_stats_at", 5, 2)
	check("level2_damage_grows", is_equal_approx(float(gs_stats2["damage"]), 33.65), "dmg=" + str(gs_stats2["damage"]))
	game6.set("spawn_queue", [])
	game6.call("_spawn_enemy")
	await process_frame
	var gs_foe: Node = _find_enemy(game6, "enemy")
	check("generic_skill_foe_ready", gs_foe != null)
	if gs_foe != null:
		var strat6: Node = game6.get("strategist")
		gs_foe.set("global_position", strat6.global_position + Vector3(5, 0, 0))
		game6.set("skill_cooldown", 0.0)
		var gs_hits := int(game6.call("cast_hero_skill"))
		check("generic_str_skill_hits", gs_hits >= 1, "hits=" + str(gs_hits))
	game6.free()

	var game7 := _make_game()
	await process_frame
	await process_frame
	game7.call("select_hero", 10) # 马谡 — chain hero
	await process_frame
	# Probe: reset the queue deterministically before the timer can fire.
	game7.set("spawn_queue", game7.call("_build_wave_queue", 1))
	game7.set("spawned_count", 0)
	for i in range(4):
		game7.call("_spawn_from_queue")
	await process_frame
	var lane_foes: Array = []
	for e in game7.get("enemies"):
		if is_instance_valid(e) and bool(e.get("alive")):
			lane_foes.append(e)
	check("four_foes_for_lane_check", lane_foes.size() >= 4, "foes=" + str(lane_foes.size()))
	if lane_foes.size() >= 2:
		var f0: Node = lane_foes[0]
		var f1: Node = lane_foes[1]
		check("two_lanes_split_spawns", int(f0.get_meta("lane")) != int(f1.get_meta("lane")) and (f0.global_position.z < 0.0) != (f1.global_position.z < 0.0), "lane0=" + str(f0.get_meta("lane")) + " z0=" + str(f0.global_position.z) + " lane1=" + str(f1.get_meta("lane")) + " z1=" + str(f1.global_position.z))
	if lane_foes.size() >= 3:
		var strat7: Node = game7.get("strategist")
		var hp7: Vector3 = strat7.global_position
		lane_foes[0].set("global_position", hp7 + Vector3(8, 0, 0))
		lane_foes[1].set("global_position", hp7 + Vector3(14, 0, 0))
		lane_foes[2].set("global_position", hp7 + Vector3(20, 0, 0))
		game7.set("skill_cooldown", 0.0)
		var chain_hits := int(game7.call("cast_hero_skill"))
		check("masu_chain_skill_hits_3", chain_hits >= 3, "hits=" + str(chain_hits))
	var boss_guard := 0
	while _find_enemy(game7, "boss") == null and boss_guard < 6:
		game7.call("_spawn_from_queue")
		boss_guard += 1
	var boss1: Node = _find_enemy(game7, "boss")
	check("wave1_boss_spawns", boss1 != null)
	var names7: Array = game7.get("bosses_spawned_names")
	check("wave1_boss_is_hande", names7.size() >= 1 and String(names7[names7.size() - 1]) == "韩德", "names=" + str(names7))
	var strat7b: Node = game7.get("strategist")
	strat7b.set("global_position", Vector3(-52, 0, 33))
	# Stage 2: pens are paid rooms now — entering runs through the trainer.
	game7.set("gold", 500)
	check("trainer_brush_entry_test7", bool(game7.call("trainer_enter", "brush")) and int(game7.get("train_level")) == 1, "level=" + str(game7.get("train_level")))
	var trainee_ok: bool = await wait_until(func() -> bool: return (game7.get("trainees") as Array).size() >= 1, 4.0)
	check("training_pen_spawns", trainee_ok, "trainees=" + str((game7.get("trainees") as Array).size()))
	if trainee_ok:
		var tr: Node = (game7.get("trainees") as Array)[0]
		var gold7_before := int(game7.get("gold"))
		var xp7_before := int(game7.get("hero_xp"))
		game7.call("apply_damage", null, tr, 9999.0, "harness_probe")
		await process_frame
		check("trainee_kill_pays_gold_and_xp", int(game7.get("gold")) >= gold7_before + 4 and int(game7.get("hero_xp")) >= xp7_before + 4, "gold %d -> %d xp %d -> %d" % [gold7_before, int(game7.get("gold")), xp7_before, int(game7.get("hero_xp"))])
	game7.free()

	# --- Test 21 (mobile round): touch controls ---------------------------
	# Synthetic touch/mouse events are fed through the game's own
	# _unhandled_input; HUD button taps go through the real viewport input
	# pipeline via Input.parse_input_event (GUI first, as on device).
	var game8 := _make_game()
	await process_frame
	await process_frame
	game8.call("select_hero", 0)
	await process_frame
	var vp8 := game8.get_viewport().get_visible_rect().size
	var cam8: Camera3D = game8.get("camera")
	var strat8: Node = game8.get("strategist")
	var strat_screen := cam8.unproject_position(strat8.global_position + Vector3(0, 1.2, 0))
	# 21a tap on the strategist selects him (precondition: not selected).
	game8.set("selected", false)
	game8.call("_unhandled_input", _touch_event(0, strat_screen, true))
	game8.call("_unhandled_input", _touch_event(0, strat_screen, false))
	await process_frame
	check("touch_tap_selects_strategist", bool(game8.get("selected")), "screen=" + str(strat_screen) + " vp=" + str(vp8))
	# 21b single-finger drag pans the camera and issues no move order.
	var marker8: Node3D = game8.get("move_marker")
	marker8.visible = false
	var tgt8a: Vector3 = game8.get("cam_target")
	var drag_start := vp8 * Vector2(0.5, 0.45)
	game8.call("_unhandled_input", _touch_event(0, drag_start, true))
	for i in range(5):
		var p := drag_start + Vector2(30.0 * float(i + 1), 0)
		game8.call("_unhandled_input", _drag_event(0, p, Vector2(30, 0)))
	game8.call("_unhandled_input", _touch_event(0, drag_start + Vector2(150, 0), false))
	await process_frame
	var tgt8b: Vector3 = game8.get("cam_target")
	check("touch_drag_pans_camera", (tgt8b - tgt8a).length() > 0.5, "target %s -> %s" % [str(tgt8a), str(tgt8b)])
	check("touch_drag_issues_no_move_order", not marker8.visible)
	# 21c tap on empty ground with a hero selected issues a move order.
	game8.call("_unhandled_input", _touch_event(0, vp8 * Vector2(0.5, 0.5), true))
	game8.call("_unhandled_input", _touch_event(0, vp8 * Vector2(0.5, 0.5), false))
	await process_frame
	check("touch_tap_moves_selected_hero", marker8.visible)
	# 21d two-finger pinch zooms in (fingers spread -> distance shrinks).
	var dist8a := float(game8.get("cam_dist"))
	var f0 := vp8 * Vector2(0.35, 0.5)
	var f1 := vp8 * Vector2(0.65, 0.5)
	game8.call("_unhandled_input", _touch_event(0, f0, true))
	game8.call("_unhandled_input", _touch_event(1, f1, true))
	game8.call("_unhandled_input", _drag_event(0, vp8 * Vector2(0.30, 0.5), Vector2(-64, 0)))
	game8.call("_unhandled_input", _drag_event(1, vp8 * Vector2(0.70, 0.5), Vector2(64, 0)))
	await process_frame
	var dist8b := float(game8.get("cam_dist"))
	check("touch_pinch_zooms", dist8b < dist8a - 0.5, "dist %.1f -> %.1f" % [dist8a, dist8b])
	# 21e after one pinch finger lifts, the remaining finger drags again.
	game8.call("_unhandled_input", _touch_event(1, vp8 * Vector2(0.70, 0.5), false))
	var tgt8c: Vector3 = game8.get("cam_target")
	var resume_pos := vp8 * Vector2(0.30, 0.5) + Vector2(40, 0)
	game8.call("_unhandled_input", _drag_event(0, resume_pos, Vector2(40, 0)))
	game8.call("_unhandled_input", _touch_event(0, resume_pos, false))
	await process_frame
	var tgt8d: Vector3 = game8.get("cam_target")
	check("touch_after_pinch_drag_resumes_pan", (tgt8d - tgt8c).length() > 0.5, "target %s -> %s" % [str(tgt8c), str(tgt8d)])
	# 21f desktop paths still work: right-click move + wheel zoom.
	marker8.visible = false
	game8.call("_unhandled_input", _mouse_button_event(MOUSE_BUTTON_RIGHT, vp8 * Vector2(0.55, 0.5), true))
	game8.call("_unhandled_input", _mouse_button_event(MOUSE_BUTTON_RIGHT, vp8 * Vector2(0.55, 0.5), false))
	await process_frame
	check("mouse_right_click_move_still_works", marker8.visible)
	var dist8c := float(game8.get("cam_dist"))
	game8.call("_unhandled_input", _mouse_button_event(MOUSE_BUTTON_WHEEL_UP, vp8 * Vector2(0.5, 0.5), true))
	await process_frame
	check("mouse_wheel_zoom_still_works", float(game8.get("cam_dist")) < dist8c - 0.5, "dist %.1f -> %.1f" % [dist8c, float(game8.get("cam_dist"))])
	# 21g HUD button taps are NOT checked here: headless --script mode does
	# not dispatch injected input to GUI at all (verified 2026-11-13 with a
	# minimal Button probe: both Input.parse_input_event and
	# Viewport.push_input leave pressed=false, for mouse as well as touch).
	# Button taps are instead covered by scripts/probe_touch.gd under xvfb,
	# where a real window exists and the viewport pipeline works.
	game8.free()

	# --- Test 22 (mobile round): screen & posture -------------------------
	# Safe area is ZERO on desktop/headless (no cutout); touch UI sizes
	# only switch on with --touch-ui (real phones report a touchscreen).
	var game9 := _make_game()
	await process_frame
	await process_frame
	var insets9: Vector4 = game9.call("_compute_safe_insets")
	check("safe_area_zero_on_desktop", insets9 == Vector4.ZERO, "insets=" + str(insets9))
	var forced_touch := "--touch-ui" in OS.get_cmdline_user_args()
	check("touch_ui_flag_matches_cmdline", bool(game9.call("_touch_ui_enabled")) == forced_touch, "touch_ui=" + str(game9.call("_touch_ui_enabled")) + " forced=" + str(forced_touch))
	var skill9: Button = game9.get("skill_button")
	# The bottom bar must really sit on screen (a negative off-screen
	# rect would pass a bare end.y test — caught 2026-11-13), and the
	# message label must stay centered at the top.
	var vp9 := game9.get_viewport().get_visible_rect().size
	var srect9 := skill9.get_global_rect()
	if not forced_touch:
		check("skill_button_onscreen_bottom", srect9.position.y > vp9.y * 0.5 and vp9.y - srect9.end.y <= 22.0, "rect=" + str(srect9) + " vp=" + str(vp9))
	var mrect9 := (game9.get("message_label") as Label).get_global_rect()
	check("message_label_centered", absf(mrect9.position.x - (vp9.x - 640.0) / 2.0) < 2.0, "rect=" + str(mrect9) + " vp=" + str(vp9))
	if forced_touch:
		# Layout revamp (2026-11-14): the bar skill button retires in
		# touch mode; the big round button is the skill control now.
		var big9: Button = game9.get("_big_skill_button")
		var brect9 := big9.get_global_rect()
		check("touch_big_skill_onscreen_right", big9 != null and brect9.position.x > vp9.x * 0.5 and vp9.x - brect9.end.x <= 26.0 and vp9.y - brect9.end.y <= 110.0, "rect=" + str(brect9) + " vp=" + str(vp9))
		check("touch_bottom_skill_retired", not skill9.is_visible_in_tree())
		check("touch_repair_in_action_column", (game9.get("repair_button") as Button).get_global_rect().position.x > vp9.x * 0.55)
		check("touch_inv_centered", absf((game9.get("inv_row") as HBoxContainer).get_global_rect().get_center().x - vp9.x / 2.0) < 30.0)
		var inv_rect9 := (game9.get("inv_row") as HBoxContainer).get_global_rect()
		var minimap_rect9 := (game9.get("_minimap") as Control).get_global_rect()
		var action_rect9 := (game9.get("_action_col") as Control).get_global_rect()
		check("geo_banner_clear_of_minimap", not mrect9.grow(4.0).intersects(minimap_rect9), "banner=" + str(mrect9) + " minimap=" + str(minimap_rect9))
		check("geo_skill_clear_of_inv", not brect9.grow(4.0).intersects(inv_rect9), "skill=" + str(brect9) + " inv=" + str(inv_rect9))
		check("geo_action_col_clear_of_inv", not action_rect9.grow(4.0).intersects(inv_rect9), "action=" + str(action_rect9) + " inv=" + str(inv_rect9))
		check("touch_skill_button_taller", skill9.custom_minimum_size.y >= 64.0, "h=" + str(skill9.custom_minimum_size.y))
		check("touch_bottom_bar_raised", is_equal_approx((game9.get("bottom_bar") as HBoxContainer).offset_top, -82.0), "offset_top=" + str((game9.get("bottom_bar") as HBoxContainer).offset_top))
		var grid9: Button = (game9.get("hero_buttons") as Array)[0]
		check("touch_hero_grid_taller", grid9.custom_minimum_size.y >= 56.0, "h=" + str(grid9.custom_minimum_size.y))
		check("touch_select_panel_wider", (game9.get("select_panel") as PanelContainer).custom_minimum_size.x >= 900.0, "w=" + str((game9.get("select_panel") as PanelContainer).custom_minimum_size.x))
	else:
		check("desktop_skill_button_height", is_equal_approx(skill9.custom_minimum_size.y, 46.0), "h=" + str(skill9.custom_minimum_size.y))
		check("desktop_bottom_bar_position", is_equal_approx((game9.get("bottom_bar") as HBoxContainer).offset_top, -64.0), "offset_top=" + str((game9.get("bottom_bar") as HBoxContainer).offset_top))
	# --- Test 23 (mobile round): performance tiers + FPS guard -----------
	# Tier 0 高：shadows + glow + all 61 trees (45 field + 16 forest,
	# added by the 2026-11-14 map-completion round). Tier 1 中：no
	# shadows, no glow, every 2nd tree (31 visible). Tier 2 低：every
	# 4th tree (16 visible). The FPS guard auto-steps down after 3
	# consecutive 2s windows below 28fps; a manual tier set disables it.
	var gameA := _make_game()
	await process_frame
	await process_frame
	check("perf_default_high", int(gameA.get("quality_tier")) == 0, "tier=" + str(gameA.get("quality_tier")))
	check("perf_sun_shadow_on", bool((gameA.get("sun_light") as DirectionalLight3D).shadow_enabled), "shadow on at tier 0")
	check("perf_glow_on", bool((gameA.get("env_ref") as Environment).glow_enabled), "glow on at tier 0")
	var veg_total := int((gameA.get("vegetation_nodes") as Array).size())
	check("perf_vegetation_count", veg_total == 61, "n=" + str(veg_total))
	check("perf_all_trees_visible", int(gameA.call("count_visible_vegetation")) == veg_total, "visible=" + str(int(gameA.call("count_visible_vegetation"))))
	gameA.call("set_quality_tier", 1)
	check("perf_mid_shadow_off", not bool((gameA.get("sun_light") as DirectionalLight3D).shadow_enabled), "shadow off at tier 1")
	check("perf_mid_glow_off", not bool((gameA.get("env_ref") as Environment).glow_enabled), "glow off at tier 1")
	check("perf_mid_half_trees", int(gameA.call("count_visible_vegetation")) == 31, "visible=" + str(int(gameA.call("count_visible_vegetation"))))
	gameA.call("set_quality_tier", 2)
	check("perf_low_quarter_trees", int(gameA.call("count_visible_vegetation")) == 16, "visible=" + str(int(gameA.call("count_visible_vegetation"))))
	# Brightness compensation (2026-11-15): glow-off tiers buy the
	# light back via exposure + ambient, and render at a lower
	# internal scale; tier 0 restores the exact baseline values.
	check("perf_low_brightness_comp", float((gameA.get("env_ref") as Environment).tonemap_exposure) > 1.40 and float((gameA.get("env_ref") as Environment).ambient_light_energy) > 1.10, "exp=" + str(float((gameA.get("env_ref") as Environment).tonemap_exposure)))
	check("perf_low_render_scale", is_equal_approx(gameA.get_viewport().scaling_3d_scale, 0.70), "scale=" + str(gameA.get_viewport().scaling_3d_scale))
	gameA.call("set_quality_tier", 0)
	check("perf_back_to_high", int(gameA.call("count_visible_vegetation")) == veg_total and bool((gameA.get("sun_light") as DirectionalLight3D).shadow_enabled), "restored tier 0")
	check("perf_high_baseline_restored", is_equal_approx(float((gameA.get("env_ref") as Environment).tonemap_exposure), 0.88) and is_equal_approx(gameA.get_viewport().scaling_3d_scale, 1.0), "baseline restored at tier 0")
	check("perf_quality_button", gameA.get("quality_button") != null and "画质" in (gameA.get("quality_button") as Button).text, "text=" + str((gameA.get("quality_button") as Button).text))
	check("perf_fps_label", gameA.get("fps_label") != null, "fps label present in HUD")
	# Safe-area regression (2026-11-13): under Xvfb the display safe
	# area is the whole X screen (1280x1024) while the window is
	# 1280x720 — the raw bottom inset goes -304 and pushes the bottom
	# bar off-screen. Insets must never be negative.
	var insetsA: Vector4 = gameA.call("_compute_safe_insets")
	check("perf_safe_insets_nonnegative", insetsA.x >= 0.0 and insetsA.y >= 0.0 and insetsA.z >= 0.0 and insetsA.w >= 0.0, "insets=" + str(insetsA))
	gameA.free()
	# Auto step-down needs a fresh instance: any manual set_quality_tier
	# on gameA above disabled its guard by design.
	var gameB := _make_game()
	await process_frame
	await process_frame
	for i in range(255):
		gameB.call("_perf_sample", 0.05) # 2 warmup windows + 3 low windows x 2s at 20fps, margin for float drift
	check("perf_auto_stepdown", int(gameB.get("quality_tier")) == 1, "tier=" + str(gameB.get("quality_tier")) + " fps_avg=" + str(float(gameB.get("_perf_fps_avg"))))
	check("perf_auto_message", "自动降为" in String((gameB.get("message_label") as Label).text), "msg=" + String((gameB.get("message_label") as Label).text))
	# Manual set locks the tier: more low-fps windows must not drop it.
	gameB.call("set_quality_tier", 1)
	for i in range(200):
		gameB.call("_perf_sample", 0.05) # 5 more windows at 20fps
	check("perf_manual_blocks_auto", int(gameB.get("quality_tier")) == 1, "tier=" + str(gameB.get("quality_tier")))
	gameB.call("_on_quality_button_pressed")
	check("perf_button_cycles", int(gameB.get("quality_tier")) == 2, "tier=" + str(gameB.get("quality_tier")))
	check("perf_button_label_updates", "低" in (gameB.get("quality_button") as Button).text, "text=" + str((gameB.get("quality_button") as Button).text))
	gameB.free()
	# dynamic resolution + UI-A theme checks (2026-11-15)
	var gameDyn := _make_game()
	await process_frame
	await process_frame
	gameDyn.call("set_quality_tier", 0)
	check("dyn_default_offset_zero", is_equal_approx(float(gameDyn.get("_dyn_scale")), 0.0) and is_equal_approx(gameDyn.get_viewport().scaling_3d_scale, 1.0), "offset=" + str(gameDyn.get("_dyn_scale")) + " scale=" + str(gameDyn.get_viewport().scaling_3d_scale))
	check("uia_core_fill_purple", (gameDyn.get("core_bar_fill_style") as StyleBoxFlat).bg_color.is_equal_approx(Color(0.608, 0.302, 1.0)), "full core HP fill is purple")
	check("uia_emblem_exists", gameDyn.get("hero_emblem_label") != null, "hero emblem label exists")
	check("uia_hud_panel_ink", ((gameDyn.get("hud_panel") as PanelContainer).get_theme_stylebox("panel") as StyleBoxFlat).bg_color.is_equal_approx(Color(0.090, 0.071, 0.031, 0.88)), "HUD panel uses ink background")
	for dyn_warmup_frame in range(144):
		gameDyn._perf_sample(1.0 / 35.0)
	check("dyn_warmup_no_step", is_equal_approx(gameDyn.get_viewport().scaling_3d_scale, 1.0), "scale=" + str(gameDyn.get_viewport().scaling_3d_scale))
	for dyn_down_first_frame in range(72):
		gameDyn._perf_sample(1.0 / 35.0)
	check("dyn_step_down_1", is_equal_approx(gameDyn.get_viewport().scaling_3d_scale, 0.95), "scale=" + str(gameDyn.get_viewport().scaling_3d_scale))
	for dyn_down_second_frame in range(72):
		gameDyn._perf_sample(1.0 / 35.0)
	check("dyn_step_down_2", is_equal_approx(gameDyn.get_viewport().scaling_3d_scale, 0.90), "scale=" + str(gameDyn.get_viewport().scaling_3d_scale))
	for dyn_floor_high_frame in range(216):
		gameDyn._perf_sample(1.0 / 35.0)
	check("dyn_floor_clamp_tier0", is_equal_approx(gameDyn.get_viewport().scaling_3d_scale, 0.85), "scale=" + str(gameDyn.get_viewport().scaling_3d_scale))
	# Rev 3 (程序化残件替换轮) test-design fix: the flush block was
	# 122 calls — flush+first (244 calls of 1/60) overshoots the close
	# of the mixed transition window plus one clean window, so the
	# recover step lands one window BEFORE the needs-2-windows check
	# whenever the floor phase's leftover window fill F < 0.4 s (the
	# mixed window then averages >55 and counts). With flush = 60 the
	# pre-check feed is 182 calls (3.03 s): window 2 cannot have
	# closed-and-counted for any F, and exactly one step has landed
	# by the step check for any F. Expectations unchanged.
	for dyn_recover_flush_frame in range(60):
		gameDyn._perf_sample(1.0 / 60.0)
	for dyn_recover_first_frame in range(122):
		gameDyn._perf_sample(1.0 / 60.0)
	check("dyn_recover_needs_2_windows", is_equal_approx(gameDyn.get_viewport().scaling_3d_scale, 0.85), "scale=" + str(gameDyn.get_viewport().scaling_3d_scale))
	for dyn_recover_second_frame in range(122):
		gameDyn._perf_sample(1.0 / 60.0)
	for dyn_recover_third_frame in range(122):
		gameDyn._perf_sample(1.0 / 60.0)
	check("dyn_recover_step", is_equal_approx(gameDyn.get_viewport().scaling_3d_scale, 0.90), "scale=" + str(gameDyn.get_viewport().scaling_3d_scale))
	for dyn_recover_base_frame in range(488):
		gameDyn._perf_sample(1.0 / 60.0)
	check("dyn_recover_to_base", is_equal_approx(gameDyn.get_viewport().scaling_3d_scale, 1.0) and is_equal_approx(float(gameDyn.get("_dyn_scale")), 0.0), "offset=" + str(gameDyn.get("_dyn_scale")) + " scale=" + str(gameDyn.get_viewport().scaling_3d_scale))
	gameDyn.call("set_quality_tier", 1)
	check("dyn_manual_reset", is_equal_approx(float(gameDyn.get("_dyn_scale")), 0.0) and is_equal_approx(gameDyn.get_viewport().scaling_3d_scale, 0.85), "offset=" + str(gameDyn.get("_dyn_scale")) + " scale=" + str(gameDyn.get_viewport().scaling_3d_scale))
	gameDyn.call("set_quality_tier", 2)
	for dyn_floor_low_frame in range(288):
		gameDyn._perf_sample(1.0 / 35.0)
	check("dyn_floor_tier2", is_equal_approx(gameDyn.get_viewport().scaling_3d_scale, 0.60), "scale=" + str(gameDyn.get_viewport().scaling_3d_scale))
	gameDyn.free()
	game9.free()

	# --- Test 24 (stage 1 选将系统): all 22 heroes vs TEARDOWN §3 --------
	# Roster data pinned verbatim (birth [str,agi,int], growth, move speed);
	# 马谡 birth per PARITY §3 note (15/14/22, doc unlisted, 待校准).
	# Then every hero is selected and casts through the real skill path.
	var gameC := _make_game()
	await process_frame
	await process_frame
	var expect24: Array = [
		["zhaotong", [18, 21, 13], [2.2, 2.2, 1.6], 320],
		["zhaoguang", [18, 19, 15], [2.1, 2.3, 1.6], 320],
		["menghuo", [25, 14, 13], [3.0, 1.6, 1.4], 270],
		["jiangwei", [17, 15, 21], [2.0, 1.5, 2.5], 270],
		["guanxing", [19, 23, 16], [2.2, 2.2, 1.6], 320],
		["guansuo", [26, 14, 13], [3.0, 1.65, 1.35], 300],
		["guanfeng", [19, 23, 16], [2.1, 2.15, 1.75], 320],
		["zhangbao", [26, 13, 13], [3.2, 1.5, 1.3], 320],
		["wangping", [22, 13, 17], [2.7, 1.5, 1.8], 320],
		["luxun", [15, 15, 22], [2.0, 1.7, 2.3], 300],
		["masu", [15, 14, 22], [2.0, 1.0, 3.0], 300],
		["muludawang", [21, 17, 16], [3.2, 2.3, 2.4], 280],
		["huangyueying", [17, 14, 22], [1.8, 1.0, 3.2], 270],
		["xiahhouba", [22, 18, 17], [2.5, 1.7, 1.8], 280],
		["liuchen", [22, 15, 15], [3.1, 1.5, 1.4], 270],
		["jiangwan", [16, 14, 23], [2.0, 1.0, 3.0], 270],
		["zhugezhan", [14, 17, 19], [1.8, 1.0, 3.2], 270],
		["huaman", [18, 19, 15], [1.9, 2.3, 1.8], 320],
		["liaohua", [20, 16, 16], [2.7, 1.5, 1.8], 270],
		["zhurong", [18, 19, 15], [2.0, 2.2, 1.8], 330],
		["madai", [18, 22, 12], [2.3, 2.3, 1.4], 320],
		["mazhong", [19, 20, 16], [2.0, 2.2, 1.6], 320],
	]
	check("roster_select_buttons_22", (gameC.get("hero_buttons") as Array).size() == 22, "buttons=" + str((gameC.get("hero_buttons") as Array).size()))
	var attrs_ok_ar := true
	var attrs_bad_ar := ""
	for i_ar in range(22):
		var b_attr_ar: Button = (gameC.get("hero_buttons") as Array)[i_ar]
		var al_ar := b_attr_ar.get_node_or_null("HeroAttrs") as Label
		if al_ar == null:
			attrs_ok_ar = false
			attrs_bad_ar = "card %d missing HeroAttrs" % i_ar
		else:
			var st_ar: Dictionary = gameC.call("hero_stats_at", i_ar, 1)
			var exp_ar := "攻 %d · 防 %.1f" % [int(float(st_ar["damage"])), float(st_ar["armor"])]
			if al_ar.text != exp_ar:
				attrs_ok_ar = false
				attrs_bad_ar = "card %d attrs '%s' != '%s'" % [i_ar, al_ar.text, exp_ar]
	check("select_card_attr_row_all_22", attrs_ok_ar, attrs_bad_ar)
	check("hidden_locked_before_unlock", bool(gameC.call("hero_is_locked", 9)) and bool(gameC.call("hero_is_locked", 11)) and bool(gameC.call("hero_is_locked", 14)))
	var lock_btn24: Button = (gameC.get("hero_buttons") as Array)[9]
	check("locked_button_shows_lock", "锁" in lock_btn24.text, "text=" + lock_btn24.text)
	check("select_locked_hero_rejected", not bool(gameC.call("select_hero", 9)))
	check("unlock_luboyan_opens_luxun", bool(gameC.call("try_unlock_hero", "luboyan")) and not bool(gameC.call("hero_is_locked", 9)))
	check("unlock_muludawang_opens", bool(gameC.call("try_unlock_hero", "muludawang")) and not bool(gameC.call("hero_is_locked", 11)))
	check("unlock_beidiwang_opens_liuchen", bool(gameC.call("try_unlock_hero", "beidiwang")) and not bool(gameC.call("hero_is_locked", 14)))
	check("locked_button_unlocked_after_pw", not ("锁" in ((gameC.get("hero_buttons") as Array)[9] as Button).text))
	var data_ok24 := true
	var data_bad24 := ""
	var detail_ok24 := true
	var detail_bad24 := ""
	var full_skills24: Array = []
	var roster24: Array = gameC.get("HERO_ROSTER")
	for i in range(22):
		var h24: Dictionary = roster24[i]
		var e24: Array = expect24[i]
		if String(h24["id"]) != String(e24[0]):
			data_ok24 = false
			data_bad24 = "id %d %s != %s" % [i, String(h24["id"]), String(e24[0])]
		var b24: Array = h24["birth"]
		var g24: Array = h24["growth"]
		var eb24: Array = e24[1]
		var eg24: Array = e24[2]
		for k in range(3):
			if int(b24[k]) != int(eb24[k]) or not is_equal_approx(float(g24[k]), float(eg24[k])):
				data_ok24 = false
				data_bad24 = "%s birth/growth mismatch k=%d" % [String(h24["id"]), k]
		if int(h24["speed"]) != int(e24[3]):
			data_ok24 = false
			data_bad24 = "%s speed %d != %d" % [String(h24["id"]), int(h24["speed"]), int(e24[3])]
		if String(h24["kit"]) == "full":
			full_skills24.append(String(h24["skill"]))
		var dt24 := String(gameC.call("_hero_detail_text", i))
		var want_note24 := "完整技能" if String(h24["kit"]) == "full" else "通用技能件"
		if not dt24.contains(String(h24["skill_name"])) or not dt24.contains(want_note24):
			detail_ok24 = false
			detail_bad24 = "%s detail missing skill/note" % String(h24["id"])
	check("roster_data_matches_teardown", data_ok24, data_bad24)
	check("detail_labels_kit_per_hero", detail_ok24, detail_bad24)
	full_skills24.sort()
	check("six_distinct_full_skills", full_skills24.size() == 22, "full=" + str(full_skills24))
	# Sweep: select each hero, cast the real skill at staged foes, restart.
	var sweep_ok24 := true
	var sweep_bad24 := ""
	for i in range(22):
		if not bool(gameC.call("select_hero", i)):
			sweep_ok24 = false
			sweep_bad24 = "select %d failed" % i
			break
		await process_frame
		var stratC: Node = gameC.get("strategist")
		if stratC == null or int(stratC.get_meta("hero_index")) != i:
			sweep_ok24 = false
			sweep_bad24 = "strategist meta %d != %d" % [int(stratC.get_meta("hero_index")) if stratC != null else -1, i]
			break
		gameC.set("spawn_queue", [])
		for k in range(3):
			gameC.call("_spawn_enemy")
		await process_frame
		var foesC: Array = []
		for e in gameC.get("enemies"):
			if is_instance_valid(e) and bool(e.get("alive")):
				foesC.append(e)
		var hpC: Vector3 = stratC.global_position
		for k in range(mini(3, foesC.size())):
			(foesC[k] as Node).set("global_position", hpC + Vector3(5.0 + 6.0 * float(k), 0, 0))
		gameC.set("skill_cooldown", 0.0)
		var hitsC := int(gameC.call("cast_hero_skill"))
		if hitsC < 1 or String(gameC.get("last_chain_feedback")) != "ok":
			sweep_ok24 = false
			sweep_bad24 = "cast %d %s hits=%d fb=%s" % [i, String(roster24[i]["name"]), hitsC, String(gameC.get("last_chain_feedback"))]
			break
		gameC.call("restart_game")
		await process_frame
		await process_frame
	check("all_22_heroes_select_and_cast", sweep_ok24, sweep_bad24)
	gameC.free()

	# --- Test 25 (stage 1 隐藏英雄口令解锁): PARITY §3/§9 ----------------
	# Mechanism: 陆逊 luboyan / 木鹿大王 muludawang / 刘谌 beidiwang, locked
	# at start, password entry in the select panel unlocks. Difficulty note:
	# the 3D build has no difficulty selection at all (grep: no "difficulty"
	# in scripts/, scenes/, project.godot), so the password path is
	# unconditional — consistent with PARITY §9 "全难度可输口令"; the
	# original's difficulty association remains unexamined (PARITY: 待校准),
	# nothing to gate here.
	var gameD := _make_game()
	await process_frame
	await process_frame
	var hidden_idx25: Array = [9, 11, 14]
	var all_locked25 := true
	var others_unlocked25 := true
	for i in range(22):
		var locked25 := bool(gameD.call("hero_is_locked", i))
		if i in hidden_idx25:
			if not locked25:
				all_locked25 = false
		elif locked25:
			others_unlocked25 = false
	check("hidden_all_three_locked_initial", all_locked25)
	check("hidden_others_unlocked_initial", others_unlocked25)
	var refuse_ok25 := true
	for i in hidden_idx25:
		if bool(gameD.call("select_hero", i)):
			refuse_ok25 = false
	check("hidden_select_refused_all_three", refuse_ok25)
	var btn_lock_ok25 := true
	for i in hidden_idx25:
		var b25: Button = (gameD.get("hero_buttons") as Array)[i]
		if not b25.disabled or not ("锁" in b25.text):
			btn_lock_ok25 = false
	check("hidden_buttons_disabled_and_marked", btn_lock_ok25)
	check("unlock_wrong_password_rejected", not bool(gameD.call("try_unlock_hero", "luboyanx")) and bool(gameD.call("hero_is_locked", 9)))
	check("unlock_empty_password_rejected", not bool(gameD.call("try_unlock_hero", "")) and not bool(gameD.call("try_unlock_hero", "   ")))
	check("unlock_case_space_insensitive", bool(gameD.call("try_unlock_hero", " LUBOYAN ")) and not bool(gameD.call("hero_is_locked", 9)))
	check("unlock_muludawang_mixed_case", bool(gameD.call("try_unlock_hero", "MuludaWang")) and not bool(gameD.call("hero_is_locked", 11)))
	check("unlock_beidiwang", bool(gameD.call("try_unlock_hero", "beidiwang")) and not bool(gameD.call("hero_is_locked", 14)))
	var btn_open_ok25 := true
	for i in hidden_idx25:
		var b25b: Button = (gameD.get("hero_buttons") as Array)[i]
		if b25b.disabled or ("锁" in b25b.text):
			btn_open_ok25 = false
	check("hidden_buttons_enabled_after_unlock", btn_open_ok25)
	check("unlock_repeat_idempotent", bool(gameD.call("try_unlock_hero", "luboyan")))
	# Explicit state-track: unlock survives restart_game (session-persistent;
	# the original asks the password once per game — here one entry unlocks
	# for the whole app session, a deliberate convenience, recorded in log).
	var sel11 := bool(gameD.call("select_hero", 11))
	await process_frame
	var stratD: Node = gameD.get("strategist")
	check("hidden_muludawang_select_after_unlock", sel11 and stratD != null and int(stratD.get_meta("hero_index")) == 11)
	gameD.call("restart_game")
	await process_frame
	await process_frame
	check("hidden_unlock_persists_across_restart", not bool(gameD.call("hero_is_locked", 9)) and not bool(gameD.call("hero_is_locked", 11)) and not bool(gameD.call("hero_is_locked", 14)))
	var sel14 := bool(gameD.call("select_hero", 14))
	await process_frame
	var stratD2: Node = gameD.get("strategist")
	check("hidden_liuchen_select_after_restart", sel14 and stratD2 != null and int(stratD2.get_meta("hero_index")) == 14)
	# --- Test 26 (stage 1 20 波＋Boss 链): TEARDOWN §4 / PARITY §4 ----------
	# Boss chain pinned verbatim: waves 1-10 per TEARDOWN §4 (wave 6 = the
	# three Zhang brothers), 11-19 per the PARITY §4 9-name assignment,
	# wave 20 = Three Simas in kill order 昭 -> 师 -> 懿. Scope note: this
	# item verifies the chain (identity / order / spawn / HP scaling /
	# preview / full-run win). Boss signature skills from TEARDOWN §4
	# (韩德临死玄冰咒, 张角天石术, 董卓七星刀抵挡, 王双烈焰刀分裂…)
	# are NOT implemented in 3D — bosses fight as scaled heavy infantry
	# (see _update_boss); that is a stage-2 follow-up, recorded in the
	# ledger, not claimed here. 邓艾 is unassigned by design: TEARDOWN's
	# late pool lists 10 names for 9 waves and PARITY + the 2D game both
	# use the 9-name assignment below (邓艾: 待校准).
	var gameE := _make_game()
	await process_frame
	await process_frame
	var expect26: Dictionary = {
		1: ["韩德"], 2: ["夏侯楙"], 3: ["华雄"], 4: ["王朗"], 5: ["郭淮"],
		6: ["张角", "张梁", "张宝"], 7: ["越吉元帅"], 8: ["雅丹丞相"],
		9: ["董卓"], 10: ["王双"], 11: ["徐晃"], 12: ["曹真"], 13: ["张郃"],
		14: ["夏侯霸"], 15: ["邓忠"], 16: ["许褚"], 17: ["张辽"], 18: ["曹操"],
		19: ["吕布"], 20: ["司马昭", "司马师", "司马懿"],
	}
	var table_ok26 := true
	var table_detail26 := ""
	var total_bosses26 := 0
	for w26 in range(1, 21):
		var got26: Array = []
		for b26 in gameE.call("bosses_for_wave", w26):
			got26.append(String(b26["name"]))
		total_bosses26 += got26.size()
		if got26 != expect26[w26]:
			table_ok26 = false
			table_detail26 += "wave%d got=%s want=%s; " % [w26, str(got26), str(expect26[w26])]
	check("boss_table_names_all_waves", table_ok26, table_detail26)
	check("boss_table_wave6_three_brothers", (gameE.call("bosses_for_wave", 6) as Array).size() == 3 and String((gameE.call("bosses_for_wave", 6) as Array)[2]["name"]) == "张宝")
	check("boss_table_wave20_order", (gameE.call("bosses_for_wave", 20) as Array).size() == 3 and String((gameE.call("bosses_for_wave", 20) as Array)[0]["name"]) == "司马昭" and String((gameE.call("bosses_for_wave", 20) as Array)[1]["name"]) == "司马师" and String((gameE.call("bosses_for_wave", 20) as Array)[2]["name"]) == "司马懿")
	check("boss_table_total_24", total_bosses26 == 24, "total=" + str(total_bosses26))
	var comp_ok26 := true
	var comp_detail26 := ""
	for w26b in range(1, 21):
		var comp26: Dictionary = gameE.call("wave_composition", w26b)
		if int(comp26.get("boss", -1)) != (expect26[w26b] as Array).size():
			comp_ok26 = false
			comp_detail26 += "wave%d comp_boss=%s want=%d; " % [w26b, str(comp26.get("boss")), (expect26[w26b] as Array).size()]
	check("boss_composition_counts_match", comp_ok26, comp_detail26)
	var prev6: String = gameE.call("wave_preview_text", 6)
	check("boss_preview_wave6_names", "张角" in prev6 and "张梁" in prev6 and "张宝" in prev6, "preview=" + prev6)
	var prev20: String = gameE.call("wave_preview_text", 20)
	check("boss_preview_wave20_names", "司马昭" in prev20 and "司马师" in prev20 and "司马懿" in prev20, "preview=" + prev20)
	# Spawn checks through the real queue: wave 1 boss HP formula
	# 380 * (1 + 0.32*(w-1)) * 1.10^max(0,w-10) * mul (calibration G2);
	# 韩德 mul 0.95 -> 361.
	gameE.call("select_hero", 0)
	await process_frame
	gameE.call("_start_wave", 1)
	await process_frame
	while not (gameE.get("spawn_queue") as Array).is_empty():
		gameE.call("_spawn_from_queue")
	var boss1_26: Node = _find_enemy(gameE, "boss")
	check("boss_wave1_spawns_hande", boss1_26 != null and String((gameE.get("bosses_spawned_names") as Array)[(gameE.get("bosses_spawned_names") as Array).size() - 1]) == "韩德")
	if boss1_26 != null:
		check("boss_wave1_hp_formula", is_equal_approx(float(boss1_26.get("max_hp")), 361.0), "max_hp=" + str(float(boss1_26.get("max_hp"))))
		check("boss_wave1_is_boss_meta", bool(boss1_26.get_meta("is_boss")) and int(boss1_26.get_meta("bounty")) == 150, "bounty=" + str(boss1_26.get_meta("bounty")))
	var end6pre: String = await _clear_current_wave(gameE)
	check("boss_wave1_clears_to_intermission", end6pre == "intermission", "state=" + end6pre)
	# Wave 6: all three brothers spawn in order, HP set matches formula
	# (380 * 2.6 * mul): 张角 1155.96 / 张梁 908.96 / 张宝 958.36; all ranged.
	gameE.call("_start_wave", 6)
	await process_frame
	while not (gameE.get("spawn_queue") as Array).is_empty():
		gameE.call("_spawn_from_queue")
	var spawned6: Array = gameE.get("bosses_spawned_names")
	var last3_6: Array = spawned6.slice(spawned6.size() - 3, spawned6.size())
	check("boss_wave6_three_spawned_in_order", last3_6 == ["张角", "张梁", "张宝"], "last3=" + str(last3_6))
	var hps6: Array = []
	var ranged6 := 0
	for e26 in gameE.get("enemies"):
		if is_instance_valid(e26) and bool(e26.get("alive")) and String(e26.get("archetype")) == "boss":
			hps6.append(float(e26.get("max_hp")))
			if float(e26.get("attack_range")) > 6.0:
				ranged6 += 1
	hps6.sort()
	check("boss_wave6_hp_formula_set", hps6.size() == 3 and is_equal_approx(hps6[0], 908.96) and is_equal_approx(hps6[1], 958.36) and is_equal_approx(hps6[2], 1155.96), "hps=" + str(hps6))
	check("boss_wave6_all_ranged", ranged6 == 3, "ranged=" + str(ranged6))
	var end20pre: String = await _clear_current_wave(gameE)
	check("boss_wave6_clears_to_intermission", end20pre == "intermission", "state=" + end20pre)
	# Wave 20: Three Simas in order; 司马懿 HP 380 * 7.08 * 1.10^10 * 2.97
	# = 20725.27 (calibration G2 composite curve) and ranged (12.0);
	# clearing it wins the game.
	gameE.call("_start_wave", 20)
	await process_frame
	while not (gameE.get("spawn_queue") as Array).is_empty():
		gameE.call("_spawn_from_queue")
	var spawned20: Array = gameE.get("bosses_spawned_names")
	var last3_20: Array = spawned20.slice(spawned20.size() - 3, spawned20.size())
	check("boss_wave20_three_spawned_in_order", last3_20 == ["司马昭", "司马师", "司马懿"], "last3=" + str(last3_20))
	var yi_hp26 := -1.0
	var yi_ranged26 := false
	for e26b in gameE.get("enemies"):
		if is_instance_valid(e26b) and bool(e26b.get("alive")) and String(e26b.get("archetype")) == "boss" and String(e26b.get("display_name")) == "司马懿":
			yi_hp26 = float(e26b.get("max_hp"))
			yi_ranged26 = float(e26b.get("attack_range")) > 6.0
	check("boss_wave20_sima_yi_hp_formula", is_equal_approx(yi_hp26, 20725.27), "max_hp=" + str(yi_hp26))
	check("boss_wave20_sima_yi_ranged", yi_ranged26)
	var end20_26: String = await _clear_current_wave(gameE)
	check("boss_wave20_clear_wins", end20_26 == "victory", "state=" + end20_26)
	gameE.free()

	# --- Test 27 (画面清单「地面可读性」: VISUAL_AUDIT P1-1) --------------
	# Construction checks for the P1-1 ground fix: seams read as soil
	# lines (lifted underlay + overlapping tiles), grass brightened with
	# per-tile variation, road tiles tinted close to the ribbon, ribbons
	# widened to cover the whole road band with a worn centre strip, and
	# aprons paving the five flat road zones. The aesthetic verdict
	# itself is Codex's (VISUAL_AUDIT.md), not this harness.
	# -0.6 addendum (2026-11-14): the grass half of this test now pins
	# the continuous-surface structure instead (see the tile-count
	# block below); road/ribbon/apron checks are unchanged.
	var gameG := _make_game()
	await process_frame
	await process_frame
	var lum27 := func(c: Color) -> float: return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
	check("ground_tile_scale_narrows_seams", float(gameG.get("ground_tile_scale")) >= 3.08, "scale=" + str(float(gameG.get("ground_tile_scale"))))
	check("ground_underlay_lifted", lum27.call(gameG.get("ground_underlay_color")) >= 0.44, "lum=" + str(lum27.call(gameG.get("ground_underlay_color"))))
	check("grass_tint_brighter", lum27.call(gameG.get("grass_tint")) >= 0.55, "lum=" + str(lum27.call(gameG.get("grass_tint"))))
	check("road_tile_tint_lifted", lum27.call(gameG.get("road_tile_tint")) >= 0.55, "lum=" + str(lum27.call(gameG.get("road_tile_tint"))))
	check("road_ribbon_width_covers_band", float(gameG.get("road_ribbon_width")) >= 8.4, "width=" + str(float(gameG.get("road_ribbon_width"))))
	check("road_ribbon_color_lifted", lum27.call(gameG.get("road_ribbon_color")) >= 0.42, "lum=" + str(lum27.call(gameG.get("road_ribbon_color"))))
	var slab27: Node = gameG.find_child("GroundSlab", true, false)
	var slab_ok27 := false
	if slab27 is MeshInstance3D:
		var smat: Material = (slab27 as MeshInstance3D).material_override
		if smat is StandardMaterial3D:
			slab_ok27 = (smat as StandardMaterial3D).albedo_color.is_equal_approx(gameG.get("ground_underlay_color"))
	check("ground_slab_material_matches", slab_ok27)
	# Repeated _add_box/_add_cylinder siblings are auto-renamed by Godot
	# to @MeshInstance3D@N, so ribbons/centres/joints are identified by
	# mesh size, not by name (names stay unique only for the aprons).
	var wr27b: Node = gameG.get("world_root")
	var rib27 := 0
	var cen27 := 0
	var joint27 := 0
	var stone27 := 0
	var blotch27 := 0
	var pebble27 := 0
	var patch27 := 0
	var tuft27 := 0
	if wr27b != null:
		for ch27b in wr27b.get_children():
			if ch27b is MeshInstance3D:
				var m27: Mesh = (ch27b as MeshInstance3D).mesh
				if m27 is BoxMesh:
					var sz27: Vector3 = (m27 as BoxMesh).size
					if is_equal_approx(sz27.y, 0.055) and is_equal_approx(sz27.z, float(gameG.get("road_ribbon_width"))):
						rib27 += 1
					if is_equal_approx(sz27.y, 0.03) and is_equal_approx(sz27.z, float(gameG.get("road_center_width"))):
						cen27 += 1
				elif m27 is CylinderMesh:
					if is_equal_approx(float((m27 as CylinderMesh).top_radius), 4.5):
						joint27 += 1
					if is_equal_approx(float((m27 as CylinderMesh).height), 0.02):
						stone27 += 1
					if is_equal_approx(float((m27 as CylinderMesh).height), 0.015):
						blotch27 += 1
					if is_equal_approx(float((m27 as CylinderMesh).height), 0.012):
						pebble27 += 1
					if is_equal_approx(float((m27 as CylinderMesh).height), 0.01):
						patch27 += 1
				elif m27 is SphereMesh:
					if is_equal_approx(float((ch27b as Node3D).scale.y), 0.28):
						tuft27 += 1
	check("road_ribbons_all_wide", rib27 == 16, "ribbons=" + str(rib27))
	check("road_center_strips_present", cen27 == 16, "centers=" + str(cen27))
	check("road_joints_round_corners", joint27 == 18, "joints=" + str(joint27))
	check("road_stone_inlays_removed", stone27 == 0, "stones=" + str(stone27)) # 碎石堆清除改判（2026-11-17 用户裁定）：224->0
	check("road_edge_blotches", blotch27 == 104, "blotches=" + str(blotch27))
	check("road_small_pebbles_removed", pebble27 == 0, "pebbles=" + str(pebble27)) # 碎石堆清除改判（2026-11-17 用户裁定）：280->0
	check("road_shallow_patches", patch27 == 72, "patches=" + str(patch27))
	check("road_edge_tufts", tuft27 == 152, "tufts=" + str(tuft27))
	var aprons27: Array = gameG.find_children("RoadApron*", "MeshInstance3D", true, false)
	check("road_aprons_five_zones", aprons27.size() == 5, "count=" + str(aprons27.size()))
	var plaza27: Node = gameG.find_child("RoadApronPlaza", true, false)
	var plaza_ok27 := false
	if plaza27 is MeshInstance3D and (plaza27 as MeshInstance3D).mesh is CylinderMesh:
		plaza_ok27 = float(((plaza27 as MeshInstance3D).mesh as CylinderMesh).top_radius) >= 9.0
	check("road_apron_plaza_radius", plaza_ok27)
	# -0.6 地面连续化 (2026-11-14): grass hex tiles are GONE — their
	# per-tile tint/height steps were the device-visible checkerboard.
	# Road hex tiles remain as hard paving (overlap scale, texture
	# stripped); every soft floor is one vertex-colored GroundSurface.
	var wr27: Node = gameG.get("world_root")
	var grass_tiles27 := 0
	var road_tiles27 := 0
	var road_scaled27 := 0
	var road_stripped27 := 0
	var base27 := float(gameG.get("ground_tile_scale"))
	if wr27 != null:
		for ch27 in wr27.get_children():
			if ch27 is Node3D:
				var sfp27 := String((ch27 as Node).scene_file_path)
				if sfp27.ends_with("hex_grass.gltf"):
					grass_tiles27 += 1
				elif sfp27.ends_with("hex_road_A.gltf"):
					road_tiles27 += 1
					var sc27 := float((ch27 as Node3D).scale.x)
					if sc27 >= base27 * 0.98 and sc27 <= base27 * 1.02:
						road_scaled27 += 1
					var mis27: Array = (ch27 as Node).find_children("*", "MeshInstance3D", true, false)
					if not mis27.is_empty():
						var mat27: Material = (mis27[0] as MeshInstance3D).get_surface_override_material(0)
						if mat27 is StandardMaterial3D and (mat27 as StandardMaterial3D).albedo_texture == null:
							road_stripped27 += 1
	check("ground_grass_hex_tiles_removed", grass_tiles27 == 0, "grass_tiles=" + str(grass_tiles27))
	check("ground_road_hex_tiles_kept", road_tiles27 >= 80, "road_tiles=" + str(road_tiles27))
	check("ground_road_tiles_overlap_scale", road_tiles27 > 0 and road_scaled27 == road_tiles27, "scaled=" + str(road_scaled27) + "/" + str(road_tiles27))
	check("ground_road_tiles_texture_stripped", road_tiles27 > 0 and road_stripped27 == road_tiles27, "stripped=" + str(road_stripped27) + "/" + str(road_tiles27))
	var gs27: Node = gameG.find_child("GroundSurface", true, false)
	var gs_ok27 := false
	var gs_colors27 := 0
	if gs27 is MeshInstance3D and (gs27 as MeshInstance3D).mesh != null:
		var gm27: Mesh = (gs27 as MeshInstance3D).mesh
		if gm27.get_surface_count() == 1:
			var arrs27: Array = gm27.surface_get_arrays(0)
			var cols27: PackedColorArray = arrs27[Mesh.ARRAY_COLOR]
			gs_colors27 = cols27.size()
			gs_ok27 = gs_colors27 > 1000 and (gs27 as MeshInstance3D).material_override is StandardMaterial3D and ((gs27 as MeshInstance3D).material_override as StandardMaterial3D).vertex_color_use_as_albedo
	check("ground_surface_single_vertex_colored_mesh", gs_ok27, "verts=" + str(gs_colors27))
	# Render-facing guard (2026-11-14): the first continuous surface
	# shipped with (0,-1,0) normals and was backface-culled — every
	# data check passed while nothing rendered (captures showed the
	# slab). Normals must point UP or the color field is fiction.
	var gs_up27 := false
	if gs27 is MeshInstance3D and (gs27 as MeshInstance3D).mesh != null:
		var garr27: Array = (gs27 as MeshInstance3D).mesh.surface_get_arrays(0)
		var gnorms27: PackedVector3Array = garr27[Mesh.ARRAY_NORMAL]
		gs_up27 = gnorms27.size() > 0 and gnorms27[0].y > 0.9 and gnorms27[gnorms27.size() / 2].y > 0.9
	check("ground_surface_normals_up", gs_up27, "normals +Y required")
	# Color-field sampling: open field reads as grass, zone centres
	# read as their floors, the forest south edge is a blend not a step.
	var cdist27 := func(a: Color, b: Color) -> float: return sqrt((a.r - b.r) * (a.r - b.r) + (a.g - b.g) * (a.g - b.g) + (a.b - b.b) * (a.b - b.b))
	var fc27: Color = gameG.call("_ground_color_at", 20.0, 30.0)
	check("ground_color_field_is_grass", fc27.g > fc27.r and fc27.r > fc27.b and lum27.call(fc27) >= 0.50, "c=" + str(fc27))
	var fo27: Color = gameG.call("_ground_color_at", 63.0, -37.0)
	var fo_ref27: Color = gameG.get("forest_floor_color")
	check("ground_color_forest_is_moss", cdist27.call(fo27, fo_ref27) <= 0.16 and lum27.call(fo27) < lum27.call(fc27), "c=" + str(fo27))
	var gr27c: Color = gameG.call("_ground_color_at", -19.0, -36.5)
	var gr_ref27: Color = gameG.get("grave_floor_color")
	check("ground_color_grave_is_ash", cdist27.call(gr27c, gr_ref27) <= 0.16 and absf(gr27c.r - gr27c.b) <= 0.075, "c=" + str(gr27c))
	var bl27: Color = gameG.call("_ground_color_at", 63.0, -28.5)
	check("ground_color_forest_edge_blends", cdist27.call(bl27, fc27) > 0.05 and cdist27.call(bl27, fo_ref27) > 0.05, "c=" + str(bl27))
	gameG.free()

	# --- Test 28 (紧急修复 2026-11-13: 内嵌 CJK 字体) -------------------
	# The project previously relied on the engine default font + system
	# fallback; Web exports have no system fonts, so every Chinese string
	# rendered as tofu boxes. The fix embeds subsetted Noto Sans CJK SC
	# (724 glyphs: the 515 CJK/punct chars used in scripts/scenes +
	# ASCII + Latin-1) as gui/theme/custom_font, sets it explicitly on
	# Label3D signs, and uses the Bold face for the two title labels.
	check("cjk_default_font_setting", String(ProjectSettings.get_setting("gui/theme/custom_font")) == "res://assets/fonts/NotoSansCJKsc-Regular.ttf", str(ProjectSettings.get_setting("gui/theme/custom_font")))
	var font_reg: Font = load("res://assets/fonts/NotoSansCJKsc-Regular.ttf")
	var font_bold: Font = load("res://assets/fonts/NotoSansCJKsc-Bold.ttf")
	check("cjk_font_resources_load", font_reg != null and font_bold != null)
	var cjk_sample: Array = [0x5251, 0x59DC, 0x7EF4, 0x9009, 0x62E9, 0x82F1, 0x96C4, 0x5C01, 0x5370, 0x6838, 0x8BAD, 0x7EC3, 0x573A, 0x4E0A, 0x65B9, 0x8C37, 0x51B3, 0x6218, 0x5E7F, 0x5175, 0x5C06]
	var cjk_ok := font_reg != null
	if font_reg != null:
		for cp in cjk_sample:
			if not font_reg.has_char(cp):
				cjk_ok = false
		cjk_ok = cjk_ok and font_reg.has_char(65) and font_reg.has_char(49) and font_reg.has_char(0xB7) and font_reg.has_char(0x3002) and font_reg.has_char(0x3001)
	check("cjk_font_covers_used_glyphs", cjk_ok, "sample=" + str(cjk_sample.size()))
	check("cjk_bold_covers_jian", font_bold != null and font_bold.has_char(0x5251))
	var gameF := _make_game()
	await process_frame
	await process_frame
	var msg28: Label = gameF.get("message_label")
	check("cjk_message_label_bold_font", msg28 != null and msg28.get_theme_font("font") == font_bold)
	var detail28: Label = gameF.get("hero_detail_label")
	check("cjk_detail_label_default_font", detail28 != null and detail28.get_theme_font("font") == font_reg)
	var signs28: Array = gameF.find_children("*", "Label3D", true, false)
	var sign_ok28 := false
	var sign_text28 := ""
	for s28 in signs28:
		var l28 := s28 as Label3D
		if l28 != null and String(l28.text).contains("训练场"):
			sign_text28 = String(l28.text)
			sign_ok28 = l28.font == font_reg
	if signs28.is_empty():
		sign_text28 = "no Label3D found"
	check("cjk_label3d_sign_uses_font", sign_ok28, sign_text28)
	gameF.free()

	# --- Test 29 (地图补齐 2026-11-14: 森林区＋墓地区, LOOP_STATE -0.5) ---
	# TEARDOWN §2 wild areas as built zones: forest NE (青龙之位/烧皮点/
	# 毒蜘蛛巢), graveyard NW (项羽之魂挑战点/白虎之位). Zones, points
	# and signs only — the saint/quest/challenge systems are stage 2.
	# Reachability is verified by walking the hero in from the road
	# through each connector path (staging the hero at a path head is a
	# scenario setup, like the earlier staged probes). This test also
	# pins the WEBDBG cleanup: the temp web-debug code from the
	# 2026-11-13 parallel session is gone and the dusk environment is
	# restored verbatim (values per daylight-ab/AB_PARAMS.md).
	var gameH := _make_game()
	await process_frame
	await process_frame
	check("forest_zone_exists", gameH.find_child("ForestZone", true, false) != null)
	check("grave_zone_exists", gameH.find_child("GraveZone", true, false) != null)
	# -0.6: zone floors are baked into the continuous ground surface
	# (feathered blends, no hard-edged apron boxes); the color sampled
	# at each zone centre must read as that zone's floor, not grass.
	check("forest_apron_box_removed", gameH.find_child("ForestApron", true, false) == null)
	check("grave_apron_box_removed", gameH.find_child("GraveApron", true, false) == null)
	var cdist29 := func(a: Color, b: Color) -> float: return sqrt((a.r - b.r) * (a.r - b.r) + (a.g - b.g) * (a.g - b.g) + (a.b - b.b) * (a.b - b.b))
	var zf29: Color = gameH.call("_ground_color_at", 63.0, -37.0)
	check("forest_floor_in_ground_surface", cdist29.call(zf29, gameH.get("forest_floor_color")) <= 0.16, "c=" + str(zf29))
	var zg29: Color = gameH.call("_ground_color_at", -19.0, -36.5)
	check("grave_floor_in_ground_surface", cdist29.call(zg29, gameH.get("grave_floor_color")) <= 0.16, "c=" + str(zg29))
	check("forest_path_exists", gameH.find_child("ForestPath", true, false) != null)
	check("grave_path_exists", gameH.find_child("GravePath", true, false) != null)
	check("qinglong_dais_exists", gameH.find_child("QinglongDais", true, false) != null)
	check("qinglong_crystal_exists", gameH.find_child("QinglongCrystal", true, false) != null)
	# Review round 13: the ward markers must be faceted, colored
	# crystals — never a white untextured sphere (P1-5).
	check("qinglong_crystal_colored", _cluster_is_colored(gameH.find_child("QinglongCrystal", true, false)), "")
	check("scorch_disc_exists", gameH.find_child("ScorchDisc", true, false) != null)
	check("spider_mound_exists", gameH.find_child("SpiderMound", true, false) != null)
	check("xiangyu_stele_exists", gameH.find_child("XiangyuStele", true, false) != null)
	check("baihu_dais_exists", gameH.find_child("BaihuDais", true, false) != null)
	check("baihu_crystal_exists", gameH.find_child("BaihuCrystal", true, false) != null)
	check("baihu_crystal_colored", _cluster_is_colored(gameH.find_child("BaihuCrystal", true, false)), "")
	var sign_texts29 := ""
	var forest_font29 := 0
	var grave_font29 := 0
	for s29 in gameH.find_children("*", "Label3D", true, false):
		sign_texts29 += String((s29 as Label3D).text) + "|"
		if (s29 as Label3D).text == "森林":
			forest_font29 = (s29 as Label3D).font_size
		if (s29 as Label3D).text == "墓地":
			grave_font29 = (s29 as Label3D).font_size
	check("forest_sign_present", sign_texts29.contains("森林"), "")
	check("qinglong_sign_present", sign_texts29.contains("青龙之位"), "")
	check("scorch_sign_present", sign_texts29.contains("烧皮点"), "")
	check("spider_sign_present", sign_texts29.contains("毒蜘蛛巢"), "")
	check("grave_sign_present", sign_texts29.contains("墓地"), "")
	check("xiangyu_sign_present", sign_texts29.contains("项羽之魂"), "")
	check("baihu_sign_present", sign_texts29.contains("白虎之位"), "")
	# Review round 13: zone signs must stay legible at full zoom-out
	# (120pt, raised clear of the north ridge/tree line).
	check("forest_sign_large", forest_font29 >= 100, "font=" + str(forest_font29))
	check("grave_sign_large", grave_font29 >= 100, "font=" + str(grave_font29))
	check("webdbg_box_absent", gameH.find_child("WEBDBG_BOX", true, false) == null)
	var env29: Environment = gameH.get("env_ref")
	# Dusk grade Rev 2 (2026-11-14, visual item 全局色调): ambient
	# 0.72->0.85 + bluer color, sun 0.55->0.50, exposure 0.90->0.88,
	# saturation 0.97->0.93, fog 0.006->0.008. Fog density later
	# 0.008->0.0095 by 边缘与远景 Rev 1 (far-ring melt; depth-mode
	# fog renders nothing in gl_compatibility, density is the lever).
	check("env_dusk_restored", env29 != null and env29.background_color.is_equal_approx(Color(0.004, 0.009, 0.040)) and env29.glow_enabled and env29.fog_enabled and env29.tonemap_mode == Environment.TONE_MAPPER_ACES and is_equal_approx(env29.ambient_light_energy, 0.85) and env29.ambient_light_color.is_equal_approx(Color(0.17, 0.205, 0.30)) and is_equal_approx(env29.tonemap_exposure, 0.88) and is_equal_approx(env29.fog_density, 0.0100)) # Rev 4 （边缘）改判: 明度型空气透视 density 0.0105->0.0100 (0.0070/0.0085 两轮均洗白, 定版微调), 与 Test 40 同步
	check("tone_grass_cooled", (gameH.get("grass_tint") as Color).b > (gameH.get("grass_tint") as Color).r - 0.10 and (gameH.get("grass_tint") as Color).is_equal_approx(Color(0.513, 0.647, 0.486))) # 全局色调 Rev 4: desat+bluegrey mix, lum kept; Rev 4 改判依据：同步新 tint 期望值
	check("tone_wall_stone_cooled", (gameH.get("wall_stone_tint") as Color).is_equal_approx(Color(0.699, 0.681, 0.662))) # 全局色调 Rev 4: desat+bluegrey mix, lum kept; Rev 4 改判依据：同步新 tint 期望值
	check("sun_dusk_restored", is_equal_approx(float((gameH.get("sun_light") as DirectionalLight3D).light_energy), 0.50))
	gameH.call("select_hero", 0) # 赵统
	await process_frame
	var hero29: Node = gameH.get("strategist")
	check("zones_hero_present", hero29 != null)
	if hero29 != null:
		hero29.set("global_position", Vector3(59, 0, -24))
		hero29.call("move_to", Vector3(63, 0, -37))
		var arrived_forest29 := await wait_until(func() -> bool: return (hero29.get("global_position") as Vector3).distance_to(Vector3(63, 0, -37)) < 2.5, 15.0)
		check("hero_reaches_forest", arrived_forest29, "pos=" + str(hero29.get("global_position")))
		hero29.set("global_position", Vector3(-19, 0, -2))
		hero29.call("move_to", Vector3(-19, 0, -36.5))
		var arrived_grave29 := await wait_until(func() -> bool: return (hero29.get("global_position") as Vector3).distance_to(Vector3(-19, 0, -36.5)) < 2.5, 20.0)
		check("hero_reaches_graveyard", arrived_grave29, "pos=" + str(hero29.get("global_position")))
	gameH.free()

	# --- Test 30 (地图补齐 2026-11-14: 水域＋新城＋朱雀之位, LOOP_STATE -0.5) ---
	# TEARDOWN §2 wild areas as built zones: water SE (玄武之位 pond),
	# new city NW (孟达 town), 朱雀之位 marker between the rift portals.
	# Zones, points and signs only — the saint/quest systems are stage 2.
	var gameI := _make_game()
	await process_frame
	await process_frame
	check("water_zone_exists", gameI.find_child("WaterZone", true, false) != null)
	check("newcity_zone_exists", gameI.find_child("NewcityZone", true, false) != null)
	check("zhuque_marker_exists", gameI.find_child("ZhuqueMarker", true, false) != null)
	# -0.6: zone floors are baked into the continuous ground surface
	# (feathered blends, no hard-edged apron boxes); the color sampled
	# at each zone centre must read as that zone's floor, not grass.
	var cdist30 := func(a: Color, b: Color) -> float: return sqrt((a.r - b.r) * (a.r - b.r) + (a.g - b.g) * (a.g - b.g) + (a.b - b.b) * (a.b - b.b))
	var zw30: Color = gameI.call("_ground_color_at", 70.0, 40.0)
	check("water_floor_in_ground_surface", cdist30.call(zw30, gameI.get("water_floor_color")) <= 0.16, "c=" + str(zw30))
	var zn30: Color = gameI.call("_ground_color_at", -75.0, -34.0)
	check("newcity_floor_in_ground_surface", cdist30.call(zn30, gameI.get("newcity_floor_color")) <= 0.16, "c=" + str(zn30))
	check("water_path_exists", gameI.find_child("WaterPath", true, false) != null)
	check("newcity_path_exists", gameI.find_child("NewcityPath", true, false) != null)
	check("water_pond_exists", gameI.find_child("WaterPond", true, false) != null)
	check("xuanwu_dais_exists", gameI.find_child("XuanwuDais", true, false) != null)
	check("xuanwu_crystal_exists", gameI.find_child("XuanwuCrystal", true, false) != null)
	# Review round 13: the ward markers must be faceted, colored
	# crystals — never a white untextured sphere (P1-5).
	check("xuanwu_crystal_colored", _cluster_is_colored(gameI.find_child("XuanwuCrystal", true, false)), "")
	check("zhuque_crystal_exists", gameI.find_child("ZhuqueCrystal", true, false) != null)
	check("zhuque_crystal_colored", _cluster_is_colored(gameI.find_child("ZhuqueCrystal", true, false)), "")
	check("newcity_gate_exists", gameI.find_child("NewcityGatePillar", true, false) != null)
	check("newcity_house_a_exists", gameI.find_child("NewcityHouseA", true, false) != null)
	check("newcity_house_b_exists", gameI.find_child("NewcityHouseB", true, false) != null)
	check("newcity_house_c_exists", gameI.find_child("NewcityHouseC", true, false) != null)
	check("newcity_well_exists", gameI.find_child("NewcityWell", true, false) != null)
	check("mengda_exists", gameI.find_child("孟达", true, false) != null)
	var sign_texts30 := ""
	var water_font30 := 0
	var newcity_font30 := 0
	for s30 in gameI.find_children("*", "Label3D", true, false):
		sign_texts30 += String((s30 as Label3D).text) + "|"
		if (s30 as Label3D).text == "水域":
			water_font30 = (s30 as Label3D).font_size
		if (s30 as Label3D).text == "新城":
			newcity_font30 = (s30 as Label3D).font_size
	check("water_sign_present", sign_texts30.contains("水域"), "")
	check("xuanwu_sign_present", sign_texts30.contains("玄武之位"), "")
	check("newcity_sign_present", sign_texts30.contains("新城"), "")
	check("mengda_sign_present", sign_texts30.contains("孟达"), "")
	check("zhuque_sign_present", sign_texts30.contains("朱雀之位"), "")
	# Review round 13: zone signs must stay legible at full zoom-out
	# (120pt, raised clear of the ridge/tree line).
	check("water_sign_large", water_font30 >= 100, "font=" + str(water_font30))
	check("newcity_sign_large", newcity_font30 >= 100, "font=" + str(newcity_font30))
	gameI.call("select_hero", 0) # 赵统
	await process_frame
	var hero30: Node = gameI.get("strategist")
	check("zones2_hero_present", hero30 != null)
	if hero30 != null:
		hero30.set("global_position", Vector3(59, 0, 24))
		hero30.call("move_to", Vector3(63, 0, 36.5))
		var arrived_water30 := await wait_until(func() -> bool: return (hero30.get("global_position") as Vector3).distance_to(Vector3(63, 0, 36.5)) < 2.5, 15.0)
		check("hero_reaches_water", arrived_water30, "pos=" + str(hero30.get("global_position")))
		hero30.set("global_position", Vector3(-75, 0, -20))
		hero30.call("move_to", Vector3(-75, 0, -34))
		var arrived_newcity30 := await wait_until(func() -> bool: return (hero30.get("global_position") as Vector3).distance_to(Vector3(-75, 0, -34)) < 2.5, 20.0)
		check("hero_reaches_newcity", arrived_newcity30, "pos=" + str(hero30.get("global_position")))
	gameI.free()

	# --- Test 31 (地图补齐 2026-11-14: 葫芦谷·上方谷＋炼化师, LOOP_STATE -0.5) ---
	# TEARDOWN §2 wild areas as built zones: the 上方谷 gorge (NE, the
	# finale terrain) and the 炼化师 stall (SW, forger of sets). Zones,
	# points and signs only — the finale event / synthesis systems are
	# stage 2. Site note: the valley sits on the flat foot of the NE
	# cliff band (x 83..87); the suggested x 82..97 band is mostly
	# EastCliff slope + rim rock, so no floor props stand east of x~86.
	var gameJ := _make_game()
	await process_frame
	await process_frame
	check("valley_zone_exists", gameJ.find_child("ValleyZone", true, false) != null)
	check("refiner_zone_exists", gameJ.find_child("RefinerZone", true, false) != null)
	var cdist31 := func(a: Color, b: Color) -> float: return sqrt((a.r - b.r) * (a.r - b.r) + (a.g - b.g) * (a.g - b.g) + (a.b - b.b) * (a.b - b.b))
	var zv31: Color = gameJ.call("_ground_color_at", 85.0, -37.0)
	check("valley_floor_in_ground_surface", cdist31.call(zv31, gameJ.get("valley_floor_color")) <= 0.16, "c=" + str(zv31))
	check("valley_path_exists", gameJ.find_child("ValleyPath", true, false) != null)
	check("valley_wall_exists", gameJ.find_child("ValleyWallRock", true, false) != null)
	check("valley_scorch_exists", gameJ.find_child("ValleyScorch", true, false) != null)
	check("valley_firewood_exists", gameJ.find_child("ValleyFirewood", true, false) != null)
	check("refiner_path_exists", gameJ.find_child("RefinerPath", true, false) != null)
	check("refiner_furnace_exists", gameJ.find_child("RefinerFurnace", true, false) != null)
	check("refiner_anvil_exists", gameJ.find_child("RefinerAnvil", true, false) != null)
	check("refiner_npc_exists", gameJ.find_child("炼化师", true, false) != null)
	var sign_texts31 := ""
	var valley_font31 := 0
	var refiner_font31 := 0
	for s31 in gameJ.find_children("*", "Label3D", true, false):
		sign_texts31 += String((s31 as Label3D).text) + "|"
		if (s31 as Label3D).text == "葫芦谷":
			valley_font31 = (s31 as Label3D).font_size
		if (s31 as Label3D).text == "炼化师 · 合成打造":
			refiner_font31 = (s31 as Label3D).font_size
	check("valley_sign_present", sign_texts31.contains("葫芦谷"), "")
	check("shangfangu_sign_present", sign_texts31.contains("上方谷"), "")
	check("refiner_sign_present", sign_texts31.contains("炼化师 · 合成打造"), "")
	check("valley_sign_large", valley_font31 >= 100, "font=" + str(valley_font31))
	check("refiner_sign_point", refiner_font31 == 64, "font=" + str(refiner_font31))
	gameJ.call("select_hero", 0) # 赵统
	await process_frame
	var hero31: Node = gameJ.get("strategist")
	check("zones3_hero_present", hero31 != null)
	if hero31 != null:
		hero31.set("global_position", Vector3(85, 0, -24))
		hero31.call("move_to", Vector3(85, 0, -37.5))
		var arrived_valley31 := await wait_until(func() -> bool: return (hero31.get("global_position") as Vector3).distance_to(Vector3(85, 0, -37.5)) < 2.5, 15.0)
		check("hero_reaches_valley", arrived_valley31, "pos=" + str(hero31.get("global_position")))
		hero31.set("global_position", Vector3(-70, 0, 44))
		hero31.call("move_to", Vector3(-70, 0, 31.5))
		var arrived_refiner31 := await wait_until(func() -> bool: return (hero31.get("global_position") as Vector3).distance_to(Vector3(-70, 0, 31.5)) < 2.5, 15.0)
		check("hero_reaches_refiner", arrived_refiner31, "pos=" + str(hero31.get("global_position")))
	gameJ.free()

	# --- Test 32 (地图补齐 2026-11-14: 猎人收购点＋城墙·箭塔防线, LOOP_STATE -0.5) ---
	# Hunter: the hide buyer (TEARDOWN §2/§5, 2D (640,1760)); wall: the
	# stage-1 base wall line + 2 arrow towers (TEARDOWN §6) is verified
	# here and given its map label — no second wall is built. Zones,
	# points and signs only — the hide economy is stage 2.
	var gameK := _make_game()
	await process_frame
	await process_frame
	check("hunter_zone_exists", gameK.find_child("HunterZone", true, false) != null)
	check("hunter_hut_exists", gameK.find_child("HunterHut", true, false) != null)
	check("hunter_rack_exists", gameK.find_child("HunterRackBar", true, false) != null)
	check("hunter_hide_exists", gameK.find_child("HunterHide", true, false) != null)
	check("hunter_hidepile_exists", gameK.find_child("HunterHidePile", true, false) != null)
	check("hunter_npc_exists", gameK.find_child("猎人", true, false) != null)
	check("gate_tower_north_exists", gameK.find_child("GateTowerNorth", true, false) != null)
	check("gate_tower_south_exists", gameK.find_child("GateTowerSouth", true, false) != null)
	check("gate_wall_seg_exists", gameK.find_child("GateWallSeg0", true, false) != null)
	check("courtyard_wall_exists", gameK.find_child("CourtyardWallN0", true, false) != null)
	check("watchtower_north_exists", gameK.find_child("WatchtowerNorth", true, false) != null)
	check("watchtower_south_exists", gameK.find_child("WatchtowerSouth", true, false) != null)
	var arrow_towers32 := 0
	for t32 in (gameK.get("towers") as Array):
		var td32: Dictionary = t32
		if String(td32.get("type", "")) == "arrow" and (td32.get("position") as Vector3).x == -50.0:
			arrow_towers32 += 1
	check("wall_two_arrow_towers", arrow_towers32 == 2, "n=" + str(arrow_towers32))
	var sign_texts32 := ""
	var hunter_font32 := 0
	var wall_font32 := 0
	for s32 in gameK.find_children("*", "Label3D", true, false):
		sign_texts32 += String((s32 as Label3D).text) + "|"
		if (s32 as Label3D).text == "猎人 · 兽皮收购":
			hunter_font32 = (s32 as Label3D).font_size
		if (s32 as Label3D).text == "城墙 · 箭塔防线":
			wall_font32 = (s32 as Label3D).font_size
	check("hunter_sign_present", sign_texts32.contains("猎人 · 兽皮收购"), "")
	check("wall_sign_present", sign_texts32.contains("城墙 · 箭塔防线"), "")
	check("hunter_sign_point", hunter_font32 == 64, "font=" + str(hunter_font32))
	check("wall_sign_point", wall_font32 == 64, "font=" + str(wall_font32))
	gameK.call("select_hero", 0) # 赵统
	await process_frame
	var hero32: Node = gameK.get("strategist")
	check("zones4_hero_present", hero32 != null)
	if hero32 != null:
		hero32.set("global_position", Vector3(45, 0, -22))
		hero32.call("move_to", Vector3(45, 0, -29.5))
		var arrived_hunter32 := await wait_until(func() -> bool: return (hero32.get("global_position") as Vector3).distance_to(Vector3(45, 0, -29.5)) < 2.5, 15.0)
		check("hero_reaches_hunter", arrived_hunter32, "pos=" + str(hero32.get("global_position")))
		hero32.set("global_position", Vector3(-50, 0, 0))
		hero32.call("move_to", Vector3(-53, 0, 0))
		var arrived_gate32 := await wait_until(func() -> bool: return (hero32.get("global_position") as Vector3).distance_to(Vector3(-53, 0, 0)) < 2.5, 15.0)
		check("hero_reaches_gate", arrived_gate32, "pos=" + str(hero32.get("global_position")))
	gameK.free()

	# --- Test 33 (商店购买 2026-11-14: 六市肆接真购买, LOOP_STATE -0.4) ---
	# TEARDOWN §5: 6 shops; the first four sell (equip/fine/grocery/
	# book), the casino opens in stage 2 (Test 44), mercenary stays
	# stage-2. Buying deducts gold,
	# lands the item in the 6-slot bag and applies its bonus; books are
	# consumed on purchase; consumables act on use from the bag.
	var gameL := _make_game()
	await process_frame
	await process_frame
	check("shop_defs_eight", (gameL.get("shop_defs") as Array).size() == 8, "n=" + str((gameL.get("shop_defs") as Array).size()))
	var kinds33 := ""
	for d33 in (gameL.get("shop_defs") as Array):
		kinds33 += String((d33 as Dictionary).get("kind", "")) + ","
	check("shop_kinds", kinds33 == "equip,fine,grocery,book,casino,mercenary,trainer,refine,", kinds33)
	check("shop_tier_wave1", int(gameL.call("shop_tier")) == 1, "tier=" + str(gameL.call("shop_tier")))
	check("shop_stock_equip3", (gameL.call("shop_stock", "equip") as Array).size() == 3)
	check("shop_stock_book5", (gameL.call("shop_stock", "book") as Array).size() == 5)
	check("shop_stock_grocery3", (gameL.call("shop_stock", "grocery") as Array).size() == 3)
	gameL.call("select_hero", 0) # 赵统
	await process_frame
	var hero33: Node = gameL.get("strategist")
	check("shop_hero_present", hero33 != null)
	if hero33 != null:
		var base_dmg33 := float(hero33.get("attack_damage"))
		gameL.set("gold", 5000)
		# Open the equipment shop and buy the tier-1 sword.
		gameL.call("_open_shop_panel", 0)
		await process_frame
		check("shop_panel_visible", bool((gameL.get("shop_panel") as Node).get("visible")))
		gameL.call("_on_shop_buy", "sword_t1")
		check("shop_buy_gold", int(gameL.get("gold")) == 5000 - 120, "gold=" + str(gameL.get("gold")))
		check("shop_buy_bag1", (gameL.get("hero_inventory") as Array).size() == 1)
		check("shop_buy_dmg", float(hero33.get("attack_damage")) == base_dmg33 + 6.0, "dmg=" + str(hero33.get("attack_damage")))
		# Insufficient gold refuses without touching gold or the bag.
		gameL.set("gold", 10)
		gameL.call("_on_shop_buy", "armor_t1")
		check("shop_poor_gold", int(gameL.get("gold")) == 10)
		check("shop_poor_bag", (gameL.get("hero_inventory") as Array).size() == 1)
		# A book is consumed at once: no bag slot, attribute bonus lands.
		gameL.set("gold", 5000)
		gameL.call("_open_shop_panel", 3)
		await process_frame
		gameL.call("_on_shop_buy", "book_str")
		check("shop_book_bag", (gameL.get("hero_inventory") as Array).size() == 1)
		check("shop_book_str", float(gameL.get("hero_bonus_str")) == 5.0)
		# Bag full refuses the 7th non-book purchase.
		gameL.set("gold", 5000)
		gameL.call("_open_shop_panel", 2)
		await process_frame
		for i33 in range(5):
			gameL.call("_on_shop_buy", "potion_heal")
		check("shop_bag_full6", (gameL.get("hero_inventory") as Array).size() == 6)
		gameL.call("_on_shop_buy", "stone_home")
		check("shop_full_refused", (gameL.get("hero_inventory") as Array).size() == 6)
		# Use a potion: hero heals 50% max HP and the slot frees.
		hero33.set("hp", float(hero33.get("max_hp")) * 0.2)
		var hp_before33 := float(hero33.get("hp"))
		gameL.call("_use_inventory_item", 1)
		check("shop_potion_heals", float(hero33.get("hp")) > hp_before33, "hp=" + str(hero33.get("hp")))
		check("shop_potion_slot", (gameL.get("hero_inventory") as Array).size() == 5)
		# T2 stock appears at wave 6 (tier rises every 5 waves).
		gameL.set("current_wave", 6)
		check("shop_tier_wave6", int(gameL.call("shop_tier")) == 2, "tier=" + str(gameL.call("shop_tier")))
		var stock2 := gameL.call("shop_stock", "equip") as Array
		check("shop_tier2_sword", String((stock2[0] as Dictionary).get("id", "")) == "sword_t2")
		# Casino opens its own panel now (stage 2); mercenary still shut.
		gameL.call("_close_shop_panel")
		gameL.call("_open_shop_panel", 4)
		check("shop_casino_opens", bool((gameL.get("shop_panel") as Node).get("visible")))
		gameL.call("_close_shop_panel")
		gameL.call("_open_shop_panel", 5)
		check("shop_merc_opens", bool((gameL.get("shop_panel") as Node).get("visible")))
		gameL.call("_close_shop_panel")
		# Level-up keeps the item bonus (and the -0.4 attack_damage fix:
		# with the old `strategist.damage` line, damage never rose).
		var dmg_before_lv33 := float(hero33.get("attack_damage"))
		gameL.call("hero_gain_xp", 10000)
		await process_frame
		check("shop_level_raises_dmg", int(gameL.get("hero_level")) > 1)
		check("shop_bonus_survives_level", float(hero33.get("attack_damage")) > dmg_before_lv33, "dmg=" + str(hero33.get("attack_damage")))
	gameL.free()

	# --- Test 34 (画面效果优化 2026-11-14: 光影丰富度 Rev 1, LOOP_STATE) ---
	# Baseline 4/10: dead-black hard sun shadows, no contact shadows
	# (units/towers floated over the grass), seal core + rifts bright
	# but with no violet falloff on the ground around them.
	var gameM := _make_game()
	await process_frame
	await process_frame
	# 1. Sun shadow unification: opacity down, blur up (energy/color
	#    untouched — the tone item owns those).
	# Rev 2: opacity 0.70->0.55, blur 2.0->3.0; CoolFill re-aimed in
	# pitch (-34->-22, yaw stays 128) and lifted 0.34->0.42 so shaded
	# faces read as cool mid-tones.
	var sun34 := gameM.get("sun_light") as DirectionalLight3D
	check("light_sun_shadow_opacity", sun34 != null and is_equal_approx(sun34.shadow_opacity, 0.55), "op=" + str(sun34.shadow_opacity if sun34 != null else -1.0))
	check("light_sun_shadow_blur", sun34 != null and is_equal_approx(sun34.shadow_blur, 3.0), "blur=" + str(sun34.shadow_blur if sun34 != null else -1.0))
	check("light_sun_energy_untouched", sun34 != null and is_equal_approx(sun34.light_energy, 0.50))
	var cool34 := gameM.get("cool_fill_light") as DirectionalLight3D
	check("light_cool_fill_exists", cool34 != null)
	if cool34 != null:
		check("light_cool_fill_reaimed", cool34.rotation_degrees.is_equal_approx(Vector3(-22, 128, 0)), "rot=" + str(cool34.rotation_degrees))
		# Rev 4 改判：CoolFill 0.47->0.58->0.80，点 1 背光提亮二轮，旋转/颜色不动。
		check("light_cool_fill_energy", is_equal_approx(cool34.light_energy, 0.80))
	# 2. Seal-core glow layering: wide dim fill + two concentric
	#    ground light pools (bright near-source core + faint wide fade).
	var core_fill34 := gameM.get("core_fill_light") as OmniLight3D
	check("light_core_fill_exists", core_fill34 != null)
	if core_fill34 != null:
		# Rev 4 点 6：封印核铺光收紧，energy 1.25->1.05。
		check("light_core_fill_energy", is_equal_approx(core_fill34.light_energy, 1.05))
		# Rev 4 点 6 三轮：range 硬截断，封印核局部补光 range 13->10。
		check("light_core_fill_range", is_equal_approx(core_fill34.omni_range, 10.0))
		check("light_core_fill_no_shadow", not core_fill34.shadow_enabled)
	# Rev 4 条纹定因：CoreLight 全向阴影在晶体刻面上产生 acne；确定性相位研究最坏档 rms 降低 56%。
	check("light_core_no_shadow_rev4", not (gameM.get("crystal_light") as OmniLight3D).shadow_enabled)
	check("light_core_pool_count", gameM.find_children("CoreLightPool*", "MeshInstance3D", true, false).size() == 3, "n=" + str(gameM.find_children("CoreLightPool*", "MeshInstance3D", true, false).size()))
	# Rev 3: local cold spot fills + core wall wash light.
	var cliff34 := gameM.get("cliff_fill_light") as SpotLight3D
	var gate34 := gameM.get("gate_fill_light") as SpotLight3D
	check("light_spot_fills_exist", cliff34 != null and gate34 != null and not cliff34.shadow_enabled and not gate34.shadow_enabled)
	var wash34 := gameM.get("core_wash_light") as OmniLight3D
	# Rev 4 点 6：立面紫洗光 range 14->11，energy 0.8 不动。
	check("light_core_wall_wash", wash34 != null and is_equal_approx(wash34.omni_range, 11.0), "wash present with range 11")
	# 3. Rift glow layering: one fill light + two pool discs per rift.
	var rift_fills34 := gameM.get("rift_fill_lights") as Array
	check("light_rift_fill_count", rift_fills34.size() == 2, "n=" + str(rift_fills34.size()))
	for rf34 in rift_fills34:
		# Rev 4 点 7：裂隙补光 energy 1.15->1.25、range 20->13，收紧衰减。
		check("light_rift_fill_params", is_equal_approx((rf34 as OmniLight3D).light_energy, 1.25) and is_equal_approx((rf34 as OmniLight3D).omni_range, 13.0) and not (rf34 as OmniLight3D).shadow_enabled)
	check("light_rift_pool_count", gameM.find_children("RiftLightPool*", "MeshInstance3D", true, false).size() == 6, "n=" + str(gameM.find_children("RiftLightPool*", "MeshInstance3D", true, false).size()))
	check("light_rift_mist_count", gameM.find_children("RiftMist*", "MeshInstance3D", true, false).size() == 4, "n=" + str(gameM.find_children("RiftMist*", "MeshInstance3D", true, false).size()))
	# 4. Static contact shadows at build time, before any hero/enemy
	#    exists: 2 watchtowers + 2 gate towers + 1 seal pedestal +
	#    10 static NPCs (6 shopkeepers + training officer + 孟达 +
	#    炼化师 + 猎人). Glob: world_root-level discs carry distinct
	#    suffixed names (ContactShadowGateN/S, ContactShadowTowerN).
	# Rev 2: tight profile + deeper alpha (0.48) so the contact core
	# reads "deepest at the feet, fading fast outward".
	check("light_static_contact_count", gameM.find_children("ContactShadow*", "MeshInstance3D", true, false).size() == 34, "n=" + str(gameM.find_children("ContactShadow*", "MeshInstance3D", true, false).size()))
	var watch34 := gameM.find_child("WatchtowerNorth", true, false)
	var watch_disc34 := watch34.find_child("ContactShadow", false, false) as MeshInstance3D if watch34 != null else null
	check("light_watchtower_contact_alpha", watch_disc34 != null and is_equal_approx((watch_disc34.material_override as StandardMaterial3D).albedo_color.a, 0.48), "a=" + str((watch_disc34.material_override as StandardMaterial3D).albedo_color.a if watch_disc34 != null else -1.0))
	# Rev 4 点 5：接地盘收紧 3.3->2.2；TowerPlinth 宽 3.8、半宽 1.9，最深暗带目标 <=5% 基宽。
	check("light_watchtower_contact_radius", watch_disc34 != null and is_equal_approx(watch_disc34.scale.x, 2.2), "r=" + str(watch_disc34.scale.x if watch_disc34 != null else -1.0))
	# 5. Hero + guard gain contact shadows on select; a built tower
	#    gains one too, and it is freed again on reset.
	gameM.call("select_hero", 0) # 赵统
	await process_frame
	var hero34: Node = gameM.get("strategist")
	check("light_hero_present", hero34 != null)
	if hero34 != null:
		check("light_hero_contact", hero34.find_child("ContactShadow", false, false) != null)
		var hero_disc34 := hero34.find_child("ContactShadow", false, false) as MeshInstance3D
		check("light_hero_contact_alpha", hero_disc34 != null and is_equal_approx((hero_disc34.material_override as StandardMaterial3D).albedo_color.a, 0.48), "a=" + str((hero_disc34.material_override as StandardMaterial3D).albedo_color.a if hero_disc34 != null else -1.0))
		check("light_hero_contact_radius", hero_disc34 != null and is_equal_approx(hero_disc34.scale.x, 0.78), "r=" + str(hero_disc34.scale.x if hero_disc34 != null else -1.0))
	var guard34: Node = gameM.get("general")
	check("light_guard_contact", guard34 != null and guard34.find_child("ContactShadow", false, false) != null)
	gameM.set("gold", 5000)
	var built34 := bool(gameM.call("build_tower", 0, "thunder"))
	check("light_build_tower_ok", built34)
	var towers34 := gameM.get("towers") as Array
	var last34 := towers34[towers34.size() - 1] as Dictionary
	check("light_built_tower_shadow", is_instance_valid(last34.get("shadow")), "")
	check("light_built_tower_shadow_node", (last34.get("shadow") as Node) != null and String((last34.get("shadow") as Node).name).begins_with("ContactShadow"))
	gameM.call("reset_game")
	await process_frame
	check("light_reset_frees_tower_shadow", gameM.find_children("ContactShadow*", "MeshInstance3D", true, false).size() == 34, "n=" + str(gameM.find_children("ContactShadow*", "MeshInstance3D", true, false).size()))
	# 6. A spawned beast carries a wider contact shadow.
	var beast34: Node = gameM.call("_make_beast", Vector3(0, 0, 20))
	check("light_beast_contact", beast34 != null and beast34.find_child("ContactShadow", false, false) != null)
	if beast34 != null:
		var bdisc34 := beast34.find_child("ContactShadow", false, false) as MeshInstance3D
		check("light_beast_contact_wide", bdisc34 != null and is_equal_approx(bdisc34.scale.x, 1.9), "sx=" + str(bdisc34.scale.x if bdisc34 != null else -1.0))
	# --- Test 35 (画面效果优化 2026-11-14: 破损件清零 Rev 1, LOOP_STATE) ---
	# Sweep probe (12 close-ups, shots/broken_*.png) verified the live
	# breakage: flat single-color rim rock boxes (one west face read as
	# a violet slab under the core fill light), pale mint field trees,
	# pale gray rubble/rock clusters, rift shards blown to pale pink
	# blobs, near-white watchtowers; flags and ballistae verified
	# grounded (no floating pieces found in the sweep).
	var game35 := _make_game()
	await process_frame
	await process_frame
	# 1. Rim rock masses: one cap stone per mass, embedded in the mass
	# (cap bottom sits inside the mass, never floating).
	var masses35 := game35.find_children("RockWallMass*", "Node3D", true, false)
	check("broken_rock_mass_count", masses35.size() >= 140, "n=" + str(masses35.size()))
	# Swap (0.1.66) re-judge: cap stones retired with the procedural
	# generator; every mass root must now hold modeled geometry.
	var masses_modeled35 := 0
	for m35root in masses35:
		if not (m35root as Node).find_children("*", "MeshInstance3D", true, false).is_empty():
			masses_modeled35 += 1
	check("swap_rock_mass_modeled", masses_modeled35 == masses35.size(), "modeled=" + str(masses_modeled35) + " masses=" + str(masses35.size()))
	# 2. Per-mass tint jitter: not all rim masses share one flat color.
	var mass_colors35 := {}
	for m35 in masses35:
		var mc := _sampled_albedo(m35)
		mass_colors35[Vector3(snappedf(mc.r, 0.02), snappedf(mc.g, 0.02), snappedf(mc.b, 0.02))] = true
	check("broken_rock_mass_jitter", mass_colors35.size() >= 5, "distinct=" + str(mass_colors35.size()))
	# 3. Far mountains jittered too (22 near + 16 far; the glob must
	# not sweep in the Rev 2 notch blocks, which share the prefix).
	var far_nodes35 := game35.find_children("FarMountainNear*", "Node3D", true, false) + game35.find_children("FarMountainFar*", "Node3D", true, false)
	var far_colors35 := {}
	for f35 in far_nodes35:
		var fc := _sampled_albedo(f35)
		far_colors35[Vector3(snappedf(fc.r, 0.02), snappedf(fc.g, 0.02), snappedf(fc.b, 0.02))] = true
	check("broken_far_mountain_count", far_nodes35.size() == 37, "n=" + str(far_nodes35.size())) # 边缘 Rev 4 改判: 远山环北扇区减 1 座 (16->15), 合计 22+15=37
	check("broken_far_mountain_jitter", far_colors35.size() >= 5, "distinct=" + str(far_colors35.size()))
	# 4. Pinned tint values (the sweep-verified pale ones).
	check("broken_field_tree_tint", (game35.get("field_tree_tint") as Color).is_equal_approx(Color(0.26, 0.42, 0.28)))
	check("broken_forest_tree_tint", (game35.get("forest_tree_tint") as Color).is_equal_approx(Color(0.24, 0.40, 0.26)))
	check("broken_rubble_tints", (game35.get("rubble_tint_a") as Color).is_equal_approx(Color(0.46, 0.42, 0.37)) and (game35.get("rubble_tint_b") as Color).is_equal_approx(Color(0.42, 0.38, 0.34)))
	check("broken_rock_cluster_tint", (game35.get("rock_cluster_tint") as Color).is_equal_approx(Color(0.48, 0.44, 0.39)))
	var cl_left35 := 0
	var wr35: Node = game35.get("world_root")
	if wr35 != null:
		for cl_node35 in wr35.get_children():
			if String(cl_node35.name).contains("rocks-large"):
				cl_left35 += 1
	check("broken_rock_clusters_removed", cl_left35 == 0, "n=" + str(cl_left35)) # 石簇清除改判（2026-11-17 用户裁定）：18->0 缺席守卫
	check("broken_watchtower_tint", (game35.get("watchtower_stone_tint") as Color).is_equal_approx(Color(0.622, 0.620, 0.609))) # 全局色调 Rev 4: desat+bluegrey mix, lum kept; Rev 4 改判依据：同步新 tint 期望值
	check("broken_banner_tint", (game35.get("banner_red_tint") as Color).is_equal_approx(Color(0.609, 0.232, 0.232))) # 全局色调 Rev 4 改判依据：红旗 tint 已按处方降饱和至 (0.609,0.232,0.232)。
	check("broken_rift_shard_tint", (game35.get("rift_shard_tint") as Color).is_equal_approx(Color(0.35, 0.10, 0.80)) and (game35.get("rift_shard_emission") as Color).is_equal_approx(Color(0.45, 0.12, 1.0)))
	check("broken_qinglong_tint", (game35.get("qinglong_crystal_tint") as Color).is_equal_approx(Color(0.22, 0.68, 0.36)))
	# 5. Rift shards and the Qinglong crystal read as colored crystal,
	# not pale blobs (same saturation rule as the round-13 check).
	check("broken_rift_shards_colored", _cluster_is_colored(game35.find_child("RiftShardsN", true, false)) and _cluster_is_colored(game35.find_child("RiftShardsS", true, false)))
	check("broken_qinglong_colored", _cluster_is_colored(game35.find_child("QinglongCrystal", true, false)))
	# 6. Rev 2 (Codex 首审): tower courses + ballista cradle on the
	# watchtowers, dark-wood ballista tint. Rev 3 (Codex 复审): the
	# fracture plates and mountain notch overlays are REPLACED by
	# geometry. Rev 4: two noncoplanar facets per mass, sparse wedges;
	# far-ring steps (7 near + 4 far), tower quoins and ballista ironwork.
	# Swap (0.1.66): facet/wedge/spall per-mass checks deleted -- those
	# sub-pieces were the retired procedural generator's output.
	check("broken_no_fault_leftovers", game35.find_children("RockFault*", "MeshInstance3D", true, false).size() == 0)
	check("broken_no_overlay_leftovers", game35.find_children("RockSlab*", "MeshInstance3D", true, false).size() == 0 and game35.find_children("FarMountainNotch*", "MeshInstance3D", true, false).size() == 0)
	check("broken_far_step_count", game35.find_children("FarStep*", "Node3D", true, false).size() == 11, "n=" + str(game35.find_children("FarStep*", "Node3D", true, false).size()))
	var watch35 := game35.find_child("WatchtowerNorth", true, false)
	check("broken_watchtower_courses", watch35 != null and watch35.find_child("TowerPlinth", false, false) != null and watch35.find_child("TowerCourseLow", false, false) != null and watch35.find_child("TowerCourseHigh", false, false) != null and watch35.find_child("BallistaCradle", false, false) != null)
	check("broken_watchtower_quoins", watch35 != null and watch35.find_children("TowerQuoin*", "MeshInstance3D", true, false).size() == 12, "n=" + str(watch35.find_children("TowerQuoin*", "MeshInstance3D", true, false).size() if watch35 != null else -1))
	check("broken_ballista_ironwork", watch35 != null and watch35.find_child("BallistaAxle", true, false) != null and watch35.find_child("BallistaWinch", true, false) != null)
	check("broken_ballista_tint", (game35.get("ballista_tint") as Color).is_equal_approx(Color(0.55, 0.45, 0.35)))
	check("broken_watchtower_seams", watch35 != null and watch35.find_children("TowerSeamH*", "MeshInstance3D", true, false).size() == 48 and watch35.find_children("TowerSeamV*", "MeshInstance3D", true, false).size() == 6) # 破损件 Rev 5 改判：横缝整条改双段错缝（6 高×4 面×2 段），计数 24→48
	var quoin35 := watch35.find_child("TowerQuoin0", true, false) as MeshInstance3D if watch35 != null else null
	check("broken_watchtower_quoin_flush", quoin35 != null and quoin35.mesh is BoxMesh and (quoin35.mesh as BoxMesh).size.x <= 0.55)
	check("broken_ballista_continuous_iron", watch35 != null and watch35.find_children("BallistaStrap*", "MeshInstance3D", true, false).size() == 2 and watch35.find_children("BallistaFrameRail*", "MeshInstance3D", true, false).size() == 2)
	check("broken_ballista_spine_and_crank", watch35 != null and watch35.find_child("BallistaSpineRail", true, false) != null and watch35.find_child("BallistaCrankArm", true, false) != null and watch35.find_children("BallistaBrace*", "MeshInstance3D", true, false).size() == 2)
	var axle35 := watch35.find_child("BallistaAxle", true, false) as MeshInstance3D if watch35 != null else null
	check("broken_ballista_axle_thick", axle35 != null and axle35.mesh is CylinderMesh and (axle35.mesh as CylinderMesh).top_radius >= 0.08)
	# --- Test 36 (画面效果优化: 程序化残件替换 门楼 Rev 3) ---
	# The three P1-4/P2-1 residual pieces are rebuilt, not re-tinted:
	# gate roof gets overlapping tile segments + a sectional ridge +
	# bronze eave teeth; lintel brackets get bearing caps; pads get two lighter stone
	# steps and a flattened gold band inlaid in the plinth top; each
	# rift gets one thick vortex ring + a bright core + a broken rock
	# mouth (CC0 kenney rocks) instead of three thin wire rings.
	var game36 := _make_game()
	await process_frame
	await process_frame
	# 1. Rev 3 gate roof: 6 rows x 3 segments per slope (36 total,
	# two row tones), 7 ridge sections and 16 thin bronze eave teeth.
	# Swap (0.1.66): the procedural gatehouse roof (tile segments /
	# ridge sections / eave teeth) is retired; the gate is modeled
	# KayKit pieces now -- twin tower B + central castle keep.
	var gt_n36 := game36.find_child("GateTowerNorth", true, false)
	var gt_s36 := game36.find_child("GateTowerSouth", true, false)
	check("swap_gate_towers_modeled", gt_n36 != null and gt_s36 != null and not gt_n36.find_children("*", "MeshInstance3D", true, false).is_empty() and not gt_s36.find_children("*", "MeshInstance3D", true, false).is_empty())
	check("swap_gate_castle_exists", game36.find_child("GateCastle", true, false) != null)
	check("swap_gate_old_roof_gone", game36.find_children("GateTileSeg*", "MeshInstance3D", true, false).is_empty() and game36.find_children("GateRidgeSeg*", "MeshInstance3D", true, false).is_empty() and game36.find_child("GateRoofTilesWest", true, false) == null and game36.find_child("GateRoofTilesEast", true, false) == null)
	# 2. Rev 3 lintel: one thin beam + 3 lowered, wider brackets at
	# the tower heads + centre; 3 bearing caps bridge brackets to beam.
	check("residual_gate_lintel_gone", game36.find_child("GateLintel", true, false) == null and game36.find_child("GateLintelBeamLow", true, false) == null)
	check("residual_gate_lintel_frame", game36.find_child("GateLintelBeam", true, false) != null and game36.find_children("GateLintelBracket?", "MeshInstance3D", true, false).size() == 3)
	check("residual_gate_lintel_caps", game36.find_children("GateLintelBracketCap*", "MeshInstance3D", true, false).size() == 3)
	# 3. Rev 3 pads: separate 0.24/0.20 step faces, four bearing piers,
	# and inner/outer stone lips holding the flattened gold band in its groove.
	var step_low36 := game36.find_children("PadStepLow*", "MeshInstance3D", true, false)
	var step_high36 := game36.find_children("PadStepHigh*", "MeshInstance3D", true, false)
	check("residual_pad_steps", step_low36.size() == 10 and step_high36.size() == 10, "low=" + str(step_low36.size()) + " high=" + str(step_high36.size()))
	check("residual_pad_step_gone", game36.find_children("PadStep", "MeshInstance3D", true, false).is_empty())
	var pad0 := game36.find_child("BuildPad0", true, false)
	var pad_ring36 := pad0.find_child("PadRing", false, false) as MeshInstance3D
	var pad_torus36 := pad_ring36.mesh as TorusMesh
	# Rev 4 改判: the gold band sinks into its groove — z-scale
	# 0.30 -> 0.22 and y 0.57 -> 0.55 (radii unchanged).
	check("residual_pad_ring_band", is_equal_approx(pad_torus36.inner_radius, 1.18) and is_equal_approx(pad_torus36.outer_radius, 1.62) and pad_ring36.scale.is_equal_approx(Vector3(1.0, 1.0, 0.22)) and is_equal_approx(pad_ring36.position.y, 0.55))
	check("residual_pad_groove", game36.find_children("PadGroove", "MeshInstance3D", true, false).size() == 10, "n=" + str(game36.find_children("PadGroove", "MeshInstance3D", true, false).size()))
	check("residual_pad_piers", game36.find_children("PadPier*", "MeshInstance3D", true, false).size() == 40)
	check("residual_pad_lips", game36.find_children("PadGrooveLipIn", "MeshInstance3D", true, false).size() == 10 and game36.find_children("PadGrooveLipOut", "MeshInstance3D", true, false).size() == 10)
	var pad_low_mesh36 := (pad0.find_child("PadStepLow", false, false) as MeshInstance3D).mesh as CylinderMesh
	var pad_high_mesh36 := (pad0.find_child("PadStepHigh", false, false) as MeshInstance3D).mesh as CylinderMesh
	check("residual_pad_step_faces", is_equal_approx(pad_low_mesh36.height, 0.24) and is_equal_approx(pad_high_mesh36.height, 0.20))
	# 4. Rifts Rev 3: four gapped arcs per mesh, overlapping voids,
	# three receding energy faces, unchanged 14 mouth rocks per rift,
	# plus six doorway frame rocks per rift.
	# Rev 4: open the mouth by recessing central rubble and raising the smaller lintel.
	check("residual_rift_rings_gone", game36.find_children("RiftRing*", "MeshInstance3D", true, false).is_empty())
	check("residual_rift_vortex", game36.find_children("RiftVortexRing", "MeshInstance3D", true, false).size() == 2, "n=" + str(game36.find_children("RiftVortexRing", "MeshInstance3D", true, false).size()))
	check("residual_rift_core", game36.find_children("RiftCore", "MeshInstance3D", true, false).size() == 2)
	check("residual_rift_funnel", game36.find_children("RiftFunnel", "MeshInstance3D", true, false).size() == 2)
	check("residual_rift_mouth_rocks", game36.find_children("RiftMouthRock*", "Node3D", true, false).size() == 28, "n=" + str(game36.find_children("RiftMouthRock*", "Node3D", true, false).size()))
	check("residual_rift_rings_array", (game36.get("rift_rings") as Array).size() == 2)
	var rift_arcs_valid36 := true
	for ring36 in game36.find_children("RiftVortexRing", "MeshInstance3D", true, false):
		var mesh36: Mesh = (ring36 as MeshInstance3D).mesh
		if not mesh36 is ArrayMesh or mesh36.get_surface_count() < 1:
			rift_arcs_valid36 = false
		else:
			rift_arcs_valid36 = rift_arcs_valid36 and mesh36.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size() > 0
	check("residual_rift_arc_gaps", rift_arcs_valid36)
	check("residual_rift_inner_glow", game36.find_children("RiftInnerGlow", "MeshInstance3D", true, false).size() == 2)
	# Rev 4 改判: one extra side-wall rock pair per rift (idx 6/7) —
	# frame rocks 6 -> 8 per rift, total 12 -> 16.
	check("residual_rift_frame_rocks", game36.find_children("RiftFrameRock*", "Node3D", true, false).size() == 16)
	var mouth_center_n36 := game36.find_child("RiftMouthRockN12", true, false) as Node3D
	var mouth_center_s36 := game36.find_child("RiftMouthRockS12", true, false) as Node3D
	check("residual_rift_mouth_center_open", mouth_center_n36 != null and mouth_center_s36 != null and mouth_center_n36.global_position.x > 77.0 and mouth_center_s36.global_position.x > 77.0 and mouth_center_n36.global_position.y <= -0.9 and mouth_center_s36.global_position.y <= -0.9, "RiftMouthRockN12/S12: x > 77.0, y <= -0.9")
	var lintel_n36 := game36.find_child("RiftFrameRockN4", true, false) as Node3D
	var lintel_s36 := game36.find_child("RiftFrameRockS4", true, false) as Node3D
	check("residual_rift_lintel_raised", lintel_n36 != null and lintel_s36 != null and lintel_n36.global_position.y > 7.5 and lintel_s36.global_position.y > 7.5, "RiftFrameRockN4/S4: y > 7.5")
	check("residual_rift_void_b", game36.find_children("RiftVoidB", "MeshInstance3D", true, false).size() == 2)
	# 5. Rev 4 additions: staggered-bond seam evidence, lintel bearing
	# stack contact, stepped ridge caps, pad cap overhang + pier
	# bearing, groove walls standing above the sunken gold band, the
	# rift depth ladder and the bent pointed centre shard.
	# Swap (0.1.66): tile-bond stagger / tile-lip checks deleted with
	# the retired procedural roof.
	var beam36 := game36.find_child("GateLintelBeam", true, false) as MeshInstance3D
	var sill36 := game36.find_child("GateLintelSill", true, false) as MeshInstance3D
	var beam_bottom36 := beam36.position.y - (beam36.mesh as BoxMesh).size.y * 0.5
	var sill_top36 := sill36.position.y + (sill36.mesh as BoxMesh).size.y * 0.5
	check("residual_gate_lintel_sill", sill36 != null and absf(sill_top36 - beam_bottom36) <= 0.01 and (sill36.mesh as BoxMesh).size.x > (beam36.mesh as BoxMesh).size.x)
	check("residual_gate_lintel_posts", game36.find_children("GateLintelPost*", "MeshInstance3D", true, false).size() == 2)
	# Swap (0.1.66): ridge cap-step check deleted with the retired roof.
	var base_mesh36 := (pad0.find_child("PadBase", false, false) as MeshInstance3D).mesh as CylinderMesh
	check("residual_pad_cap_overhang", base_mesh36.bottom_radius > pad_high_mesh36.top_radius)
	var pier036 := pad0.find_child("PadPier0", false, false) as MeshInstance3D
	var pier_top36 := pier036.position.y + (pier036.mesh as BoxMesh).size.y * 0.5
	var pier_bottom36 := pier036.position.y - (pier036.mesh as BoxMesh).size.y * 0.5
	check("residual_pad_pier_bearing", absf(pier_top36 - 0.44) <= 0.01 and absf(pier_bottom36 - 0.24) <= 0.01)
	var lip_in36 := pad0.find_child("PadGrooveLipIn", false, false) as MeshInstance3D
	var lip_torus36 := lip_in36.mesh as TorusMesh
	var ring_top36 := pad_ring36.position.y + (pad_torus36.outer_radius - pad_torus36.inner_radius) * 0.5 * pad_ring36.scale.z
	var lip_top36 := lip_in36.position.y + (lip_torus36.outer_radius - lip_torus36.inner_radius) * 0.5 * lip_in36.scale.z
	check("residual_pad_groove_walls", lip_top36 > ring_top36 and ring_top36 - 0.58 <= 0.03, "ring_top=" + str(ring_top36) + " lip_top=" + str(lip_top36))
	check("residual_rift_shard", game36.find_children("RiftShard", "MeshInstance3D", true, false).size() == 2)
	var portal36 := game36.find_child("RiftPortal", true, false)
	var funnel36 := portal36.find_child("RiftFunnel", false, false) as MeshInstance3D
	var glow36 := portal36.find_child("RiftInnerGlow", false, false) as MeshInstance3D
	var core36 := portal36.find_child("RiftCore", false, false) as MeshInstance3D
	check("residual_rift_depth_ladder", funnel36.position.z <= -0.29 and glow36.position.z <= -0.50 and absf(core36.position.z) <= 0.10)
	game36.free()

	# --- Test 37 (画面效果优化 2026-11-14: 三国身份强化 Rev 1, LOOP_STATE) ---
	# Gate plaque 「劍閣」 + gold 「蜀」 on tower banners and all 20 field
	# flags; glowing lantern boxes replaced by real paper lanterns with
	# cords/brackets; upturned eave tips on the gatehouse roof; sloped
	# tile caps on the gate-wall and courtyard-wall merlons.
	var game37 := _make_game()
	await process_frame
	await process_frame
	# 1. Gate plaque: dark wood board + gold trims + hangers + gold text.
	var plaque37 := game37.find_child("GatePlaque", true, false) as MeshInstance3D
	check("identity_gate_plaque", plaque37 != null)
	var plaque_text37 := game37.find_child("GatePlaqueText", true, false) as Label3D
	check("identity_gate_plaque_text", plaque_text37 != null and plaque_text37.text == "劍閣" and plaque_text37.font_size == 56)
	check("identity_gate_plaque_hangers", game37.find_children("GatePlaqueHanger*", "MeshInstance3D", true, false).size() == 2)
	# 2. Watchtower banners: rotated to face south (was edge-on fin),
	# hung under the parapet, gold 「蜀」 on the face. (The GLB root
	# imports as "flag-banner-long2" — its inner mesh node keeps the
	# plain name — so match the instance roots by their Watchtower
	# parent, not by the plain name.)
	var banners37: Array = []
	for b37 in game37.find_children("flag-banner-long*", "Node3D", true, false):
		if (b37 as Node).get_parent().name.begins_with("Watchtower"):
			banners37.append(b37)
	check("identity_tower_banners", banners37.size() == 2, "n=" + str(banners37.size()))
	var banner_ok37 := banners37.size() == 2
	for b37 in banners37:
		var bn := b37 as Node3D
		if not (is_equal_approx(bn.rotation.y, PI / 2.0) and is_equal_approx(bn.position.y, 3.2) and is_equal_approx(bn.position.z, 1.78)):
			banner_ok37 = false
	check("identity_tower_banner_pose", banner_ok37)
	var tower_glyphs37 := game37.find_children("BannerGlyph", "Label3D", true, false)
	check("identity_tower_glyphs", tower_glyphs37.size() == 2 and (tower_glyphs37[0] as Label3D).text == "蜀" and (tower_glyphs37[1] as Label3D).text == "蜀", "n=" + str(tower_glyphs37.size()))
	# 3. Field flags: one gold 「蜀」 per flag (12 set-dressing + 4 plaza
	# + 2 forest + 2 gate = 20).
	var flag_glyphs37 := game37.find_children("FlagGlyph*", "Label3D", true, false)
	check("identity_flag_glyphs", flag_glyphs37.size() == 20, "n=" + str(flag_glyphs37.size()))
	var flag_text_ok37 := flag_glyphs37.size() == 20
	for f37 in flag_glyphs37:
		if (f37 as Label3D).text != "蜀":
			flag_text_ok37 = false
	check("identity_flag_glyph_text", flag_text_ok37)
	# Rev 3: glyphs are cloth-attached (billboard off, plane parallel
	# to the cloth) and sized to the band (pixel_size 0.0125).
	var flag_attach_ok37 := flag_glyphs37.size() == 20
	for f37 in flag_glyphs37:
		var fl := f37 as Label3D
		if fl.billboard != BaseMaterial3D.BILLBOARD_DISABLED or not is_equal_approx(fl.pixel_size, 0.0125):
			flag_attach_ok37 = false
	check("identity_flag_glyph_attached", flag_attach_ok37)
	# 4. Lanterns: 6 real fixtures (2 towers + 2 gate + tent + hunter),
	# each with body + 2 caps + rod; no glowing box left anywhere.
	# (The "LanternBody*" glob also matches the caps/rods, so count
	# bodies by their squashed-sphere mesh.)
	var lantern_bodies37 := 0
	for lb37 in game37.find_children("LanternBody*", "MeshInstance3D", true, false):
		if (lb37 as MeshInstance3D).mesh is SphereMesh:
			lantern_bodies37 += 1
	check("identity_lantern_bodies", lantern_bodies37 == 6, "n=" + str(lantern_bodies37))
	check("identity_lantern_rods", game37.find_children("*Rod", "MeshInstance3D", true, false).size() == 6, "n=" + str(game37.find_children("*Rod", "MeshInstance3D", true, false).size()))
	check("identity_lantern_caps", game37.find_children("*CapTop", "MeshInstance3D", true, false).size() == 6 and game37.find_children("*CapBottom", "MeshInstance3D", true, false).size() == 6)
	# Rev 3: the top cap flares into a hat brim wider than the body.
	var brim_ok37 := true
	for ct37 in game37.find_children("*CapTop", "MeshInstance3D", true, false):
		var cm37 := (ct37 as MeshInstance3D).mesh as CylinderMesh
		if cm37 == null or not is_equal_approx(cm37.bottom_radius, 0.31) or not is_equal_approx(cm37.height, 0.06):
			brim_ok37 = false
	check("identity_lantern_brim", brim_ok37)
	check("identity_lantern_rims", game37.find_children("*CapTopRim", "MeshInstance3D", true, false).size() == 6)
	var bottoms37 := game37.find_children("*CapBottom", "MeshInstance3D", true, false)
	var bottom_rim_ok37 := false
	if not bottoms37.is_empty():
		var bottom_mesh37 := (bottoms37[0] as MeshInstance3D).mesh as CylinderMesh
		bottom_rim_ok37 = bottom_mesh37 != null and is_equal_approx(bottom_mesh37.top_radius, 0.28)
	check("identity_lantern_bottom_rim", bottom_rim_ok37)
	check("identity_lantern_boxes_gone", game37.find_children("*LanternBox*", "MeshInstance3D", true, false).is_empty())
	check("identity_tower_lantern_bracket", game37.find_children("LanternBracket", "MeshInstance3D", true, false).size() == 2)
	# 5. Upturned eave corners on the gatehouse roof (4, kicked up).
	# Swap (0.1.66): eave tip/segment/roof-edge checks deleted -- the
	# upturned-eave assembly belonged to the retired procedural roof.
	check("identity_eave_rises_gone", game37.find_children("GateEaveRise*", "MeshInstance3D", true, false).is_empty())
	# Swap (0.1.66): eave lift-profile check deleted with the roof.
	# 6. Merlon caps: 20 gate-wall + 50 courtyard-wall = 70 sloped caps.
	var caps37 := game37.find_children("MerlonCap*", "MeshInstance3D", true, false)
	check("identity_merlon_caps", caps37.size() == 70, "n=" + str(caps37.size()))
	var cap_color37 := false
	if caps37.size() > 0:
		var cm := ((caps37[0] as MeshInstance3D).material_override as StandardMaterial3D).albedo_color
		cap_color37 = cm.is_equal_approx(Color.html("#3a4a63"))
	check("identity_merlon_cap_color", cap_color37)
	check("identity_cap_wedge_profile", not caps37.is_empty() and (caps37[0] as MeshInstance3D).mesh is ArrayMesh)
	# Rev 3: every cap carries a ridge roll and a drip lip.
	check("identity_cap_rolls", game37.find_children("CapRoll*", "MeshInstance3D", true, false).size() == 70, "n=" + str(game37.find_children("CapRoll*", "MeshInstance3D", true, false).size()))
	check("identity_cap_lips", game37.find_children("CapLip*", "MeshInstance3D", true, false).size() == 70, "n=" + str(game37.find_children("CapLip*", "MeshInstance3D", true, false).size()))
	var rolls37 := game37.find_children("CapRoll*", "MeshInstance3D", true, false)
	var roll_radius_ok37 := false
	if not rolls37.is_empty():
		var roll_mesh37 := (rolls37[0] as MeshInstance3D).mesh as CylinderMesh
		roll_radius_ok37 = roll_mesh37 != null and is_equal_approx(roll_mesh37.top_radius, 0.045)
	check("identity_cap_roll_radius", roll_radius_ok37)
	game37.free()

	# --- Test 38 (画面效果优化 2026-11-14: 单位可读性 Rev 1, LOOP_STATE) ---
	# Team rings under every unit (green defender / red enemy), bigger
	# HP bars with a pale border quad and brighter fills, hero-vs-minion
	# scale split (hero x1.22, enemy rank-and-file x0.93), warm enemy
	# tints (were blue), boss name labels (looked up but never created),
	# wider selection ring.
	var game38 := _make_game()
	await process_frame
	await process_frame
	game38.call("select_hero", 0)
	await process_frame
	var hero38: Node = game38.get("strategist")
	check("readability_hero_spawned", hero38 != null)
	var hero_ring38 := hero38.get_node_or_null("TeamRing") as MeshInstance3D
	check("readability_hero_ring", hero_ring38 != null)
	if hero_ring38 != null:
		var hrc := (hero_ring38.material_override as StandardMaterial3D).albedo_color
		check("readability_hero_ring_green", hrc.g > hrc.r and hrc.g > hrc.b, str(hrc))
	var hero_model38 := hero38.get_node_or_null("VisualRoot/PackModel") as Node3D
	check("readability_hero_scale", hero_model38 != null and is_equal_approx(hero_model38.scale.x, 1.05 * 1.22), str(hero_model38.scale.x if hero_model38 != null else -1.0))
	check("readability_hero_bar_size", is_equal_approx(float(hero38.get("hp_bar_width")), 1.75) and is_equal_approx(float(hero38.get("hp_bar_height")), 0.24))
	check("readability_bar_border", hero38.get_node_or_null("HpBar/HpBarBorder") != null)
	game38.call("_spawn_enemy_of_type", "infantry")
	await process_frame
	var enemies38: Array = game38.get("enemies")
	var inf38: Node = enemies38[enemies38.size() - 1]
	var inf_ring38 := inf38.get_node_or_null("TeamRing") as MeshInstance3D
	check("readability_enemy_ring", inf_ring38 != null)
	# Rev 2: the torus became a filled disc (QuadMesh, scale 1.45 ->
	# edge band at world 1.13-1.45, outside the 1.05 contact shadow).
	check("readability_ring_disc", inf_ring38 != null and inf_ring38.mesh is QuadMesh and is_equal_approx(inf_ring38.scale.x, 1.45))
	if inf_ring38 != null:
		var erc := (inf_ring38.material_override as StandardMaterial3D).albedo_color
		check("readability_enemy_ring_red", erc.r > erc.g and erc.r > erc.b, str(erc))
	var inf_model38 := inf38.get_node_or_null("VisualRoot/PackModel") as Node3D
	check("readability_enemy_scale", inf_model38 != null and is_equal_approx(inf_model38.scale.x, 1.05 * 0.93), str(inf_model38.scale.x if inf_model38 != null else -1.0))
	check("readability_hero_bigger", hero_model38 != null and inf_model38 != null and hero_model38.scale.x > inf_model38.scale.x * 1.2)
	check("readability_enemy_bar_size", is_equal_approx(float(inf38.get("hp_bar_width")), 1.6) and is_equal_approx(float(inf38.get("hp_bar_height")), 0.24))
	var etint: Color = ArticulatedUnit.MODEL_TINTS["enemy"]
	check("readability_enemy_tint_warm", etint.r > etint.b, str(etint))
	# Rev 3: enemy part tiers must separate in the unit's own override
	# materials — head brightest warm, weapons cooler (steel) than body.
	var rt_head := -1.0
	var rt_body := -1.0
	var rt_arm := -1.0
	var rt_weap_cool := -99.0
	var rt_body_cool := -99.0
	if inf_model38 != null:
		for rt_mi in inf_model38.find_children("*", "MeshInstance3D", true, false):
			var rt_mat := (rt_mi as MeshInstance3D).get_surface_override_material(0)
			if rt_mat is StandardMaterial3D:
				var rt_ac := (rt_mat as StandardMaterial3D).albedo_color
				var rt_lum := 0.299 * rt_ac.r + 0.587 * rt_ac.g + 0.114 * rt_ac.b
				var rt_nm := (rt_mi as MeshInstance3D).name.to_lower()
				if rt_nm.contains("head") or rt_nm.contains("hat"):
					rt_head = maxf(rt_head, rt_lum)
				elif rt_nm.contains("body"):
					rt_body = rt_lum
					rt_body_cool = rt_ac.b - rt_ac.r
				elif rt_nm.contains("arm"):
					rt_arm = maxf(rt_arm, rt_lum)
				elif rt_nm.contains("axe") or rt_nm.contains("shield"):
					rt_weap_cool = maxf(rt_weap_cool, rt_ac.b - rt_ac.r)
	check("readability_enemy_tiers", rt_head > rt_body + 0.04 and rt_body > 0.0, "head=" + str(rt_head) + " body=" + str(rt_body))
	check("readability_enemy_weapon_cool", rt_weap_cool > rt_body_cool + 0.08, "weap=" + str(rt_weap_cool) + " body=" + str(rt_body_cool))
	check("readability_enemy_brim", inf_model38 != null and not inf_model38.find_children("EnemyHatBrim", "MeshInstance3D", true, false).is_empty())
	check("readability_enemy_chest_gap", rt_body > rt_arm + 0.05 and rt_body > 0.0, "body=" + str(rt_body) + " arm=" + str(rt_arm))
	inf38.call("start_death")
	check("readability_ring_hides_on_death", inf_ring38 != null and not inf_ring38.visible)
	game38.call("_spawn_enemy_of_type", "boss")
	await process_frame
	var boss38: Node = null
	for e38 in game38.get("enemies"):
		if is_instance_valid(e38) and String(e38.get("archetype")) == "boss":
			boss38 = e38
	check("readability_boss_spawned", boss38 != null)
	if boss38 != null:
		var bl38 := boss38.get_node_or_null("NameLabel") as Label3D
		check("readability_boss_label", bl38 != null and bl38.text == "韩德", bl38.text if bl38 != null else "none")
		# Rev 2: label smaller (56) and floating clear above the bar.
		var bbar38 := boss38.get_node_or_null("HpBar") as Node3D
		check("readability_boss_label_gap", bl38 != null and bbar38 != null and bl38.font_size == 56 and bl38.position.y > bbar38.position.y + 1.66)
		check("readability_boss_ring", boss38.get_node_or_null("TeamRing") != null)
	# Rev 2: selection marker is a gold-white double ring (container).
	var sel38 := game38.get("selection_ring") as Node3D
	var sel_outer38 := sel38.get_node_or_null("SelectionRingOuter") as MeshInstance3D if sel38 != null else null
	var sel_mesh38 := sel_outer38.mesh as TorusMesh if sel_outer38 != null else null
	check("readability_selection_ring_size", sel_mesh38 != null and is_equal_approx(sel_mesh38.inner_radius, 1.04) and is_equal_approx(sel_mesh38.outer_radius, 1.42))
	check("readability_selection_double", sel38 != null and sel38.get_node_or_null("SelectionRingInner") != null)
	# Rev 3: the vertical beacon (pillar + chevron) is what makes the
	# selection独占 at full-field framing.
	check("readability_selection_beacon", sel38 != null and sel38.get_node_or_null("SelectionPillar") != null and sel38.get_node_or_null("SelectionChevron") != null)
	check("readability_selection_diamond", sel38 != null and sel38.get_node_or_null("SelectionDiamond") != null)
	check("readability_selection_pillar_core", sel38 != null and sel38.get_node_or_null("SelectionPillarCore") != null)
	var sel_diamond38 := sel38.get_node_or_null("SelectionDiamond") as MeshInstance3D if sel38 != null else null
	var sel_diamond_mesh38 := sel_diamond38.mesh as QuadMesh if sel_diamond38 != null else null
	check("readability_selection_diamond_size", sel_diamond_mesh38 != null and sel_diamond_mesh38.size.x >= 3.79, str(sel_diamond_mesh38.size.x) if sel_diamond_mesh38 != null else "none")
	var sel_core38 := sel38.get_node_or_null("SelectionPillarCore") as MeshInstance3D if sel38 != null else null
	var sel_core_mesh38 := sel_core38.mesh as CylinderMesh if sel_core38 != null else null
	check("readability_selection_core_reach", sel_core_mesh38 != null and sel_core_mesh38.height >= 4.4, str(sel_core_mesh38.height) if sel_core_mesh38 != null else "none")
	check("readability_enemy_chest_plate", inf_model38 != null and not inf_model38.find_children("EnemyChestPlate", "MeshInstance3D", true, false).is_empty())
	check("readability_enemy_blade_edge", inf_model38 != null and not inf_model38.find_children("EnemyBladeEdge", "MeshInstance3D", true, false).is_empty())
	var wr38 := game38.get("world_root") as Node3D
	var nc_sign38: Label3D = null
	var nc_line38: MeshInstance3D = null
	if wr38 != null:
		for nc_label38 in wr38.find_children("*", "Label3D", true, false):
			if (nc_label38 as Label3D).text == "新城":
				nc_sign38 = nc_label38 as Label3D
				break
		for nc_mesh38 in wr38.find_children("*", "MeshInstance3D", true, false):
			if nc_mesh38.name == "NewcityLeaderLine":
				nc_line38 = nc_mesh38 as MeshInstance3D
				break
	check("readability_newcity_sign_moved", nc_sign38 != null and nc_sign38.position.x > -55.0)
	check("readability_newcity_leader_line", nc_line38 != null)
	if sel_outer38 != null:
		var soc := (sel_outer38.material_override as StandardMaterial3D).albedo_color
		check("readability_selection_gold", soc.r > soc.g and soc.g > soc.b, str(soc))
	game38.free()

	# --- Test 39 (手游操作改版 2026-11-14: 摇杆+技能大钮+小地图;
	# 镜头 15:05 定跟随、同日 17:04 用户改定自由视角) ---
	var game39 := _make_game()
	await process_frame
	await process_frame
	if not bool(game39.get("_touch_ui")):
		check("controls_absent_on_desktop", game39.get("_joy") == null and game39.get("_minimap") == null and game39.get("_big_skill_button") == null)
	else:
		check("controls_widgets_exist", game39.get("_joy") != null and game39.get("_minimap") != null and game39.get("_big_skill_button") != null)
		game39.call("select_hero", 0)
		await process_frame
		await process_frame
		var big39: Button = game39.get("_big_skill_button")
		check("controls_big_skill_shows_hero_skill", big39 != null and big39.text == "残影剑", "text=" + (big39.text if big39 != null else "null"))
		var vp39 := game39.get_viewport().get_visible_rect().size
		var strat39: Node3D = game39.get("strategist")
		var joy_origin := vp39 * Vector2(0.20, 0.70)
		# Joystick: press in the lower-left zone engages, drag right
		# drives the hero +x, release stops him.
		game39.call("_unhandled_input", _touch_event(0, joy_origin, true))
		check("controls_joystick_engages", int(game39.get("_joy_index")) == 0)
		for i in range(5):
			game39.call("_unhandled_input", _drag_event(0, joy_origin + Vector2(26.0 * float(i + 1), 0), Vector2(26, 0)))
		var hx0 := strat39.global_position.x
		await create_timer(0.6).timeout
		check("controls_joystick_drives_hero", strat39.global_position.x > hx0 + 1.0, "x %.1f -> %.1f" % [hx0, strat39.global_position.x])
		game39.call("_unhandled_input", _touch_event(0, joy_origin + Vector2(130, 0), false))
		await create_timer(0.25).timeout
		var hx1 := strat39.global_position.x
		await create_timer(0.35).timeout
		check("controls_joystick_release_stops", absf(strat39.global_position.x - hx1) < 0.4, "x %.1f -> %.1f" % [hx1, strat39.global_position.x])
		# Free camera (user call 2026-11-14 17:04, replacing the
		# follow camera chosen at 15:05): the hero ran +x under the
		# joystick, yet the camera target never left the default view.
		await create_timer(0.8).timeout
		var tgt39: Vector3 = game39.get("cam_target")
		check("controls_camera_free_no_follow", tgt39.distance_to(Vector3(-24, 0, 0)) < 0.6, "target=" + str(tgt39) + " hero=" + str(strat39.global_position))
		# A battlefield drag (outside the joystick zone) pans the
		# camera, and the pan persists — no spring-back, no re-centre.
		game39.call("_unhandled_input", _touch_event(1, vp39 * Vector2(0.72, 0.45), true))
		for i in range(4):
			game39.call("_unhandled_input", _drag_event(1, vp39 * Vector2(0.72, 0.45) + Vector2(-30.0 * float(i + 1), 0), Vector2(-30, 0)))
		game39.call("_unhandled_input", _touch_event(1, vp39 * Vector2(0.72, 0.45) + Vector2(-120, 0), false))
		var tgt39b: Vector3 = game39.get("cam_target")
		check("controls_camera_pan_moves", tgt39b.distance_to(tgt39) > 2.0, "from=" + str(tgt39) + " to=" + str(tgt39b))
		await create_timer(0.8).timeout
		var tgt39c: Vector3 = game39.get("cam_target")
		check("controls_camera_pan_persists", tgt39c.distance_to(tgt39b) < 0.3, "target=" + str(tgt39c))
		game39.call("reset_camera_view")
		# A quick tap inside the joystick zone still resolves as a tap
		# (move order), it must not be swallowed by the joystick.
		var marker39: Node3D = game39.get("move_marker")
		marker39.visible = false
		game39.set("selected", true)
		game39.call("_unhandled_input", _touch_event(0, joy_origin, true))
		game39.call("_unhandled_input", _touch_event(0, joy_origin, false))
		await process_frame
		check("controls_tap_in_joy_zone_still_taps", marker39.visible)
	game39.free()

	# --- Test 40 （边缘与远景 Rev 1, 2026-11-14): outer apron seals
	# the void, a mid ridge ring adds the missing depth step, corner
	# masses close the rim junctions, fog becomes a depth ramp. -----
	var game40 := _make_game()
	await process_frame
	await process_frame
	check("edge_apron_exists", game40.find_child("OuterApron", true, false) != null)
	check("edge_ridge_ring_count", game40.find_children("FarRidge*", "Node3D", true, false).size() == 16, "n=" + str(game40.find_children("FarRidge*", "Node3D", true, false).size())) # 边缘 Rev 4 改判: 北扇区 7 座合并为 3 条长脊, 20-7+3=16
	check("edge_corner_masses_added", game40.find_children("RockWallMass*", "Node3D", true, false).size() >= 144, "n=" + str(game40.find_children("RockWallMass*", "Node3D", true, false).size())) # 边缘 Rev 4 改判: 与 rim 总数同步 (144)
	var env40: Environment = (game40.get("env_ref") as Environment)
	# Rev 4 改判依据：明度型空气透视微调 density 0.0105->0.0100、雾色 #2c3850->#303f5e，使远层向亮退、近层保持反差（0.0070/0.0085 两轮激进迭代均全帧洗白，已回调定版）。
	check("edge_fog_strengthened", env40 != null and env40.fog_mode == Environment.FOG_MODE_EXPONENTIAL and is_equal_approx(env40.fog_density, 0.0100), "density=" + str(env40.fog_density))
	# Rev 2 (Codex 首审 3.5/10): talus ramps at every rim foot, the
	# south outer descent, rolling outer slabs, and a bigger, more
	# distant, haze-flattened far ring.
	for talus_name in ["NorthTalus", "SouthTalus", "EastTalus", "WestTalus", "SouthOuterSlope"]:
		check("edge_talus_" + talus_name.to_lower(), game40.find_child(talus_name, true, false) != null)
	check("edge_outer_slabs", game40.find_children("OuterSlab*", "MeshInstance3D", true, false).size() == 12, "n=" + str(game40.find_children("OuterSlab*", "MeshInstance3D", true, false).size()))
	var far_ok := true
	for fnode in game40.find_children("FarMountainFar*", "Node3D", true, false):
		var fp := (fnode as Node3D).global_position
		# Mountain pull-in reverted (user 2026-11-17 22:30): the
		# composition round's backdrop-band exception for members
		# 11/12 is rolled back - every far member is checked against
		# the original push-out radius again.
		if maxf(absf(fp.x), absf(fp.z)) < 130.0:
			far_ok = false
	check("edge_far_ring_pushed_out", far_ok)
	var masses40 := game40.find_children("RockWallMass*", "Node3D", true, false).size()
	check("edge_rim_gap_mass_count", masses40 == 144, "n=" + str(masses40)) # 边缘 Rev 4 改判: 缺口双排对齐加宽, 前排 -2 后排 -4, 合计 150-6=144
	var shoulders40 := game40.find_children("CornerShoulder*", "MeshInstance3D", true, false).size()
	check("edge_corner_shoulders", shoulders40 == 4, "n=" + str(shoulders40))
	var h_top40: float = game40.call("_cliff_height", 0.0, 74.0, 8)
	var h_bot40: float = game40.call("_cliff_height", 0.0, 116.0, 8)
	var h_a40: float = game40.call("_cliff_height", 0.0, 74.0 + 42.0 * 0.16, 8)
	var h_b40: float = game40.call("_cliff_height", 0.0, 74.0 + 42.0 * 0.26, 8)
	var h_8540: float = game40.call("_cliff_height", 0.0, 85.0, 8)
	var h_9540: float = game40.call("_cliff_height", 0.0, 95.0, 8)
	var h_10540: float = game40.call("_cliff_height", 0.0, 105.0, 8)
	var terrace_ok40 := h_top40 > 7.4 and h_bot40 < 0.4 and absf(h_a40 - h_b40) < 1.0 and h_8540 >= h_9540 - 0.6 and h_9540 >= h_10540 - 0.6
	check("edge_south_terrace_profile", terrace_ok40, "heights=" + str([h_top40, h_bot40, h_a40, h_b40, h_8540, h_9540, h_10540]))
	var ridge_nodes40 := game40.find_children("FarRidge*", "Node3D", true, false)
	var ridge_avg40 := Vector3.ZERO
	for ridge_node40 in ridge_nodes40:
		var ridge_color40: Color = _sampled_albedo(ridge_node40)
		ridge_avg40 += Vector3(ridge_color40.r, ridge_color40.g, ridge_color40.b)
	ridge_avg40 /= float(maxi(ridge_nodes40.size(), 1))
	check("edge_ridge_fog_premix_40", absf(ridge_avg40.x - 0.370) < 0.035 and absf(ridge_avg40.y - 0.392) < 0.035 and absf(ridge_avg40.z - 0.460) < 0.035, "avg=" + str(ridge_avg40)) # Rev 4: 按新材质解析计算的中心值，容差 0.035 不变
	var far_nodes40 := game40.find_children("FarMountainFar*", "Node3D", true, false)
	var far_avg40 := Vector3.ZERO
	for far_node40 in far_nodes40:
		var far_color40: Color = _sampled_albedo(far_node40)
		far_avg40 += Vector3(far_color40.r, far_color40.g, far_color40.b)
	far_avg40 /= float(maxi(far_nodes40.size(), 1))
	check("edge_far_silhouette_avg", far_avg40.distance_to(Vector3(0.375, 0.479, 0.678)) < 0.095, "avg=" + str(far_avg40)) # Rev 4: 按新材质解析计算的远层均值，容差 0.095 不变
	game40.free()

	# --- Test 41 (炼化合成 2026-11-14: 第二阶段首项, LOOP_STATE) --------
	# TEARDOWN §5 / PARITY §5, ported from the 2D v2 refiner: materials
	# are bought into the bag, set pieces forge for fee + materials,
	# completing a 3-piece set applies its bonus, exclusives forge for
	# 600 + 龙鳞x1 玄铁x1 and the owner's skill power becomes x1.3.
	var gameR := _make_game()
	await process_frame
	await process_frame
	check("refine_stock_five_materials", (gameR.call("shop_stock", "refine") as Array).size() == 5)
	check("refine_sets_six", (gameR.get("REFINE_SETS") as Array).size() == 6)
	check("refine_exclusives_15", (gameR.get("REFINE_EXCLUSIVES") as Array).size() == 15)
	gameR.call("select_hero", 0) # 赵统 — owner of 青釭剑
	await process_frame
	var heroR: Node = gameR.get("strategist")
	check("refine_hero_present", heroR != null)
	if heroR != null:
		var base_dmgR := float(heroR.get("attack_damage"))
		gameR.set("gold", 5000)
		gameR.call("_open_shop_panel", 7) # 炼化师 is shop_defs[7] (trainer took 6)
		await process_frame
		check("refine_panel_visible", bool((gameR.get("shop_panel") as Node).get("visible")))
		check("refine_panel_rows", (gameR.get("shop_items_box") as Node).get_child_count() >= 38, "rows=" + str((gameR.get("shop_items_box") as Node).get_child_count()))
		# Buy the 青龙套 sword recipe: 龙鳞x2 + 玄铁x1 at 80 each.
		gameR.call("_on_shop_buy", "mat_longlin")
		gameR.call("_on_shop_buy", "mat_longlin")
		gameR.call("_on_shop_buy", "mat_xuantie")
		check("refine_mat_gold", int(gameR.get("gold")) == 5000 - 240, "gold=" + str(gameR.get("gold")))
		check("refine_mat_bag3", (gameR.get("hero_inventory") as Array).size() == 3)
		check("refine_mat_count", int(gameR.call("refine_material_count", "龙鳞")) == 2)
		# Forge piece 1: fee 350, materials consumed, stats land.
		check("refine_craft_sword", bool(gameR.call("refine_craft_set", "青龙套", "青龙偃月刀·套")))
		check("refine_craft_gold", int(gameR.get("gold")) == 4760 - 350, "gold=" + str(gameR.get("gold")))
		check("refine_craft_mats_gone", int(gameR.call("refine_material_count", "龙鳞")) == 0 and int(gameR.call("refine_material_count", "玄铁")) == 0)
		check("refine_craft_bag1", (gameR.get("hero_inventory") as Array).size() == 1)
		check("refine_craft_dmg", is_equal_approx(float(heroR.get("attack_damage")), base_dmgR + 35.0), "dmg=" + str(heroR.get("attack_damage")))
		check("refine_set_count1", int(gameR.call("refine_set_count", "青龙套")) == 1)
		# Re-forge of an owned piece and forging without materials refuse.
		check("refine_recraft_refused", not bool(gameR.call("refine_craft_set", "青龙套", "青龙偃月刀·套")))
		check("refine_nomats_refused", not bool(gameR.call("refine_craft_set", "青龙套", "青鳞战甲")))
		check("refine_refusals_keep_gold", int(gameR.get("gold")) == 4410, "gold=" + str(gameR.get("gold")))
		# Forge pieces 2 and 3; the third completes the set bonus.
		for repR in range(2):
			gameR.call("_on_shop_buy", "mat_longlin")
			gameR.call("_on_shop_buy", "mat_longlin")
			gameR.call("_on_shop_buy", "mat_xuantie")
			var pieceR := "青鳞战甲" if repR == 0 else "龙魂玉"
			check("refine_craft_piece_" + str(repR + 2), bool(gameR.call("refine_craft_set", "青龙套", pieceR)))
		check("refine_set_count3", int(gameR.call("refine_set_count", "青龙套")) == 3)
		check("refine_set_bonus_str", is_equal_approx(float(gameR.get("hero_bonus_str")), 12.0 + 14.0 + 15.0), "str=" + str(gameR.get("hero_bonus_str")))
		check("refine_set_bonus_dmg", is_equal_approx(float(gameR.get("hero_bonus_damage")), 35.0 + 15.0), "b=" + str(gameR.get("hero_bonus_damage")))
		check("refine_gold_after_set", int(gameR.get("gold")) == 3230, "gold=" + str(gameR.get("gold")))
		# Exclusive for the fielded hero: 青釭剑 （赵统）.
		check("refine_mul_before_excl", is_equal_approx(float(gameR.call("hero_skill_mul")), 1.0))
		gameR.call("_on_shop_buy", "mat_longlin")
		gameR.call("_on_shop_buy", "mat_xuantie")
		check("refine_craft_excl", bool(gameR.call("refine_craft_exclusive", "青釭剑")))
		check("refine_excl_gold", int(gameR.get("gold")) == 3230 - 160 - 600, "gold=" + str(gameR.get("gold")))
		check("refine_has_exclusive", bool(gameR.call("hero_has_exclusive")))
		check("refine_mul_after_excl", is_equal_approx(float(gameR.call("hero_skill_mul")), 1.3))
		check("refine_crafted_count4", int(gameR.get("crafted_count")) == 4, "n=" + str(gameR.get("crafted_count")))
		# Materials in the bag explain themselves and are not consumed.
		gameR.call("_on_shop_buy", "mat_lianhua")
		var lianhua_slot := -1
		var invR: Array = gameR.get("hero_inventory")
		for iR in range(invR.size()):
			if String((invR[iR] as Dictionary).get("name", "")) == "炼化石":
				lianhua_slot = iR
		check("refine_lianhua_in_bag", lianhua_slot >= 0)
		if lianhua_slot >= 0:
			gameR.call("_use_inventory_item", lianhua_slot)
			check("refine_material_not_consumed", (gameR.get("hero_inventory") as Array).size() == invR.size())
			check("refine_material_hint", String((gameR.get("message_label") as Label).text).contains("炼化师"))
		# Insufficient gold refuses a material purchase cleanly.
		gameR.set("gold", 10)
		var bag_before_poor := (gameR.get("hero_inventory") as Array).size()
		gameR.call("_on_shop_buy", "mat_longlin")
		check("refine_poor_refused", int(gameR.get("gold")) == 10 and (gameR.get("hero_inventory") as Array).size() == bag_before_poor)
		# Restart wipes the forge state with the bag.
		gameR.call("reset_game")
		check("refine_reset_state", int(gameR.get("crafted_count")) == 0 and (gameR.get("hero_inventory") as Array).size() == 0)
	gameR.free()

	# --- Test 41b: the exclusive multiplier moves real skill damage. ---
	# 姜维 （鼎文杖 owner, no crit/lifesteal passive) casts 烈火燎原 on a
	# boss foe before and after forging; the second hit must carry both
	# the staff's int and the x1.3 skill multiplier.
	var gameS := _make_game()
	await process_frame
	await process_frame
	gameS.call("select_hero", 3) # 姜维
	await process_frame
	var heroS: Node = gameS.get("strategist")
	check("refine_skill_hero_present", heroS != null)
	if heroS != null:
		gameS.set("gold", 5000)
		gameS.call("_open_shop_panel", 7)
		await process_frame
		gameS.call("_on_shop_buy", "mat_longlin")
		gameS.call("_on_shop_buy", "mat_xuantie")
		var foeS: Node = gameS.call("_spawn_enemy_of_type", "boss")
		check("refine_skill_foe_ready", foeS != null)
		if foeS != null:
			foeS.set("global_position", (heroS as Node3D).global_position + Vector3(5, 0, 0))
			var main1 := float((gameS.call("hero_stats_at", 3, 1) as Dictionary)["main"])
			var hp0 := float(foeS.get("hp"))
			gameS.set("skill_cooldown", 0.0)
			var hits1 := int(gameS.call("cast_hero_skill"))
			var drop1 := hp0 - float(foeS.get("hp"))
			check("refine_skill_base_hit", hits1 >= 1 and is_equal_approx(drop1, 22.0 + main1 * 1.15), "drop=" + str(drop1) + " want=" + str(22.0 + main1 * 1.15))
			check("refine_skill_forge", bool(gameS.call("refine_craft_exclusive", "鼎文杖")))
			foeS.set("hp", float(foeS.get("max_hp")))
			var main2 := float((gameS.call("hero_stats_at", 3, 1) as Dictionary)["main"])
			var hp1 := float(foeS.get("hp"))
			gameS.set("skill_cooldown", 0.0)
			var hits2 := int(gameS.call("cast_hero_skill"))
			var drop2 := hp1 - float(foeS.get("hp"))
			check("refine_skill_boosted_hit", hits2 >= 1 and absf(drop2 - (22.0 + main2 * 1.15) * 1.3) < 0.75, "drop=" + str(drop2) + " want=" + str((22.0 + main2 * 1.15) * 1.3))
	gameS.free()

	# --- Test 42: training rooms + growth gear (stage 2) ---------------
	# 2D rules at the 1/10 price scale: brush entry 50 raises the
	# officer level and batches soldiers in; boss entry 300 spawns the
	# training boss; its drop pays a growth item (65%) or gold (35%);
	# growth items level per 40 hero kills (cap 20).
	var gameT := _make_game()
	await process_frame
	await process_frame
	gameT.call("select_hero", 0)
	await process_frame
	var stratT: Node = gameT.get("strategist")
	gameT.set("gold", 1000)
	check("trainer_registered_as_shop", (gameT.get("shop_defs") as Array).size() == 8 and String(((gameT.get("shop_defs") as Array)[6] as Dictionary).get("kind", "")) == "trainer", "defs=" + str((gameT.get("shop_defs") as Array).size()))
	gameT.call("_open_shop_panel", 6)
	await process_frame
	check("trainer_panel_opens", bool(gameT.get("shop_panel").get("visible")) and String(gameT.get("shop_title").get("text")).contains("训练长官"), "title=" + String(gameT.get("shop_title").get("text")))
	gameT.call("_close_shop_panel")
	check("trainer_brush_enter_ok", bool(gameT.call("trainer_enter", "brush")), "")
	check("trainer_brush_fee_and_level", int(gameT.get("gold")) == 950 and int(gameT.get("train_level")) == 1 and bool(gameT.get("brush_session")), "gold=" + str(gameT.get("gold")) + " lvl=" + str(gameT.get("train_level")))
	check("trainer_brush_teleports_into_pen", stratT.global_position.distance_to(Vector3(-52, 0, 33)) < 1.0, "pos=" + str(stratT.global_position))
	check("trainer_brush_batch_spawns", int(gameT.call("_alive_trainee_count")) == 3, "alive=" + str(gameT.call("_alive_trainee_count")))
	check("trainer_brush_reentry_refused", not bool(gameT.call("trainer_enter", "brush")) and int(gameT.get("gold")) == 950, "")
	stratT.set("global_position", Vector3(0, 0, 0))
	var brush_ended: bool = await wait_until(func() -> bool: return not bool(gameT.get("brush_session")), 3.0)
	check("trainer_brush_exit_ends_session", brush_ended and int(gameT.call("_alive_trainee_count")) == 0, "alive=" + str(gameT.call("_alive_trainee_count")))
	check("trainer_boss_enter_ok", bool(gameT.call("trainer_enter", "boss")) and int(gameT.get("gold")) == 650, "gold=" + str(gameT.get("gold")))
	var tboss: Node = gameT.get("train_boss")
	check("trainer_boss_spawned", tboss != null and bool(tboss.get("alive")), "")
	stratT.set("global_position", Vector3(0, 0, 0))
	var boss_ended: bool = await wait_until(func() -> bool: return not bool(gameT.get("boss_session")), 3.0)
	check("trainer_boss_exit_flees", boss_ended and gameT.get("train_boss") == null, "")
	gameT.set("boss_session", true)
	var bag_before := (gameT.get("hero_inventory") as Array).size()
	gameT.call("training_boss_drop", 0.5)
	var bagT: Array = gameT.get("hero_inventory")
	check("trainer_drop_growth_item", bagT.size() == bag_before + 1 and (bagT[bagT.size() - 1] as Dictionary).has("growth"), "bag=" + str(bagT.size()))
	gameT.set("boss_session", true)
	var goldT := int(gameT.get("gold"))
	gameT.call("training_boss_drop", 0.9)
	check("trainer_drop_miss_pays_gold", int(gameT.get("gold")) == goldT + 200 and not bool(gameT.get("boss_session")), "gold=" + str(gameT.get("gold")))
	var git: Dictionary = gameT.call("make_growth_item", "方天画戟")
	(gameT.get("hero_inventory") as Array).append(git)
	gameT.call("_apply_item_effect", git)
	git["kills"] = 39
	var dmg_before := float(gameT.get("hero_bonus_damage"))
	gameT.call("training_spawn_brush_batch")
	var trT: Node = (gameT.get("trainees") as Array)[0]
	gameT.call("apply_damage", stratT, trT, 99999.0)
	await process_frame
	check("growth_kill_counted", int(git.get("kills", 0)) == 40, "kills=" + str(git.get("kills", 0)))
	check("growth_level_up_applies", int(git.get("level", 0)) == 1 and is_equal_approx(float(gameT.get("hero_bonus_damage")), dmg_before + 2.0), "dmg " + str(dmg_before) + " -> " + str(gameT.get("hero_bonus_damage")))
	gameT.set("train_level", 5)
	gameT.set("brush_session", true)
	gameT.call("reset_game")
	await process_frame
	check("training_state_reset", int(gameT.get("train_level")) == 0 and not bool(gameT.get("brush_session")) and not bool(gameT.get("boss_session")), "")
	gameT.free()

	# --- Test 43: quest chain (stage 2) -------------------------------
	# The 2D catalogue on 3D machinery: wild/challenge units outside
	# `enemies`, NPC talks via quest_npc_interact, tokens in the bag.
	var gameQ := _make_game()
	await process_frame
	await process_frame
	gameQ.call("select_hero", 0)
	await process_frame
	var stratQ: Node = gameQ.get("strategist")
	gameQ.set("gold", 1000)
	check("quest_catalog_twelve", (gameQ.get("QUEST_DEFS") as Array).size() == 12, "defs=" + str((gameQ.get("QUEST_DEFS") as Array).size()))
	check("quest_npcs_five", (gameQ.get("quest_npc_defs") as Array).size() == 5, "")
	check("quest_wilds_spawned", (gameQ.get("wilds") as Array).size() >= 13, "wilds=" + str((gameQ.get("wilds") as Array).size()))
	var banditQ: Node = null
	var motherQ: Node = null
	var xuanwuQ: Node = null
	var yaoshuQ: Node = null
	var xiangyuQ: Node = null
	var hunQ: Node = null
	for wd in gameQ.get("wilds"):
		var k := String(wd.get_meta("wild_kind", "")) if wd.has_meta("wild_kind") else ""
		if k == "bandit":
			banditQ = wd
		elif k == "bloodmother":
			motherQ = wd
		elif k == "xuanwu":
			xuanwuQ = wd
		elif k == "yaoshu":
			yaoshuQ = wd
		elif k == "xiangyu":
			xiangyuQ = wd
		elif k == "hunboss":
			hunQ = wd
	gameQ.call("apply_damage", stratQ, banditQ, 99999.0)
	check("quest_bandit_revives_once", bool(banditQ.get("alive")) and float(banditQ.get("hp")) > 0.5 * float(banditQ.get("max_hp")), "hp=" + str(banditQ.get("hp")))
	gameQ.call("apply_damage", stratQ, banditQ, 99999.0)
	await process_frame
	check("quest_bandit_head_drops", not bool(banditQ.get("alive")) and bool(gameQ.call("has_hero_item", "人头")), "")
	gameQ.call("quest_npc_interact", "cunzh")
	check("quest_qiangdao_done_reward", String(gameQ.call("qstate", "qiangdao")) == "done" and not bool(gameQ.call("has_hero_item", "人头")), "")
	gameQ.call("quest_npc_interact", "laotou")
	check("quest_dudan_gate_holds", String(gameQ.call("qstate", "dudan")) == "no", "")
	gameQ.set("train_level", 7)
	gameQ.call("quest_npc_interact", "laotou")
	check("quest_dudan_accepted", String(gameQ.call("qstate", "dudan")) == "on", "")
	gameQ.call("apply_damage", stratQ, motherQ, 99999.0)
	check("quest_gland_drops", bool(gameQ.call("has_hero_item", "毒腺")), "")
	gameQ.call("quest_npc_interact", "laotou")
	check("quest_dudan_reward", String(gameQ.call("qstate", "dudan")) == "done" and bool(gameQ.call("has_hero_item", "徐夫人")), "")
	var genQ: Node = gameQ.get("general")
	var gen_dmg := float(genQ.get("attack_damage"))
	gameQ.call("apply_damage", stratQ, xuanwuQ, 99999.0)
	check("quest_yuxi_drops", bool(gameQ.call("has_hero_item", "玉玺")), "")
	gameQ.call("quest_npc_interact", "kongming")
	check("quest_yuxi_empowers_general", String(gameQ.call("qstate", "yuxi")) == "done" and int(gameQ.get("general_level")) == 3 and is_equal_approx(float(genQ.get("attack_damage")), gen_dmg + 8.0), "lvl=" + str(gameQ.get("general_level")))
	var mark_slotQ := -1
	var bagQ0: Array = gameQ.get("hero_inventory")
	for i in range(bagQ0.size()):
		if String((bagQ0[i] as Dictionary).get("name", "")) == "圣痕·玄武":
			mark_slotQ = i
	gameQ.call("_use_inventory_item", mark_slotQ)
	check("quest_mark_summons_xuanwu", mark_slotQ >= 0 and (gameQ.get("saints_active") as Array).size() == 1, "slot=" + str(mark_slotQ))
	gameQ.set("letter_pending", true)
	gameQ.call("quest_npc_interact", "kongming")
	check("quest_letter_received", bool(gameQ.call("has_hero_item", "书信")) and not bool(gameQ.get("letter_pending")), "")
	gameQ.call("quest_npc_interact", "mengda")
	check("quest_xincheng_protect_starts", String(gameQ.call("qstate", "xincheng")) == "on2" and gameQ.get("mengda_unit") != null, "")
	var xuhuangQ: Node = null
	for wd2 in gameQ.get("wilds"):
		if wd2.has_meta("wild_kind") and String(wd2.get_meta("wild_kind", "")) == "xuhuang":
			xuhuangQ = wd2
	check("quest_xuhuang_hunts", xuhuangQ != null, "")
	gameQ.call("apply_damage", stratQ, xuhuangQ, 99999.0)
	await process_frame
	check("quest_xincheng_done", String(gameQ.call("qstate", "xincheng")) == "done", "")
	gameQ.call("apply_damage", stratQ, yaoshuQ, 99999.0)
	check("quest_yaoshu_swords", bool(gameQ.call("has_hero_item", "斩蛇剑")) and bool(gameQ.call("has_hero_item", "轩辕剑")) and String(gameQ.call("qstate", "xuanyuan")) == "on", "")
	gameQ.call("apply_damage", stratQ, xiangyuQ, 99999.0)
	check("quest_xiangyu_drops_po", bool(gameQ.call("has_hero_item", "魄")), "")
	check("quest_bless_works", bool(gameQ.call("xuanyuan_bless")) and bool(gameQ.call("has_hero_item", "开光轩辕剑")) and String(gameQ.call("qstate", "xuanyuan")) == "done", "")
	gameQ.call("apply_damage", stratQ, hunQ, 99999.0)
	check("quest_soul_drops", bool(gameQ.call("has_hero_item", "魂")), "")
	var soul_slot := -1
	var bagQ: Array = gameQ.get("hero_inventory")
	for i in range(bagQ.size()):
		if String((bagQ[i] as Dictionary).get("name", "")) == "魂":
			soul_slot = i
	gameQ.call("_use_inventory_item", soul_slot)
	var hpQ := float(stratQ.get("hp"))
	gameQ.set("game_state", "battle")
	var dealtQ: float = gameQ.call("apply_damage", stratQ, stratQ, 50.0)
	check("quest_soul_invulnerable", float(gameQ.get("soul_timer")) > 7.0 and is_equal_approx(dealtQ, 0.0) and is_equal_approx(float(stratQ.get("hp")), hpQ), "dealt=" + str(dealtQ))
	gameQ.set("hides_n", 2)
	gameQ.set("hides_f", 1)
	var goldQ := int(gameQ.get("gold"))
	gameQ.call("quest_npc_interact", "hunter")
	check("quest_hides_sold", int(gameQ.get("gold")) == goldQ + 700 and int(gameQ.get("hides_n")) == 0 and int(gameQ.get("hides_f")) == 0, "gold=" + str(gameQ.get("gold")))
	var hides0 := int(gameQ.get("hides_n")) + int(gameQ.get("hides_f"))
	for i in range(60):
		gameQ.call("_on_wild_death", "beast", stratQ)
	check("quest_beast_hide_drops", int(gameQ.get("hides_n")) + int(gameQ.get("hides_f")) > hides0, "hides=" + str(int(gameQ.get("hides_n")) + int(gameQ.get("hides_f"))))
	gameQ.call("spawn_escort_event")
	check("quest_escort_spawns", (gameQ.get("villagers") as Array).size() == 4 and bool(gameQ.get("escort_active")), "villagers=" + str((gameQ.get("villagers") as Array).size()))
	var saved0 := int(gameQ.get("saved_villagers"))
	var goldE := int(gameQ.get("gold"))
	((gameQ.get("villagers") as Array)[0] as Node).set("global_position", Vector3(-63, 0, 2))
	var saved_ok: bool = await wait_until(func() -> bool: return int(gameQ.get("saved_villagers")) >= saved0 + 1, 3.0)
	check("quest_villager_saved_pays", saved_ok and int(gameQ.get("gold")) == goldE + 30, "saved=" + str(gameQ.get("saved_villagers")) + " gold=" + str(gameQ.get("gold")))
	gameQ.call("_open_quest_panel")
	await process_frame
	check("quest_panel_lists_all", bool(gameQ.get("quest_panel").get("visible")) and (gameQ.get("quest_box") as Node).get_child_count() >= 24, "rows=" + str((gameQ.get("quest_box") as Node).get_child_count()))
	gameQ.call("reset_game")
	await process_frame
	var wilds_back: bool = await wait_until(func() -> bool: return (gameQ.get("wilds") as Array).size() >= 13, 3.0)
	check("quest_state_reset", String(gameQ.call("qstate", "yuxi")) == "no" and int(gameQ.get("saved_villagers")) == 0 and not bool(gameQ.get("letter_pending")) and wilds_back, "wilds=" + str((gameQ.get("wilds") as Array).size()))
	gameQ.free()

	# --- Test 44: casino (stage 2) + village-chief single reward --------
	# 2D gamble (game/index.html): 500 gold/pull, 3% saint beast, 7%
	# consumable, 20% premium, else tier gear. This slice swaps the 500
	# gold for 1 free chip (SOL design doc red line 1: chips are
	# independent — never bought with gold, never converted to gold).
	var game44 := _make_game()
	await process_frame
	await process_frame
	game44.call("select_hero", 0)
	await process_frame
	var casinoCSidx := -1
	var merc_idx := -1
	for i in range((game44.get("shop_defs") as Array).size()):
		var k44 := String(((game44.get("shop_defs") as Array)[i] as Dictionary).get("kind", ""))
		if k44 == "casino":
			casinoCSidx = i
		elif k44 == "mercenary":
			merc_idx = i
	check("casino_shop_index", casinoCSidx == 4 and merc_idx == 5, "casino=" + str(casinoCSidx) + " merc=" + str(merc_idx))
	check("casino_chips_granted", int(game44.get("casino_chips")) == 10 and int(game44.get("casino_pulls")) == 0 and String(game44.get("casino_last_result")) == "", "chips=" + str(game44.get("casino_chips")))
	game44.call("_open_shop_panel", casinoCSidx)
	await process_frame
	check("casino_panel_opens", bool((game44.get("shop_panel") as Node).get("visible")) and String((game44.get("shop_title") as Label).text).contains("赌场"), "title=" + String((game44.get("shop_title") as Label).text))
	var gamble_btn: Button = null
	for child in (game44.get("shop_items_box") as Node).get_children():
		var b44 := child as Button
		if b44 != null and bool(b44.get_meta("casino_gamble", false)):
			gamble_btn = b44
	check("casino_gamble_button", gamble_btn != null and String(gamble_btn.text).contains("赌一把"), "")
	game44.call("_close_shop_panel")
	game44.call("_open_shop_panel", merc_idx)
	await process_frame
	check("mercenary_opens_now", bool((game44.get("shop_panel") as Node).get("visible")), "")
	game44.call("_close_shop_panel")
	game44.set("gold", 5000)
	var goldC := int(game44.get("gold"))
	var bagC := (game44.get("hero_inventory") as Array).size()
	var okC: bool = game44.call("casino_gamble", 0.50)
	check("casino_gamble_gear", okC and int(game44.get("casino_chips")) == 9 and int(game44.get("casino_pulls")) == 1 and int(game44.get("gold")) == goldC and (game44.get("hero_inventory") as Array).size() == bagC + 1 and String(game44.get("casino_last_result")) == "gear", "chips=" + str(game44.get("casino_chips")) + " gold=" + str(game44.get("gold")))
	game44.call("casino_gamble", 0.05)
	check("casino_gamble_consumable", String(game44.get("casino_last_result")) == "consumable" and int(game44.get("gold")) == goldC, "result=" + String(game44.get("casino_last_result")))
	var lastC: Dictionary = (game44.get("hero_inventory") as Array)[(game44.get("hero_inventory") as Array).size() - 1] as Dictionary
	check("casino_consumable_kind", String(lastC.get("kind", "")) in ["potion_heal", "stone_home", "stone_revive"], "kind=" + String(lastC.get("kind", "")))
	game44.call("casino_gamble", 0.15)
	check("casino_gamble_premium", String(game44.get("casino_last_result")) == "premium" and String(((game44.get("hero_inventory") as Array)[(game44.get("hero_inventory") as Array).size() - 1] as Dictionary).get("name", "")).begins_with("黄金"), "")
	game44.call("casino_gamble", 0.01)
	check("casino_beast_event", String(game44.get("casino_last_result")) == "beast" and String(game44.get("casino_beast_name")) in ["青龙", "朱雀", "玄武", "白虎"], "beast=" + String(game44.get("casino_beast_name")))
	var beastC: Node = null
	for wd in game44.get("wilds"):
		if wd.has_meta("wild_kind") and String(wd.get_meta("wild_kind", "")) == "saint_beast":
			beastC = wd
	check("casino_beast_spawned", beastC != null and String(beastC.get("display_name")) == String(game44.get("casino_beast_name")) and int(beastC.get_meta("bounty")) == 300, "")
	var strat44: Node = game44.get("strategist")
	var goldB := int(game44.get("gold"))
	var bagB := (game44.get("hero_inventory") as Array).size()
	game44.call("apply_damage", strat44, beastC, 99999.0)
	await process_frame
	check("casino_beast_bounty_and_gear", not bool(beastC.get("alive")) and int(game44.get("gold")) == goldB + 300 and (game44.get("hero_inventory") as Array).size() == bagB + 2, "gold=" + str(game44.get("gold")) + " bag=" + str((game44.get("hero_inventory") as Array).size()))
	check("casino_beast_drops_mark_too", bool(game44.call("has_hero_item", "圣痕·" + String(game44.get("casino_beast_name")))), "")
	game44.set("casino_chips", 0)
	var pullsC := int(game44.get("casino_pulls"))
	var ok0: bool = game44.call("casino_gamble", 0.50)
	check("casino_no_chips_refuses", not ok0 and int(game44.get("casino_chips")) == 0 and int(game44.get("casino_pulls")) == pullsC and int(game44.get("gold")) == goldB + 300, "")
	game44.call("reset_game")
	await process_frame
	check("casino_reset_regrants", int(game44.get("casino_chips")) == 10 and int(game44.get("casino_pulls")) == 0 and String(game44.get("casino_last_result")) == "", "chips=" + str(game44.get("casino_chips")))
	game44.free()
	# Village-chief single reward (round 34 note): delivering the head
	# with a full bag must grant exactly one gold gear and no gold —
	# the old `gold += 300` fallback paid on top of the stashed gear.
	var gameV := _make_game()
	await process_frame
	await process_frame
	gameV.call("select_hero", 0)
	await process_frame
	gameV.set("gold", 5000)
	var invV: Array = gameV.get("hero_inventory")
	for n in range(6):
		invV.append({"name": "填充装%d" % n, "kind": "gear", "dmg": 1.0, "desc": "测试填充"})
	var stash_ok: bool = not bool(gameV.call("give_hero_item", {"name": "测试装", "kind": "gear", "dmg": 1.0, "desc": "x"}))
	check("chief_stash_semantics", stash_ok and (gameV.get("pending_quest_items") as Array).size() == 1 and int(gameV.get("gold")) == 5000, "pending=" + str((gameV.get("pending_quest_items") as Array).size()))
	invV.clear()
	(gameV.get("pending_quest_items") as Array).clear()
	for n in range(5):
		invV.append({"name": "填充装%d" % n, "kind": "gear", "dmg": 1.0, "desc": "测试填充"})
	invV.append({"name": "人头", "kind": "quest", "desc": "强盗头子的人头"})
	gameV.call("quest_npc_interact", "cunzh")
	check("chief_full_bag_single_reward", int(gameV.get("gold")) == 5000 and String(gameV.call("qstate", "qiangdao")) == "done" and not bool(gameV.call("has_hero_item", "人头")) and (gameV.get("pending_quest_items") as Array).is_empty(), "gold=" + str(gameV.get("gold")))
	var gold_gears := 0
	for it in gameV.get("hero_inventory"):
		if String((it as Dictionary).get("name", "")).begins_with("黄金"):
			gold_gears += 1
	check("chief_full_bag_one_gold_gear", gold_gears == 1, "n=" + str(gold_gears))
	gameV.free()

	# --- Test 45: mercenaries (stage 2) --------------------------------
	# Quartermaster roster on the 2D contract: wave unlocks, population
	# cap 6 + strategist level, upkeep from wave 12, farmer repairs the
	# seal core, siege doubles damage against bosses, death frees pop.
	var gameMR := _make_game()
	await process_frame
	await process_frame
	gameMR.call("select_hero", 0)
	await process_frame
	check("merc_defs_seven", (gameMR.get("MERC_DEFS") as Array).size() == 7, "")
	check("merc_pop_cap_formula", int(gameMR.call("pop_cap")) == 6 + int(gameMR.get("general_level")), "cap=" + str(gameMR.call("pop_cap")))
	gameMR.set("gold", 5000)
	check("merc_buy_farmer", bool(gameMR.call("buy_mercenary", 0)) and int(gameMR.get("gold")) == 4985 and (gameMR.get("mercs") as Array).size() == 1 and int(gameMR.call("pop_used")) == 1, "gold=" + str(gameMR.get("gold")))
	check("merc_wave_locked", not bool(gameMR.call("buy_mercenary", 6)) and int(gameMR.get("gold")) == 4985 and (gameMR.get("mercs") as Array).size() == 1, "")
	gameMR.set("current_wave", 10)
	check("merc_buy_shanyue", bool(gameMR.call("buy_mercenary", 6)) and int(gameMR.call("pop_used")) == 2, "")
	for n in range(5):
		gameMR.call("buy_mercenary", 0)
	check("merc_pop_full", int(gameMR.call("pop_used")) == 7 and not bool(gameMR.call("buy_mercenary", 1)), "pop=" + str(gameMR.call("pop_used")))
	gameMR.set("general_level", 5)
	gameMR.set("gold", 0)
	check("merc_gold_refused", not bool(gameMR.call("buy_mercenary", 1)) and (gameMR.get("mercs") as Array).size() == 7, "")
	gameMR.set("gold", 5000)
	gameMR.set("current_wave", 12)
	check("merc_buy_piliche", bool(gameMR.call("buy_mercenary", 5)) and int(gameMR.call("pop_used")) == 9, "pop=" + str(gameMR.call("pop_used")))
	var pilicheMR: Node = null
	var shanyueMR: Node = null
	var farmerMR: Node = null
	for m in gameMR.get("mercs"):
		var mid := String((m as Node).get_meta("merc_id", ""))
		if mid == "piliche":
			pilicheMR = m
		elif mid == "shanyue":
			shanyueMR = m
		elif mid == "farmer" and farmerMR == null:
			farmerMR = m
	gameMR.set("game_state", "battle")
	var bossMR: Node = gameMR.call("_make_unit", "boss", "enemy", "测试Boss", Vector3(30, 0, 30), 100000.0, 0.5, 2.2, 1.0, 1.0, "", Color.WHITE, 1.0)
	var bossMRR_hp0 := float(bossMR.get("hp"))
	gameMR.call("apply_damage", pilicheMR, bossMR, 100.0)
	check("merc_siege_doubles_vs_boss", float(bossMR.get("hp")) == bossMRR_hp0 - 200.0, "hp=" + str(bossMR.get("hp")))
	gameMR.call("apply_damage", farmerMR, bossMR, 100.0)
	check("merc_nonsiege_single_vs_boss", float(bossMR.get("hp")) == bossMRR_hp0 - 300.0, "hp=" + str(bossMR.get("hp")))
	bossMR.free()
	var dummyMR: Node = gameMR.call("_make_unit", "enemy", "enemy", "靶子", Vector3(2, 0, 20), 90.0, 0.5, 2.2, 1.0, 1.0, "", Color.WHITE, 1.0)
	(gameMR.get("enemies") as Array).append(dummyMR)
	shanyueMR.set("global_position", Vector3(0, 0, 20))
	var killMR_ok: bool = await wait_until(func() -> bool: return not bool(dummyMR.get("alive")), 8.0)
	check("merc_guards_kill_enemy", killMR_ok, "")
	gameMR.set("core_hp", 200.0)
	var repMR_ok: bool = await wait_until(func() -> bool: return float(gameMR.get("core_hp")) > 200.0, 6.0)
	check("merc_farmer_repairs_core", repMR_ok, "core=" + str(gameMR.get("core_hp")))
	gameMR.set("gold", 1000)
	var popMR := int(gameMR.call("pop_used"))
	var feeMR: int = gameMR.call("merc_upkeep_tick")
	check("merc_upkeep_wave12", feeMR == popMR * 2 and int(gameMR.get("gold")) == 1000 - feeMR, "fee=" + str(feeMR))
	gameMR.set("current_wave", 11)
	check("merc_upkeep_none_before_12", int(gameMR.call("merc_upkeep_tick")) == 0 and int(gameMR.get("gold")) == 1000 - feeMR, "")
	var stratMR: Node = gameMR.get("strategist")
	gameMR.call("apply_damage", stratMR, shanyueMR, 999999.0)
	await process_frame
	check("merc_death_frees_pop", int(gameMR.call("pop_used")) == popMR - 1 and not (gameMR.get("mercs") as Array).has(shanyueMR), "pop=" + str(gameMR.call("pop_used")))
	var mercMR_idx := -1
	var defsMR: Array = gameMR.get("shop_defs")
	for i in range(defsMR.size()):
		if String((defsMR[i] as Dictionary).get("kind", "")) == "mercenary":
			mercMR_idx = i
	gameMR.call("_open_shop_panel", mercMR_idx)
	await process_frame
	var mercMR_btn := false
	for b in (gameMR.get("shop_items_box") as Node).get_children():
		if (b as Node).has_meta("merc_idx"):
			mercMR_btn = true
	check("merc_panel_opens_with_buttons", bool((gameMR.get("shop_panel") as Node).get("visible")) and mercMR_btn and String((gameMR.get("shop_title") as Label).text).contains("人口"), "")
	gameMR.call("reset_game")
	await process_frame
	check("merc_reset_clears", (gameMR.get("mercs") as Array).is_empty() and int(gameMR.call("pop_used")) == 0, "")
	gameMR.free()

	# --- Test 46: saint marks and the four saints (stage 2) -----------
	# Wild saints on their daises drop marks; tokens ride along (zhuque
	# 铜雀, baihu 和氏璧, xuanwu 玉玺+mark). A used mark summons the
	# beast for 1 pop; its death returns the mark. Casino beast too.
	var gameSB := _make_game()
	await process_frame
	await process_frame
	gameSB.call("select_hero", 0)
	await process_frame
	check("saint_points_sixteen", (gameSB.get("wild_points") as Array).size() == 16, "n=" + str((gameSB.get("wild_points") as Array).size()))
	var qlSB: Node = gameSB.call("spawn_wild_at", "qinglong", Vector3(77, 0, -37))
	check("saint_qinglong_spawns", qlSB != null and String(qlSB.get_meta("wild_kind", "")) == "qinglong", "")
	qlSB.free()
	var stratSB: Node = gameSB.get("strategist")
	gameSB.call("_on_wild_death", "qinglong", stratSB)
	gameSB.call("_on_wild_death", "zhuque", stratSB)
	gameSB.call("_on_wild_death", "baihu", stratSB)
	gameSB.call("_on_wild_death", "xuanwu", stratSB)
	var namesSB: Array = []
	for it in gameSB.get("hero_inventory"):
		namesSB.append(String((it as Dictionary).get("name", "")))
	for it in gameSB.get("pending_quest_items"):
		namesSB.append(String((it as Dictionary).get("name", "")))
	check("saint_marks_drop", namesSB.has("圣痕·青龙") and namesSB.has("圣痕·朱雀") and namesSB.has("圣痕·白虎") and namesSB.has("圣痕·玄武"), "names=" + str(namesSB))
	check("saint_tokens_drop", bool(gameSB.call("has_hero_item", "铜雀")) and bool(gameSB.call("has_hero_item", "和氏璧")) and bool(gameSB.call("has_hero_item", "玉玺")), "")
	check("saint_detection_from_heshibi", bool(gameSB.call("hero_has_detection")), "")
	var mark_slot := -1
	var invSB: Array = gameSB.get("hero_inventory")
	for i in range(invSB.size()):
		if String((invSB[i] as Dictionary).get("name", "")) == "圣痕·青龙":
			mark_slot = i
	gameSB.call("_use_inventory_item", mark_slot)
	await process_frame
	check("saint_summon_works", mark_slot >= 0 and (gameSB.get("saints_active") as Array).size() == 1 and not bool(gameSB.call("has_hero_item", "圣痕·青龙")) and int(gameSB.call("pop_used")) == 1, "slot=" + str(mark_slot))
	var saintSB: Node = (gameSB.get("saints_active") as Array)[0]
	gameSB.set("game_state", "battle")
	var dummySB: Node = gameSB.call("_make_unit", "enemy", "enemy", "靶子", saintSB.get("global_position") + Vector3(4, 0, 0), 90.0, 0.5, 2.2, 1.0, 1.0, "", Color.WHITE, 1.0)
	(gameSB.get("enemies") as Array).append(dummySB)
	var skill_ok: bool = await wait_until(func() -> bool: return not bool(dummySB.get("alive")), 8.0)
	check("saint_fights_beside_hero", skill_ok, "")
	gameSB.call("_deliver_pending_items")
	gameSB.call("apply_damage", stratSB, saintSB, 999999.0)
	await process_frame
	var namesSB2: Array = []
	for it in gameSB.get("hero_inventory"):
		namesSB2.append(String((it as Dictionary).get("name", "")))
	for it in gameSB.get("pending_quest_items"):
		namesSB2.append(String((it as Dictionary).get("name", "")))
	check("saint_death_returns_mark", (gameSB.get("saints_active") as Array).is_empty() and int(gameSB.call("pop_used")) == 0 and namesSB2.has("圣痕·青龙"), "")
	gameSB.set("gold", 5000)
	gameSB.set("current_wave", 10)
	for n in range(6):
		gameSB.call("buy_mercenary", 0)
	check("saint_pop_gate_setup", int(gameSB.call("pop_used")) == 6, "pop=" + str(gameSB.call("pop_used")))
	var xw_slot := -1
	var invSB2: Array = gameSB.get("hero_inventory")
	for i in range(invSB2.size()):
		if String((invSB2[i] as Dictionary).get("name", "")) == "圣痕·玄武":
			xw_slot = i
	gameSB.call("_use_inventory_item", xw_slot)
	await process_frame
	check("saint_summon_fills_pop", xw_slot >= 0 and (gameSB.get("saints_active") as Array).size() == 1 and int(gameSB.call("pop_used")) == 7, "slot=" + str(xw_slot))
	var zq_slot := -1
	var invSB3: Array = gameSB.get("hero_inventory")
	for i in range(invSB3.size()):
		if String((invSB3[i] as Dictionary).get("name", "")) == "圣痕·朱雀":
			zq_slot = i
	gameSB.call("_use_inventory_item", zq_slot)
	await process_frame
	check("saint_pop_full_refuses", (gameSB.get("saints_active") as Array).size() == 1 and bool(gameSB.call("has_hero_item", "圣痕·朱雀")), "")
	stratSB.set("hp", 100.0)
	gameSB.set("gold", 0)
	var tq_slot := -1
	var invSB4: Array = gameSB.get("hero_inventory")
	for i in range(invSB4.size()):
		if String((invSB4[i] as Dictionary).get("name", "")) == "铜雀":
			tq_slot = i
	gameSB.call("_use_inventory_item", tq_slot)
	check("saint_tongque_pays", tq_slot >= 0 and not bool(gameSB.call("has_hero_item", "铜雀")) and int(gameSB.get("gold")) == int(gameSB.get("hero_level")) * 50 and float(stratSB.get("hp")) > 100.0, "gold=" + str(gameSB.get("gold")))
	for arr_name in ["hero_inventory", "pending_quest_items"]:
		var arrSB: Array = gameSB.get(arr_name)
		for i in range(arrSB.size() - 1, -1, -1):
			if String((arrSB[i] as Dictionary).get("name", "")) == "圣痕·白虎":
				arrSB.remove_at(i)
	var cbeastSB: Node = gameSB.call("spawn_casino_beast", "白虎")
	gameSB.call("apply_damage", stratSB, cbeastSB, 999999.0)
	await process_frame
	check("saint_casino_beast_drops_mark", bool(gameSB.call("has_hero_item", "圣痕·白虎")), "")
	gameSB.call("reset_game")
	await process_frame
	check("saint_reset_clears", (gameSB.get("saints_active") as Array).is_empty() and int(gameSB.call("pop_used")) == 0, "")
	gameSB.free()

	# ---- Test 47: finale — three Simas, revive, fire trap, victory
	var gameZ = _make_game()
	await process_frame
	await process_frame
	gameZ.set("_perf_enabled", false)
	gameZ.call("select_hero", 0)
	var stratZ: ArticulatedUnit = gameZ.get("strategist")
	gameZ.call("_start_wave", 20)
	check("finale_activates_on_wave20", bool(gameZ.get("finale_active")) and String(gameZ.call("qstate", "shangfanggu")) == "on")
	gameZ.set("spawn_queue", [])
	gameZ.set("current_boss_list", gameZ.call("bosses_for_wave", 20))
	gameZ.set("boss_spawn_index", 0)
	var yiZ: ArticulatedUnit = null
	var shiZ: ArticulatedUnit = null
	var zhaoZ: ArticulatedUnit = null
	for i in range(3):
		var bZ = gameZ.call("_spawn_enemy_of_type", "boss")
		if bZ.display_name == "司马懿":
			yiZ = bZ
		elif bZ.display_name == "司马师":
			shiZ = bZ
		elif bZ.display_name == "司马昭":
			zhaoZ = bZ
	var statesZ: Dictionary = gameZ.get("sima_state")
	check("finale_trio_spawned", yiZ != null and shiZ != null and zhaoZ != null and String(statesZ["司马懿"]) == "alive", str(statesZ))
	check("finale_yi_registered", gameZ.get("sima_yi") == yiZ and yiZ.has_meta("finale_yi"))
	gameZ.call("apply_damage", stratZ, yiZ, 999999.0)
	statesZ = gameZ.get("sima_state")
	check("finale_yi_revives_pending", String(statesZ["司马懿"]) == "reviving" and float(gameZ.get("yi_revive_timer")) > 0.0, str(statesZ))
	gameZ.call("_update_finale", 5.5)
	var yi2Z: ArticulatedUnit = gameZ.get("sima_yi")
	statesZ = gameZ.get("sima_state")
	check("finale_yi_revived", yi2Z != null and yi2Z != yiZ and yi2Z.alive and String(statesZ["司马懿"]) == "alive")
	yi2Z.global_position = Vector3(85, 0, -37)
	gameZ.call("_update_finale", 0.1)
	check("finale_yi_trapped", bool(gameZ.get("yi_trapped")) and (gameZ.get("finale_flames") as Array).size() == 6)
	var dealtZ: float = gameZ.call("apply_damage", stratZ, yi2Z, 500.0)
	check("finale_trapped_invulnerable", dealtZ == 0.0 and yi2Z.alive)
	gameZ.call("apply_damage", stratZ, zhaoZ, 999999.0)
	statesZ = gameZ.get("sima_state")
	check("finale_zhao_dead_first", String(statesZ["司马昭"]) == "dead" and bool(gameZ.get("yi_trapped")))
	gameZ.call("apply_damage", stratZ, shiZ, 999999.0)
	statesZ = gameZ.get("sima_state")
	check("finale_trap_releases", String(statesZ["司马师"]) == "dead" and not bool(gameZ.get("yi_trapped")) and (gameZ.get("finale_flames") as Array).is_empty())
	gameZ.call("apply_damage", stratZ, yi2Z, 999999.0)
	statesZ = gameZ.get("sima_state")
	check("finale_yi_truly_dead", String(statesZ["司马懿"]) == "dead" and float(gameZ.get("yi_revive_timer")) < 0.0)
	check("finale_done_and_quest", bool(gameZ.get("finale_done")) and String(gameZ.call("qstate", "shangfanggu")) == "done")
	gameZ.call("_check_wave_clear")
	check("finale_victory", String(gameZ.get("game_state")) == "victory", String(gameZ.get("game_state")))
	root.remove_child(gameZ)
	gameZ.free()

	# ---- Test 48: stage-2 hero kits — status engine + bespoke skills
	var gameK0 = _make_game()
	await process_frame
	var all_full := true
	for r in range(22):
		var rowK: Dictionary = gameK0.get("HERO_ROSTER")[r]
		if String(rowK.get("kit", "")) != "full":
			all_full = false
	check("kits_all_full", all_full)
	var liuchenK: Dictionary = gameK0.get("HERO_ROSTER")[14]
	check("liuchen_curhp_passive", String(liuchenK.get("passive", "")) == "curhp" and String(liuchenK.get("skill", "")) == "rift_slash")
	var liaohuaK: Dictionary = gameK0.get("HERO_ROSTER")[18]
	check("liaohua_drunk_passive", String(liaohuaK.get("passive", "")) == "drunk" and String(liaohuaK.get("skill", "")) == "fire_breath")
	gameK0.free()

	# 赵广 frost arrow: stun lands.
	var gameK1 = _make_game()
	await process_frame
	await process_frame
	gameK1.set("_perf_enabled", false)
	gameK1.call("select_hero", 1)
	gameK1.set("spawn_queue", [])
	gameK1.call("_spawn_enemy")
	await process_frame
	var foeK1: Node = _find_enemy(gameK1, "enemy")
	var stratK1: Node = gameK1.get("strategist")
	foeK1.set("global_position", stratK1.global_position + Vector3(5, 0, 0))
	gameK1.set("skill_cooldown", 0.0)
	var hitsK1 := int(gameK1.call("cast_hero_skill"))
	check("frost_arrow_hits_and_stuns", hitsK1 >= 1 and foeK1.has_meta("stun_until") and bool(gameK1.call("_unit_disabled", foeK1)), "hits=" + str(hitsK1))
	gameK1.free()

	# 关索 bind: root + DoT ticking; vuln / atk-cut damage hooks.
	var gameK2 = _make_game()
	await process_frame
	await process_frame
	gameK2.set("_perf_enabled", false)
	gameK2.call("select_hero", 5)
	gameK2.set("spawn_queue", [])
	gameK2.call("_spawn_enemy")
	await process_frame
	var foeK2: Node = _find_enemy(gameK2, "enemy")
	var stratK2: Node = gameK2.get("strategist")
	foeK2.set("global_position", stratK2.global_position + Vector3(5, 0, 0))
	gameK2.set("skill_cooldown", 0.0)
	var hitsK2 := int(gameK2.call("cast_hero_skill"))
	check("bind_roots_and_dots", hitsK2 >= 1 and foeK2.has_meta("root_until") and (gameK2.get("dot_effects") as Array).size() >= 1, "hits=" + str(hitsK2))
	var hpK2: float = foeK2.get("hp")
	for i in range(4):
		gameK2.call("_update_statuses", 1.0)
	check("bind_dot_ticks_damage", float(foeK2.get("hp")) < hpK2, "hp " + str(hpK2) + " -> " + str(foeK2.get("hp")))
	gameK2.call("_apply_vuln", foeK2, 0.25, 8.0)
	var dealtK2: float = gameK2.call("apply_damage", stratK2, foeK2, 100.0)
	check("vuln_amplifies_damage", dealtK2 > 115.0 and dealtK2 < 135.0, "dealt=" + str(dealtK2))
	gameK2.call("_apply_atk_cut", foeK2, 0.5, 8.0)
	var hpS2: float = stratK2.get("hp")
	var dealtK3: float = gameK2.call("apply_damage", foeK2, stratK2, 100.0)
	check("atk_cut_halves_damage", dealtK3 > 40.0 and dealtK3 < 60.0, "dealt=" + str(dealtK3))
	gameK2.free()

	# 木鹿大王 hex: shrink + disable + expiry restore.
	var gameK3 = _make_game()
	await process_frame
	await process_frame
	gameK3.set("_perf_enabled", false)
	# 木鹿大王是口令锁英雄，新局须先解口令，否则 select_hero(11) 被拒、strategist 为 null，2678 行空访问会直接 abort 整个 harness（_finish 永不执行、进程空转至 timeout）。
	gameK3.call("try_unlock_hero", "muludawang")
	gameK3.call("select_hero", 11)
	gameK3.set("spawn_queue", [])
	gameK3.call("_spawn_enemy")
	await process_frame
	var foeK3: Node = _find_enemy(gameK3, "enemy")
	var stratK3: Node = gameK3.get("strategist")
	foeK3.set("global_position", stratK3.global_position + Vector3(5, 0, 0))
	var scaleK3: Vector3 = foeK3.get("scale")
	gameK3.set("skill_cooldown", 0.0)
	var hitsK3 := int(gameK3.call("cast_hero_skill"))
	check("hex_shrinks_and_disables", hitsK3 >= 1 and float(foeK3.get("scale").x) < scaleK3.x * 0.6 and bool(gameK3.call("_unit_disabled", foeK3)), "hits=" + str(hitsK3))
	gameK3.set("elapsed", float(gameK3.get("elapsed")) + 30.0)
	gameK3.call("_update_statuses", 0.1)
	check("hex_expires_and_restores", is_equal_approx(float(foeK3.get("scale").x), scaleK3.x) and (gameK3.get("status_units") as Array).is_empty())
	gameK3.free()

	# 诸葛瞻 frost burst: slow halves move speed.
	var gameK4 = _make_game()
	await process_frame
	await process_frame
	gameK4.set("_perf_enabled", false)
	gameK4.call("select_hero", 16)
	gameK4.set("spawn_queue", [])
	gameK4.call("_spawn_enemy")
	await process_frame
	var foeK4: Node = _find_enemy(gameK4, "enemy")
	var stratK4: Node = gameK4.get("strategist")
	foeK4.set("global_position", stratK4.global_position + Vector3(5, 0, 0))
	var spdK4: float = foeK4.get("move_speed")
	gameK4.set("skill_cooldown", 0.0)
	var hitsK4 := int(gameK4.call("cast_hero_skill"))
	check("frost_burst_slows", hitsK4 >= 1 and is_equal_approx(float(foeK4.get("move_speed")), spdK4 * 0.5), "hits=" + str(hitsK4))
	gameK4.free()

	# ---- Test 49: boss signature skills (stage 2) — assignment, specials
	# （韩德 death curse / 董卓 七星刀 / 王双 烈焰刀）, mirror, transform,
	# shield, silence, 天石术 and the boss AI cast loop.
	var gameB1 = _make_game()
	await process_frame
	await process_frame
	gameB1.set("_perf_enabled", false)
	gameB1.call("select_hero", 0)
	gameB1.set("spawn_queue", [])
	gameB1.set("current_boss_list", gameB1.call("bosses_for_wave", 1))
	gameB1.set("boss_spawn_index", 0)
	var hbB1: Node = gameB1.call("_spawn_enemy_of_type", "boss")
	check("boss49_skills_assigned", (hbB1.get_meta("boss_skills") as Array).has("玄冰咒"))
	check("boss49_special_hande", String(hbB1.get_meta("boss_special", "")) == "hande")
	var heroB1: Node = gameB1.get("strategist")
	var genB1: Node = gameB1.get("general")
	var heroB1Hp := float(heroB1.get("hp"))
	gameB1.call("apply_damage", heroB1, hbB1, 10.0)
	gameB1.call("apply_damage", genB1, hbB1, 10.0)
	gameB1.call("apply_damage", heroB1, hbB1, 100000.0)
	check("boss49_hande_safe_two_attackers", is_equal_approx(float(heroB1.get("hp")), heroB1Hp))
	gameB1.free()

	var gameB2 = _make_game()
	await process_frame
	await process_frame
	gameB2.set("_perf_enabled", false)
	gameB2.call("select_hero", 0)
	gameB2.set("spawn_queue", [])
	gameB2.set("current_boss_list", gameB2.call("bosses_for_wave", 1))
	gameB2.set("boss_spawn_index", 0)
	var hbB2: Node = gameB2.call("_spawn_enemy_of_type", "boss")
	var heroB2: Node = gameB2.get("strategist")
	var genB2: Node = gameB2.get("general")
	var u3B2: Node = gameB2.call("_make_unit", "general", "ally", "测试兵", heroB2.global_position + Vector3(2, 0, 0), 500.0, 3.0, 3.0, 10.0, 1.0)
	gameB2.call("apply_damage", heroB2, hbB2, 10.0)
	gameB2.call("apply_damage", genB2, hbB2, 10.0)
	gameB2.call("apply_damage", u3B2, hbB2, 10.0)
	var heroB2Hp := float(heroB2.get("hp"))
	gameB2.call("apply_damage", heroB2, hbB2, 100000.0)
	check("boss49_hande_curse_three_attackers", float(heroB2.get("hp")) < heroB2Hp - 100.0)
	check("boss49_hande_curse_stuns", bool(gameB2.call("_unit_disabled", heroB2)))
	gameB2.free()

	var gameB3 = _make_game()
	await process_frame
	await process_frame
	gameB3.set("_perf_enabled", false)
	gameB3.call("select_hero", 0)
	gameB3.set("spawn_queue", [])
	gameB3.set("current_boss_list", gameB3.call("bosses_for_wave", 9))
	gameB3.set("boss_spawn_index", 0)
	var dzB3: Node = gameB3.call("_spawn_enemy_of_type", "boss")
	var heroB3: Node = gameB3.get("strategist")
	dzB3.set("global_position", heroB3.global_position + Vector3(6, 0, 0))
	gameB3.set("skill_cooldown", 0.0)
	var blockedB3 := int(gameB3.call("cast_hero_skill"))
	check("boss49_qixing_blocks_skill", blockedB3 == 0 and float(gameB3.get("skill_cooldown")) > 0.0)
	check("boss49_qixing_on_cooldown", float(dzB3.get_meta("qixing_ready", 0.0)) > 20.0)
	gameB3.set("skill_cooldown", 0.0)
	var firedB3 := int(gameB3.call("cast_hero_skill"))
	check("boss49_qixing_second_cast_fires", firedB3 >= 1)
	gameB3.free()

	var gameB4 = _make_game()
	await process_frame
	await process_frame
	gameB4.set("_perf_enabled", false)
	gameB4.call("select_hero", 0)
	gameB4.set("spawn_queue", [])
	gameB4.set("current_boss_list", gameB4.call("bosses_for_wave", 10))
	gameB4.set("boss_spawn_index", 0)
	var wsB4: Node = gameB4.call("_spawn_enemy_of_type", "boss")
	var heroB4: Node = gameB4.get("strategist")
	var genB4: Node = gameB4.get("general")
	genB4.set("global_position", heroB4.global_position + Vector3(3, 0, 0))
	var genB4Hp := float(genB4.get("hp"))
	gameB4.call("apply_damage", wsB4, heroB4, 100.0)
	# 0.1.52 re-judgment: the primary hit (default kind "physical")
	# now takes hero armor (zhaotong f=0.78295), so the no-crit
	# splash is 100*0.78295*0.5 = 39.15 (was 50); either 20% crit
	# roll (primary or splash re-entry) gives 176, both give 793.
	# Threshold 35 keeps splash on/off
	# discrimination in both branches.
	check("boss49_lieyan_splashes", float(genB4.get("hp")) < genB4Hp - 35.0)
	gameB4.free()

	var gameB5 = _make_game()
	await process_frame
	await process_frame
	gameB5.set("_perf_enabled", false)
	gameB5.call("select_hero", 0)
	gameB5.set("spawn_queue", [])
	gameB5.set("current_boss_list", gameB5.call("bosses_for_wave", 13))
	gameB5.set("boss_spawn_index", 0)
	var zhB5: Node = gameB5.call("_spawn_enemy_of_type", "boss")
	var nB5 := (gameB5.get("enemies") as Array).size()
	var okB5 := bool(gameB5.call("cast_boss_skill", zhB5, "分身", null))
	var enemiesB5: Array = gameB5.get("enemies")
	check("boss49_mirror_spawns_clones", okB5 and enemiesB5.size() == nB5 + 2 and bool((enemiesB5[enemiesB5.size() - 1] as Node).get_meta("is_clone", false)))
	gameB5.free()

	var gameB6 = _make_game()
	await process_frame
	await process_frame
	gameB6.set("_perf_enabled", false)
	gameB6.call("select_hero", 0)
	gameB6.set("spawn_queue", [])
	gameB6.set("current_boss_list", gameB6.call("bosses_for_wave", 9))
	gameB6.set("boss_spawn_index", 0)
	var dzB6: Node = gameB6.call("_spawn_enemy_of_type", "boss")
	var scaleB6 := (dzB6.get("scale") as Vector3).x
	var atkB6 := float(dzB6.get("attack_damage"))
	gameB6.call("cast_boss_skill", dzB6, "天神下凡", null)
	check("boss49_transform_grows", (dzB6.get("scale") as Vector3).x > scaleB6 * 1.3 and float(dzB6.get("attack_damage")) > atkB6 * 1.4)
	gameB6.call("_apply_stun", dzB6, 2.0)
	check("boss49_transform_control_immune", not bool(gameB6.call("_unit_disabled", dzB6)))
	gameB6.free()

	var gameB7 = _make_game()
	await process_frame
	await process_frame
	gameB7.set("_perf_enabled", false)
	gameB7.call("select_hero", 0)
	gameB7.set("spawn_queue", [])
	gameB7.set("current_boss_list", gameB7.call("bosses_for_wave", 4))
	gameB7.set("boss_spawn_index", 0)
	var wlB7: Node = gameB7.call("_spawn_enemy_of_type", "boss")
	gameB7.call("cast_boss_skill", wlB7, "五行罩", null)
	var wlB7Hp := float(wlB7.get("hp"))
	var wlB7Shield := float(wlB7.get_meta("bsk_shield_hp"))
	var heroB7: Node = gameB7.get("strategist")
	# Hit relative to the shield pool: hero 0 (赵统) crits x2 at 25%,
	# and a flat 50 hit crits to 100 > the 93.48 pool, spilling 6.52
	# into HP and tripping the <5.0 clause ~25% of runs (diagnosed
	# 2026-11-15, .tmp/diag_shield49.gd: 2/8 iters spilled exactly
	# 6.52). 0.4x pool crits to 0.8x pool — always fully absorbed.
	var hitB7 := minf(50.0, wlB7Shield * 0.4)
	gameB7.call("apply_damage", heroB7, wlB7, hitB7)
	check("boss49_shield_absorbs", float(wlB7.get_meta("bsk_shield_hp")) < wlB7Shield and wlB7Hp - float(wlB7.get("hp")) < 5.0)
	gameB7.free()

	var gameB8 = _make_game()
	await process_frame
	await process_frame
	gameB8.set("_perf_enabled", false)
	gameB8.call("select_hero", 0)
	gameB8.set("spawn_queue", [])
	gameB8.set("current_boss_list", gameB8.call("bosses_for_wave", 18))
	gameB8.set("boss_spawn_index", 0)
	var ccB8: Node = gameB8.call("_spawn_enemy_of_type", "boss")
	var heroB8: Node = gameB8.get("strategist")
	gameB8.call("cast_boss_skill", ccB8, "蚀心咒", heroB8)
	gameB8.set("skill_cooldown", 0.0)
	check("boss49_silence_blocks_cast", int(gameB8.call("cast_hero_skill")) == 0 and heroB8.has_meta("silenced_until"))
	check("boss49_heart_curse_dot_applied", (gameB8.get("dot_effects") as Array).size() >= 1)
	gameB8.free()

	var gameB9 = _make_game()
	await process_frame
	await process_frame
	gameB9.set("_perf_enabled", false)
	gameB9.call("select_hero", 0)
	gameB9.set("spawn_queue", [])
	gameB9.set("current_boss_list", gameB9.call("bosses_for_wave", 6))
	gameB9.set("boss_spawn_index", 0)
	var zjB9: Node = gameB9.call("_spawn_enemy_of_type", "boss")
	var heroB9: Node = gameB9.get("strategist")
	gameB9.call("cast_boss_skill", zjB9, "天石术", null)
	check("boss49_tianshi_pending", (gameB9.get("boss_pending") as Array).size() == 1)
	gameB9.set("elapsed", float(gameB9.get("elapsed")) + 1.1)
	var heroB9Hp := float(heroB9.get("hp"))
	gameB9.call("_update_boss_skills", 0.1)
	check("boss49_tianshi_detonates_on_cluster", float(heroB9.get("hp")) < heroB9Hp)
	gameB9.free()

	var gameB10 = _make_game()
	await process_frame
	await process_frame
	gameB10.set("_perf_enabled", false)
	gameB10.call("select_hero", 0)
	gameB10.set("spawn_queue", [])
	gameB10.set("current_boss_list", gameB10.call("bosses_for_wave", 3))
	gameB10.set("boss_spawn_index", 0)
	var hxB10: Node = gameB10.call("_spawn_enemy_of_type", "boss")
	var heroB10: Node = gameB10.get("strategist")
	hxB10.set("global_position", heroB10.global_position + Vector3(5, 0, 0))
	hxB10.set_meta("bsk_next_cast", 0.0)
	gameB10.call("_update_boss_skills", 0.1)
	check("boss49_ai_casts", float(hxB10.get_meta("bsk_next_cast", 0.0)) > 0.0)
	gameB10.free()

	# Test 50: stage-2 tower system - the six 2D buildable types,
	# population, the upgrade ladder, tower HP under enemy attack,
	# destruction freeing pad + population, farmer tower repair.
	var gameW1 = _make_game()
	gameW1.select_hero(0)
	gameW1.set("gold", 5000)
	var six_ok := true
	var type_ids := ["arrow", "frost", "thunder", "stone", "flame", "crossbow"]
	for i in range(type_ids.size()):
		if not gameW1.build_tower(i, type_ids[i]):
			six_ok = false
	check("tower50_six_types_buildable", six_ok)
	var occupiedW1 := 0
	for piW1 in range(6):
		if gameW1.get("pads")[piW1].get("tower") != null:
			occupiedW1 += 1
	check("tower50_six_towers_stand", occupiedW1 == 6)
	check("tower50_towers_count_population", gameW1.pop_used() == 6)
	check("tower50_seventh_fills_cap", gameW1.build_tower(6, "arrow"))
	check("tower50_population_blocks_eighth", not gameW1.build_tower(7, "arrow"))
	var tw0: Dictionary = gameW1.get("pads")[0].get("tower")
	check("tower50_tower_starts_lv1_full_hp", int(tw0.get("level", 0)) == 1 and absf(float(tw0.get("hp", 0.0)) - 600.0) < 0.01)
	var goldW1: int = gameW1.get("gold")
	check("tower50_upgrade_to_lv2", gameW1.upgrade_tower(0))
	check("tower50_upgrade_math", int(tw0.get("level", 0)) == 2 and absf(float(tw0.get("dmg", 0.0)) - 9.0 * 1.55) < 0.01 and absf(float(tw0.get("max_hp", 0.0)) - 850.0) < 0.01)
	check("tower50_upgrade_cost_25", int(gameW1.get("gold")) == goldW1 - 25)
	check("tower50_upgrade_to_lv3", gameW1.upgrade_tower(0))
	check("tower50_upgrade_maxed", not gameW1.upgrade_tower(0))
	gameW1.free()

	var gameW2 = _make_game()
	gameW2.select_hero(0)
	gameW2.set("gold", 5000)
	gameW2.set("spawn_queue", [])
	gameW2.build_tower(0, "frost")
	gameW2.build_tower(1, "stone")
	gameW2.set("game_state", "battle")
	var foeW1 = gameW2._make_unit("enemy", "enemy", "冰靶", Vector3(42, 0, -13), 3000.0, 0.0, 2.2, 1.0, 1.0)
	gameW2.get("enemies").append(foeW1)
	var foeW3 = gameW2._make_unit("enemy", "enemy", "石靶甲", Vector3(42, 0, 13), 3000.0, 0.0, 2.2, 1.0, 1.0)
	gameW2.get("enemies").append(foeW3)
	var foeW4 = gameW2._make_unit("enemy", "enemy", "石靶乙", Vector3(44, 0, 15), 3000.0, 0.0, 2.2, 1.0, 1.0)
	gameW2.get("enemies").append(foeW4)
	await wait_until(func() -> bool: return is_instance_valid(foeW1) and foeW1.has_meta("slow_until"), 6.0)
	check("tower50_frost_slows", foeW1.has_meta("slow_until"))
	await wait_until(func() -> bool: return foeW3.hp < 3000.0 and foeW4.hp < 3000.0, 8.0)
	check("tower50_stone_splashes", foeW3.hp < 3000.0 and foeW4.hp < 3000.0)
	gameW2.free()

	var gameW3 = _make_game()
	gameW3.select_hero(0)
	gameW3.set("gold", 1000)
	gameW3.build_tower(2, "arrow")
	var tw3: Dictionary = gameW3.get("pads")[2].get("tower")
	var tw3_count: int = gameW3.get("towers").size()
	var popW3: int = gameW3.pop_used()
	gameW3.damage_tower(tw3, 250.0)
	check("tower50_tower_takes_damage", absf(float(tw3.get("hp", 0.0)) - 350.0) < 0.01)
	gameW3.damage_tower(tw3, 10000.0)
	check("tower50_destroy_removes_tower", gameW3.get("towers").size() == tw3_count - 1)
	check("tower50_destroy_frees_pad", gameW3.get("pads")[2].get("tower") == null)
	check("tower50_destroy_frees_population", gameW3.pop_used() == popW3 - 1)
	gameW3.free()

	var gameW4 = _make_game()
	gameW4.select_hero(0)
	gameW4.set("gold", 1000)
	gameW4.set("spawn_queue", [])
	gameW4.build_tower(2, "arrow")
	var tw4: Dictionary = gameW4.get("pads")[2].get("tower")
	var padW4: Vector3 = tw4["position"]
	gameW4.set("game_state", "battle")
	var bruiser = gameW4._make_unit("enemy", "enemy", "砸塔兵", padW4 + Vector3(2.5, 0, 0), 3000.0, 0.0, 2.2, 15.0, 1.0)
	gameW4.get("enemies").append(bruiser)
	await wait_until(func() -> bool: return float(tw4.get("hp", 600.0)) < 600.0, 8.0)
	check("tower50_enemy_batters_tower", float(tw4.get("hp", 600.0)) < 600.0)
	gameW4.free()

	var gameW5 = _make_game()
	gameW5.select_hero(0)
	gameW5.set("gold", 5000)
	gameW5.set("spawn_queue", [])
	gameW5.build_tower(9, "arrow")
	var tw5: Dictionary = gameW5.get("pads")[9].get("tower")
	gameW5.damage_tower(tw5, 100.0)
	check("tower50_farmer_hired", gameW5.buy_mercenary(0))
	await wait_until(func() -> bool: return float(tw5.get("hp", 0.0)) >= 600.0, 45.0)
	check("tower50_farmer_repairs_tower", float(tw5.get("hp", 0.0)) >= 600.0)
	gameW5.free()

	# Test 51: stage-2 assassin ambush - stealth spawn from wave 6,
	# hidden from all targeting until revealed by attacking or detected
	# via 和氏璧 / 魂形态； beelines for 孔明； 孔明死则败.
	var gameA1 = _make_game()
	gameA1.select_hero(0)
	gameA1.set("current_wave", 6)
	gameA1.set("spawn_queue", [])
	gameA1.set("game_state", "battle")
	var aA1: Node = gameA1.call("spawn_assassin")
	check("assassin51_spawns", is_instance_valid(aA1) and bool(aA1.get_meta("is_assassin")))
	check("assassin51_hidden_at_spawn", not bool(aA1.get("visible")))
	check("assassin51_stats_wave6", absf(float(aA1.get("hp")) - 510.0) < 0.01 and absf(float(aA1.get("attack_damage")) - 23.0) < 0.01 and absf(float(aA1.get("move_speed")) - 5.0) < 0.01)
	check("assassin51_bounty_xp", int(aA1.get_meta("bounty", 0)) == 200 and int(aA1.get_meta("xp", 0)) == 300)
	check("assassin51_hidden_not_targetable", not bool(gameA1.call("_enemy_targetable", aA1)))
	check("assassin51_hidden_out_of_pool", not (gameA1.call("combat_targets") as Array).has(aA1))
	check("assassin51_nearest_ignores_hidden", gameA1.call("_nearest_enemy", (gameA1.get("strategist") as Node).global_position, 100.0) != aA1)
	# Detection via 和氏璧： visible + targetable, and removing it hides again.
	gameA1.call("give_hero_item", {"name": "和氏璧", "kind": "token", "desc": "持有：反隐（看破隐形单位）"})
	check("assassin51_detection_true", bool(gameA1.call("hero_has_detection")))
	check("assassin51_detected_targetable", bool(gameA1.call("_enemy_targetable", aA1)) and (gameA1.call("combat_targets") as Array).has(aA1))
	gameA1.call("_update_assassin", aA1)
	check("assassin51_detected_visible", bool(aA1.get("visible")))
	gameA1.call("take_hero_item", "和氏璧")
	check("assassin51_detection_off", not bool(gameA1.call("hero_has_detection")))
	gameA1.call("_update_assassin", aA1)
	check("assassin51_hidden_again", not bool(aA1.get("visible")))
	gameA1.free()

	# 魂形态 also grants detection while it lasts (2D soulform 原制）.
	var gameA2 = _make_game()
	gameA2.select_hero(0)
	gameA2.set("soul_timer", 8.0)
	check("assassin51_soulform_detects", bool(gameA2.call("hero_has_detection")))
	gameA2.set("soul_timer", 0.0)
	check("assassin51_soulform_fades", not bool(gameA2.call("hero_has_detection")))
	gameA2.free()

	# The assassin walks straight at 孔明 and ignores defenders on the way.
	var gameA3 = _make_game()
	gameA3.select_hero(0)
	gameA3.set("current_wave", 6)
	gameA3.set("spawn_queue", [])
	gameA3.set("game_state", "battle")
	var aA3: Node = gameA3.call("spawn_assassin")
	var kmA3: Node = gameA3.get("kongming_unit")
	var dA3_0 := Vector2(aA3.global_position.x - kmA3.global_position.x, aA3.global_position.z - kmA3.global_position.z).length()
	await wait_until(func() -> bool: return Vector2(aA3.global_position.x - kmA3.global_position.x, aA3.global_position.z - kmA3.global_position.z).length() < dA3_0 - 10.0, 8.0)
	var dA3_1 := Vector2(aA3.global_position.x - kmA3.global_position.x, aA3.global_position.z - kmA3.global_position.z).length()
	check("assassin51_beelines_to_kongming", dA3_1 < dA3_0 - 10.0)
	check("assassin51_no_combat_target_en_route", aA3.get("_combat_target") == null and bool(aA3.get("_has_move_target")))
	gameA3.free()

	# In range the assassin reveals itself, strikes 孔明， and 孔明 fights back.
	var gameA4 = _make_game()
	gameA4.select_hero(0)
	gameA4.set("current_wave", 6)
	gameA4.set("spawn_queue", [])
	gameA4.set("game_state", "battle")
	var aA4: Node = gameA4.call("spawn_assassin")
	var kmA4: Node = gameA4.get("kongming_unit")
	aA4.set("global_position", kmA4.global_position + Vector3(2.0, 0, 0))
	aA4.set("attack_timer", 0.0)
	var kmHpA4 := float(kmA4.get("hp"))
	gameA4.call("_update_assassin", aA4)
	check("assassin51_reveals_on_attack", bool(aA4.get("visible")) and float(aA4.get_meta("revealed_until", -1.0)) > float(gameA4.get("elapsed")))
	check("assassin51_strikes_kongming", float(kmA4.get("hp")) < kmHpA4)
	var aHpA4 := float(aA4.get("hp"))
	kmA4.set("attack_timer", 0.0)
	gameA4.call("_update_kongming")
	check("assassin51_kongming_fights_back", float(aA4.get("hp")) < aHpA4)
	# The wave cannot clear while the assassin lives, and clears once it dies.
	gameA4.call("_check_wave_clear")
	check("assassin51_blocks_wave_clear", String(gameA4.get("game_state")) == "battle")
	var goldA4 := int(gameA4.get("gold"))
	gameA4.call("apply_damage", gameA4.get("strategist"), aA4, 99999.0, "harness_probe")
	check("assassin51_dies_to_probe", not bool(aA4.get("alive")))
	check("assassin51_bounty_200", int(gameA4.get("gold")) == goldA4 + 200)
	check("assassin51_xp_300_levels_hero", int(gameA4.get("hero_level")) >= 2)
	gameA4.call("_check_wave_clear")
	check("assassin51_clear_after_death", String(gameA4.get("game_state")) == "intermission")
	gameA4.free()

	# 孔明死则败 (2D 原制）.
	var gameA5 = _make_game()
	gameA5.select_hero(0)
	gameA5.set("current_wave", 6)
	gameA5.set("spawn_queue", [])
	gameA5.set("game_state", "battle")
	var aA5: Node = gameA5.call("spawn_assassin")
	var kmA5: Node = gameA5.get("kongming_unit")
	kmA5.set("hp", 10.0)
	aA5.set("global_position", kmA5.global_position + Vector3(2.0, 0, 0))
	aA5.set("attack_timer", 0.0)
	gameA5.call("_update_assassin", aA5)
	check("assassin51_kongming_death_is_defeat", String(gameA5.get("game_state")) == "defeat" and String(gameA5.get("defeat_reason")) == "孔明遇刺身亡")
	gameA5.free()

	# The timer only fires in battle from wave 6, and never before wave 6.
	var gameA6 = _make_game()
	gameA6.select_hero(0)
	gameA6.set("current_wave", 6)
	gameA6.set("spawn_queue", [])
	gameA6.set("game_state", "battle")
	var dummyA6: Node = gameA6.call("_make_unit", "enemy", "enemy", "哨兵", Vector3(42, 0, -13), 3000.0, 0.0, 2.2, 1.0, 1.0)
	(gameA6.get("enemies") as Array).append(dummyA6)
	gameA6.set("assassin_timer", 0.05)
	var spawnedA6 := await wait_until(func() -> bool: return _find_enemy(gameA6, "assassin") != null, 8.0)
	check("assassin51_timer_auto_spawns", spawnedA6)
	var spawnedUnitA6 := _find_enemy(gameA6, "assassin")
	check("assassin51_timer_spawn_hidden", spawnedUnitA6 != null and not bool(spawnedUnitA6.get("visible")))
	gameA6.free()

	var gameA7 = _make_game()
	gameA7.select_hero(0)
	gameA7.set("current_wave", 5)
	gameA7.set("spawn_queue", [])
	gameA7.set("game_state", "battle")
	var dummyA7: Node = gameA7.call("_make_unit", "enemy", "enemy", "哨兵", Vector3(42, 0, -13), 3000.0, 0.0, 2.2, 1.0, 1.0)
	(gameA7.get("enemies") as Array).append(dummyA7)
	gameA7.set("assassin_timer", 0.01)
	await wait_until(func() -> bool: return false, 2.0)
	check("assassin51_no_spawn_before_wave6", _find_enemy(gameA7, "assassin") == null)
	gameA7.free()

	# 孔明数值：1 级 3500 血 / 12 攻 / 射程 6；玉玺升 2 级后 4500 血.
	var gameA8 = _make_game()
	gameA8.select_hero(0)
	var kmA8: Node = gameA8.get("kongming_unit")
	check("assassin51_kongming_stats", absf(float(kmA8.get("max_hp")) - 3500.0) < 0.01 and absf(float(kmA8.get("attack_damage")) - 12.0) < 0.01 and absf(float(kmA8.get("attack_range")) - 6.0) < 0.01)
	gameA8.set("general_level", 3)
	gameA8.call("_refresh_kongming_stats")
	check("assassin51_kongming_levels_with_yuxi", absf(float(kmA8.get("max_hp")) - 4500.0) < 0.01 and absf(float(kmA8.get("hp")) - 4500.0) < 0.01)
	gameA8.free()

	# Test 52: stage-2 calibration G1-G5 (user-approved 2026-11-15) —
	# foe growth curves, boss composite curve + spread mul table,
	# cavalry from wave 4, bounty/xp wave growth; ends with a bounded
	# live boss duel as a pressure sanity check (not a balance verdict).
	var gameC1 = _make_game()
	check("calib52_hp_scale_w1", is_equal_approx(float(gameC1.call("wave_hp_scale", 1)), 1.0))
	check("calib52_hp_scale_w11", is_equal_approx(float(gameC1.call("wave_hp_scale", 11)), 4.0))
	check("calib52_atk_scale_w11", is_equal_approx(float(gameC1.call("wave_atk_scale", 11)), 2.2))
	check("calib52_atk_scale_w20", is_equal_approx(float(gameC1.call("wave_atk_scale", 20)), 3.28))
	var comp3: Dictionary = gameC1.call("wave_composition", 3)
	check("calib52_no_cavalry_wave3", int(comp3.get("cavalry", -1)) == 0, "comp=" + str(comp3))
	var comp5: Dictionary = gameC1.call("wave_composition", 5)
	check("calib52_cavalry_wave5", int(comp5.get("cavalry", -1)) == 4 and int(comp5.get("infantry", -1)) == 16, "comp=" + str(comp5))
	var prev5: String = gameC1.call("wave_preview_text", 5)
	check("calib52_preview_lists_cavalry", "骑兵 ×4" in prev5, "preview=" + prev5)
	gameC1.set("current_wave", 1)
	check("calib52_bounty_w1_table", int(gameC1.call("bounty_for", "enemy")) == 10 and int(gameC1.call("bounty_for", "cavalry")) == 16)
	gameC1.set("current_wave", 11)
	check("calib52_bounty_w11_grown", int(gameC1.call("bounty_for", "enemy")) == 18, "b=" + str(int(gameC1.call("bounty_for", "enemy"))))
	gameC1.free()

	var gameC2 = _make_game()
	gameC2.select_hero(0)
	gameC2.set("current_wave", 6)
	gameC2.set("game_state", "battle")
	gameC2.set("spawn_queue", [])
	var cav52: Node = gameC2.call("_spawn_enemy_of_type", "cavalry")
	check("calib52_cavalry_hp", is_equal_approx(float(cav52.get("max_hp")), 250.0), "hp=" + str(float(cav52.get("max_hp"))))
	check("calib52_cavalry_atk", is_equal_approx(float(cav52.get("attack_damage")), 16.0), "atk=" + str(float(cav52.get("attack_damage"))))
	check("calib52_cavalry_fastest_regular", float(cav52.get("move_speed")) > 4.0 and float(cav52.get("move_speed")) < 5.0, "spd=" + str(float(cav52.get("move_speed"))))
	var inf52: Node = gameC2.call("_spawn_enemy_of_type", "infantry")
	check("calib52_infantry_hp_w6", is_equal_approx(float(inf52.get("max_hp")), 165.0), "hp=" + str(float(inf52.get("max_hp"))))
	check("calib52_infantry_atk_w6", is_equal_approx(float(inf52.get("attack_damage")), 11.2), "atk=" + str(float(inf52.get("attack_damage"))))
	check("calib52_foe_xp_grown_w6", int(gameC2.call("xp_for", inf52)) == 9, "xp=" + str(int(gameC2.call("xp_for", inf52))))
	gameC2.free()

	# Boss composite curve through the real queue: wave 11 徐晃
	# hp = 380 * (1+0.32*10) * 1.10^1 * 1.64 = 2879.18; atk = 14+2.2*11.
	var gameC3 = _make_game()
	gameC3.select_hero(0)
	gameC3.call("_start_wave", 11)
	await process_frame
	while not (gameC3.get("spawn_queue") as Array).is_empty():
		gameC3.call("_spawn_from_queue")
	var boss52: Node = _find_enemy(gameC3, "boss")
	check("calib52_boss_w11_hp", boss52 != null and is_equal_approx(float(boss52.get("max_hp")), 2879.18), "hp=" + str(float(boss52.get("max_hp")) if boss52 != null else -1.0))
	check("calib52_boss_w11_atk", boss52 != null and is_equal_approx(float(boss52.get("attack_damage")), 38.2), "atk=" + str(float(boss52.get("attack_damage")) if boss52 != null else -1.0))
	gameC3.free()

	# Pressure race (deterministic): a level-14 hero (+40 dmg / +800 hp
	# bonuses, standing in for mid-game gear) vs the wave-11 boss,
	# computed from the real spawned units' stats. (A live scripted
	# duel proved unreliable in harness — the hero's attack path is
	# player-order driven; bounds only, balance verdicts stay with
	# the user's device playtest.)
	var gameC4 = _make_game()
	gameC4.select_hero(0)
	gameC4.set("hero_level", 14)
	gameC4.set("hero_bonus_damage", 40.0)
	gameC4.set("hero_bonus_max_hp", 800.0)
	gameC4.call("_apply_hero_level_stats")
	gameC4.set("current_wave", 11)
	gameC4.set("game_state", "battle")
	gameC4.set("spawn_queue", [])
	gameC4.set("current_boss_list", gameC4.call("bosses_for_wave", 11))
	gameC4.set("boss_spawn_index", 0)
	var boss52f: Node = gameC4.call("_spawn_enemy_of_type", "boss")
	var gen52f: Node = gameC4.get("strategist")
	var ttk52 := float(boss52f.get("max_hp")) / maxf(float(gen52f.get("attack_damage")) / maxf(float(gen52f.get("attack_cooldown_time")), 0.01), 0.01)
	var taken52 := float(boss52f.get("attack_damage")) / maxf(float(boss52f.get("attack_cooldown_time")), 0.01) * ttk52 * 1.3
	check("calib52_race_ttk_bounded", ttk52 <= 90.0, "ttk=" + str(ttk52))
	check("calib52_race_hero_survives", taken52 < float(gen52f.get("max_hp")), "taken=" + str(taken52) + " hero_hp=" + str(float(gen52f.get("max_hp"))))
	gameC4.free()

	# ---- Test 53: boss skill damage must NOT roll attack passives
	# （倍击/致命/重击/战鼓）. The passives live in apply_damage's shared
	# funnel, so boss skills carry kind "boss_skill" and the hook skips
	# them (2D rolls crits only on the basic-attack path). Melee-kind
	# damage and unflagged (on-hit family) DoT ticks from the same boss
	# must still roll them.
	var gameG53 = _make_game()
	await process_frame
	await process_frame
	gameG53.set("_perf_enabled", false)
	gameG53.call("select_hero", 0)
	gameG53.set("spawn_queue", [])
	gameG53.set("current_boss_list", gameG53.call("bosses_for_wave", 1))
	gameG53.set("boss_spawn_index", 0)
	var hbG53: Node = gameG53.call("_spawn_enemy_of_type", "boss")
	var heroG53: Node = gameG53.get("strategist")
	hbG53.set("global_position", heroG53.global_position + Vector3(10, 0, 0))
	heroG53.set("max_hp", 1000000.0)
	heroG53.set("hp", 1000000.0)
	var aG53 := float(hbG53.get("attack_damage"))
	var baseG53 := aG53 * 9.0
	var skillFlatG53 := true
	var skillMaxG53 := 0.0
	for i in 220:
		var beforeS := float(heroG53.get("hp"))
		gameG53.call("cast_boss_skill", hbG53, "玄冰咒", heroG53)
		var dealtS := beforeS - float(heroG53.get("hp"))
		skillMaxG53 = maxf(skillMaxG53, dealtS)
		if absf(dealtS - baseG53) > 0.6:
			skillFlatG53 = false
	check("bskgate53_skill_never_crits", skillFlatG53, "base=" + str(baseG53) + " max=" + str(skillMaxG53))
	var meleeMinG53 := 1.0e9
	var meleeMaxG53 := 0.0
	for i in 300:
		var beforeM := float(heroG53.get("hp"))
		gameG53.call("apply_damage", hbG53, heroG53, aG53, "melee")
		var dealtM := beforeM - float(heroG53.get("hp"))
		meleeMinG53 = minf(meleeMinG53, dealtM)
		meleeMaxG53 = maxf(meleeMaxG53, dealtM)
	# 0.1.52 改判: melee is phys, now ×0.78295 armor; old min=a/max>2.5a -> min=a*0.78295/max>2.3a.
	# Skill 145.8 stays constant: boss_skill is non-phys.
	check("bskgate53_melee_still_crits", meleeMaxG53 > aG53 * 2.3 and absf(meleeMinG53 - aG53 * 0.78295) < 0.6, "min=" + str(meleeMinG53) + " max=" + str(meleeMaxG53))
	var dotFlatG53 := true
	gameG53.call("_apply_dot", heroG53, 20.0, 30.0, "curse", hbG53, true)
	for i in 60:
		var beforeD := float(heroG53.get("hp"))
		gameG53.call("_update_statuses", 0.5)
		var dealtD := beforeD - float(heroG53.get("hp"))
		if absf(dealtD - 10.0) > 0.6:
			dotFlatG53 = false
	check("bskgate53_skill_dot_ticks_flat", dotFlatG53)
	var dotRolledG53 := false
	gameG53.call("_apply_dot", heroG53, 20.0, 30.0, "curse", hbG53)
	for i in 60:
		var beforeU := float(heroG53.get("hp"))
		gameG53.call("_update_statuses", 0.5)
		var dealtU := beforeU - float(heroG53.get("hp"))
		if dealtU > 10.6:
			dotRolledG53 = true
	check("bskgate53_onhit_dot_still_rolls", dotRolledG53)
	gameG53.free()

	# Test 54: 0.1.52 HP, armor, tianshi, global cast gate and real-stat TTK.
	var game54a = _make_game()
	game54a.select_hero(0)
	game54a.set("game_state", "battle")
	game54a.set("spawn_queue", [])
	check("bal54_factor_anchor", absf(float(game54a.call("armor_factor", 4.62)) - 0.78295) < 0.0005)
	check("bal54_factor_zero", is_equal_approx(float(game54a.call("armor_factor", 0.0)), 1.0))
	check("bal54_factor_negative", absf(float(game54a.call("armor_factor", -10.0)) - 1.4614) < 0.001)
	var st54a: Dictionary = game54a.call("hero_stats_at", 0, 1)
	check("bal54_zhaotong_l1", is_equal_approx(float(st54a["hp"]), 816.0) and absf(float(st54a["armor"]) - 4.62) < 0.01, str(st54a))
	var st54b: Dictionary = game54a.call("hero_stats_at", 0, 8)
	check("bal54_zhaotong_l8", absf(float(st54b["hp"]) - 1154.8) < 0.5 and absf(float(st54b["armor"]) - 8.008) < 0.01, str(st54b))
	var source54: Node = game54a.call("_spawn_enemy_of_type", "infantry")
	var hero54: Node = game54a.get("strategist")
	var beforeHero54 := float(hero54.get("hp"))
	game54a.call("apply_damage", source54, hero54, 100.0, "melee")
	var dealtHero54 := beforeHero54 - float(hero54.get("hp"))
	check("bal54_melee_reduced_on_hero", absf(dealtHero54 - 78.29) < 0.6, "dealt=" + str(dealtHero54))
	var other54: Node = game54a.get("kongming_unit")
	if not is_instance_valid(other54) or not bool(other54.get("alive")):
		other54 = game54a.get("general")
	var beforeOther54 := float(other54.get("hp"))
	game54a.call("apply_damage", source54, other54, 100.0, "melee")
	var dealtOther54 := beforeOther54 - float(other54.get("hp"))
	check("bal54_melee_full_on_nonhero", absf(dealtOther54 - 100.0) < 0.01, "dealt=" + str(dealtOther54))
	game54a.free()

	var game54c = _make_game()
	game54c.select_hero(0)
	game54c.set("hero_level", 8)
	game54c.call("_apply_hero_level_stats")
	game54c.set("current_wave", 6)
	game54c.set("game_state", "battle")
	game54c.set("spawn_queue", [])
	game54c.set("current_boss_list", game54c.call("bosses_for_wave", 6))
	game54c.set("boss_spawn_index", 0)
	var bossc54: Node = game54c.call("_spawn_enemy_of_type", "boss")
	var atkc54 := float(bossc54.get("attack_damage"))
	var maxhpc54 := float(game54c.get("strategist").get("max_hp"))
	check("bal54_tianshi_w6", atkc54 * 7.5 <= maxhpc54 * 0.30, "dmg=" + str(atkc54 * 7.5) + " hp=" + str(maxhpc54))
	check("bal54_tianshi_mult", is_equal_approx(float((game54c.get("BSK_DEF") as Dictionary)["天石术"]["mult"]), 7.5))
	game54c.free()

	var game54d = _make_game()
	game54d.select_hero(0)
	game54d.set("hero_level", 10)
	game54d.call("_apply_hero_level_stats")
	game54d.set("current_wave", 8)
	game54d.set("game_state", "battle")
	game54d.set("spawn_queue", [])
	game54d.set("current_boss_list", game54d.call("bosses_for_wave", 8))
	game54d.set("boss_spawn_index", 0)
	var bossd54: Node = game54d.call("_spawn_enemy_of_type", "boss")
	var atkd54 := float(bossd54.get("attack_damage"))
	var maxhpd54 := float(game54d.get("strategist").get("max_hp"))
	check("bal54_tianshi_w8", atkd54 * 7.5 <= maxhpd54 * 0.30, "dmg=" + str(atkd54 * 7.5) + " hp=" + str(maxhpd54))
	game54d.free()

	var game54e = _make_game()
	game54e.select_hero(0)
	game54e.set("hero_level", 18)
	game54e.call("_apply_hero_level_stats")
	game54e.set("current_wave", 18)
	game54e.set("game_state", "battle")
	game54e.set("spawn_queue", [])
	game54e.set("current_boss_list", game54e.call("bosses_for_wave", 18))
	game54e.set("boss_spawn_index", 0)
	var bosse54: Node = game54e.call("_spawn_enemy_of_type", "boss")
	var atke54 := float(bosse54.get("attack_damage"))
	var maxhpe54 := float(game54e.get("strategist").get("max_hp"))
	check("bal54_tianshi_w18", atke54 * 7.5 <= maxhpe54 * 0.30, "dmg=" + str(atke54 * 7.5) + " hp=" + str(maxhpe54))
	game54e.free()

	var game54f = _make_game()
	game54f.select_hero(0)
	var gateHero54: Node = game54f.get("strategist")
	gateHero54.set("max_hp", 1000000.0)
	gateHero54.set("hp", 1000000.0)
	game54f.set("current_wave", 6)
	game54f.set("game_state", "battle")
	game54f.set("spawn_queue", [])
	game54f.set("current_boss_list", game54f.call("bosses_for_wave", 6))
	game54f.set("boss_spawn_index", 0)
	for bossIndex54 in 3:
		var gateBoss54: Node = game54f.call("_spawn_enemy_of_type", "boss")
		gateBoss54.set("global_position", gateHero54.global_position + Vector3(8, 0, float(bossIndex54) * 1.5))
		gateBoss54.set_meta("bsk_next_cast", 0.0)
		# 隔离观测：门内技能统一为即时直伤，施法即伤害事件。
		gateBoss54.set_meta("boss_skills", ["玄冰咒"])
	var t54 := 100.0
	game54f.set("elapsed", t54)
	game54f.set("bsk_global_next_cast", 0.0)
	var base54 := int(game54f.get("last_damage_events"))
	var gateTimes54: Array = []
	for step54 in 120:
		t54 += 0.05
		game54f.set("elapsed", t54)
		game54f.call("_update_boss_skills", 0.05)
		var cur54 := int(game54f.get("last_damage_events"))
		var diff54 := cur54 - base54
		while diff54 > 0:
			gateTimes54.append(t54)
			diff54 -= 1
		base54 = cur54
	var mingap54 := INF
	var firstWindow54 := 0
	for timeIndex54 in gateTimes54.size():
		if float(gateTimes54[timeIndex54]) < 101.30:
			firstWindow54 += 1
		if timeIndex54 > 0:
			mingap54 = minf(mingap54, float(gateTimes54[timeIndex54]) - float(gateTimes54[timeIndex54 - 1]))
	# 观测口径=伤害事件（审计 2026-11-16 指出门变量观测会被同帧覆写掩盖齐射，故改测真实施法）。
	check("bal54_gate_casts_not_lost", gateTimes54.size() >= 3, "times=" + str(gateTimes54))
	check("bal54_gate_min_gap", gateTimes54.size() >= 3 and mingap54 >= 1.30, "times=" + str(gateTimes54))
	check("bal54_gate_first_window_single", firstWindow54 == 1, "times=" + str(gateTimes54))
	game54f.free()

	var game54g = _make_game()
	game54g.select_hero(0)
	game54g.set("current_wave", 1)
	game54g.set("game_state", "battle")
	game54g.set("spawn_queue", [])
	game54g.set("current_boss_list", game54g.call("bosses_for_wave", 1))
	game54g.set("boss_spawn_index", 0)
	var bossg54: Node = game54g.call("_spawn_enemy_of_type", "boss")
	var infg54: Node = game54g.call("_spawn_enemy_of_type", "infantry")
	var bossAg54 := float(bossg54.get("attack_damage"))
	var bossCdg54 := float(bossg54.get("attack_cooldown_time"))
	var infAg54 := float(infg54.get("attack_damage"))
	var infCdg54 := float(infg54.get("attack_cooldown_time"))
	var statsg54: Dictionary = game54g.call("hero_stats_at", 0, 1)
	var dpsRawg54 := bossAg54 / bossCdg54 + 8.0 * infAg54 / infCdg54
	var ttkNewg54 := float(statsg54["hp"]) / (dpsRawg54 * float(game54g.call("armor_factor", float(statsg54["armor"]))))
	var hpOldg54 := 250.0 + float(statsg54["str"]) * 16.0 + float(1 - 1) * 12.0
	var ttkOldg54 := hpOldg54 / dpsRawg54
	check("bal54_ttk_fix_w1", ttkNewg54 >= 1.8 * ttkOldg54, "new=" + str(ttkNewg54) + " old=" + str(ttkOldg54))
	game54g.free()

	var game54h = _make_game()
	game54h.select_hero(0)
	game54h.set("current_wave", 6)
	game54h.set("game_state", "battle")
	game54h.set("spawn_queue", [])
	game54h.set("current_boss_list", game54h.call("bosses_for_wave", 6))
	game54h.set("boss_spawn_index", 0)
	var bossh54: Node = game54h.call("_spawn_enemy_of_type", "boss")
	var infh54: Node = game54h.call("_spawn_enemy_of_type", "infantry")
	var bossAh54 := float(bossh54.get("attack_damage"))
	var bossCdh54 := float(bossh54.get("attack_cooldown_time"))
	var infAh54 := float(infh54.get("attack_damage"))
	var infCdh54 := float(infh54.get("attack_cooldown_time"))
	var statsh54: Dictionary = game54h.call("hero_stats_at", 0, 8)
	var dpsRawh54 := bossAh54 / bossCdh54 + 8.0 * infAh54 / infCdh54
	var ttkNewh54 := float(statsh54["hp"]) / (dpsRawh54 * float(game54h.call("armor_factor", float(statsh54["armor"]))))
	var hpOldh54 := 250.0 + float(statsh54["str"]) * 16.0 + float(8 - 1) * 12.0
	var ttkOldh54 := hpOldh54 / dpsRawh54
	check("bal54_ttk_fix_w6", ttkNewh54 >= 1.8 * ttkOldh54, "new=" + str(ttkNewh54) + " old=" + str(ttkOldh54))
	game54h.free()

	var game54i = _make_game()
	game54i.select_hero(0)
	game54i.set("current_wave", 10)
	game54i.set("game_state", "battle")
	game54i.set("spawn_queue", [])
	game54i.set("current_boss_list", game54i.call("bosses_for_wave", 10))
	game54i.set("boss_spawn_index", 0)
	var bossi54: Node = game54i.call("_spawn_enemy_of_type", "boss")
	var infi54: Node = game54i.call("_spawn_enemy_of_type", "infantry")
	var bossAi54 := float(bossi54.get("attack_damage"))
	var bossCdi54 := float(bossi54.get("attack_cooldown_time"))
	var infAi54 := float(infi54.get("attack_damage"))
	var infCdi54 := float(infi54.get("attack_cooldown_time"))
	var statsi54: Dictionary = game54i.call("hero_stats_at", 0, 13)
	var dpsRawi54 := bossAi54 / bossCdi54 + 8.0 * infAi54 / infCdi54
	var ttkNewi54 := float(statsi54["hp"]) / (dpsRawi54 * float(game54i.call("armor_factor", float(statsi54["armor"]))))
	var hpOldi54 := 250.0 + float(statsi54["str"]) * 16.0 + float(13 - 1) * 12.0
	var ttkOldi54 := hpOldi54 / dpsRawi54
	check("bal54_ttk_fix_w10", ttkNewi54 >= 1.8 * ttkOldi54, "new=" + str(ttkNewi54) + " old=" + str(ttkOldi54))
	game54i.free()

	# Test 55: 0.1.53 per-skill boss CD keys are ASCII (BSK_CD_ID) — the old
	# Chinese meta keys never wrote, so per-skill CDs were dead since 0.1.33.
	# Observation is by real damage events (last_damage_events), never by the
	# CD meta itself; the rotation block identifies skills by damage amount.
	var game55a = _make_game()
	var def55: Dictionary = game55a.get("BSK_DEF")
	var map55: Dictionary = game55a.get("BSK_CD_ID")
	var mapOk55 := true
	var seen55: Dictionary = {}
	for k55 in def55.keys():
		var nm55 := String(k55)
		if not map55.has(nm55):
			mapOk55 = false
			continue
		var id55 := String(map55[nm55])
		if seen55.has(id55):
			mapOk55 = false
		seen55[id55] = true
		if not ("bsk_cd_" + id55).is_valid_identifier():
			mapOk55 = false
	check("cdfix55_cd_map_complete", mapOk55 and seen55.size() == def55.size(), "defs=" + str(def55.size()) + " mapped=" + str(seen55.size()))
	game55a.free()

	var game55b = _make_game()
	game55b.select_hero(0)
	var hero55b: Node = game55b.get("strategist")
	hero55b.set("max_hp", 1000000.0)
	hero55b.set("hp", 1000000.0)
	game55b.set("current_wave", 6)
	game55b.set("game_state", "battle")
	game55b.set("spawn_queue", [])
	game55b.set("current_boss_list", game55b.call("bosses_for_wave", 6))
	game55b.set("boss_spawn_index", 0)
	var boss55b: Node = game55b.call("_spawn_enemy_of_type", "boss")
	boss55b.set("global_position", hero55b.global_position + Vector3(8, 0, 0))
	boss55b.set_meta("bsk_next_cast", 0.0)
	boss55b.set_meta("boss_skills", ["玄冰咒"])
	var t55b := 100.0
	game55b.set("elapsed", t55b)
	game55b.set("bsk_global_next_cast", 0.0)
	var base55b := int(game55b.get("last_damage_events"))
	var times55b: Array = []
	for step55b in 300:
		t55b += 0.05
		game55b.set("elapsed", t55b)
		game55b.call("_update_boss_skills", 0.05)
		var cur55b := int(game55b.get("last_damage_events"))
		while cur55b > base55b:
			times55b.append(t55b)
			base55b += 1
	check("cdfix55_single_skill_cast_count", times55b.size() == 2, "times=" + str(times55b))
	check("cdfix55_single_skill_cd_gap", times55b.size() == 2 and float(times55b[1]) - float(times55b[0]) >= 11.9, "times=" + str(times55b))
	game55b.free()

	var game55c = _make_game()
	game55c.select_hero(0)
	var hero55c: Node = game55c.get("strategist")
	hero55c.set("max_hp", 1000000.0)
	hero55c.set("hp", 1000000.0)
	game55c.set("current_wave", 6)
	game55c.set("game_state", "battle")
	game55c.set("spawn_queue", [])
	game55c.set("current_boss_list", game55c.call("bosses_for_wave", 6))
	game55c.set("boss_spawn_index", 0)
	var boss55c: Node = game55c.call("_spawn_enemy_of_type", "boss")
	boss55c.set("global_position", hero55c.global_position + Vector3(8, 0, 0))
	boss55c.set_meta("bsk_next_cast", 0.0)
	boss55c.set_meta("boss_skills", ["玄冰咒", "玄冰爆"])
	var atk55c := float(boss55c.get("attack_damage"))
	var t55c := 100.0
	game55c.set("elapsed", t55c)
	game55c.set("bsk_global_next_cast", 0.0)
	var base55c := int(game55c.get("last_damage_events"))
	var hpPrev55c := float(hero55c.get("hp"))
	var times55c: Array = []
	var dmgs55c: Array = []
	for step55c in 300:
		t55c += 0.05
		game55c.set("elapsed", t55c)
		game55c.call("_update_boss_skills", 0.05)
		var cur55c := int(game55c.get("last_damage_events"))
		if cur55c > base55c:
			times55c.append(t55c)
			dmgs55c.append(hpPrev55c - float(hero55c.get("hp")))
			base55c = cur55c
		hpPrev55c = float(hero55c.get("hp"))
	check("cdfix55_rotation_casts_three", times55c.size() >= 3, "times=" + str(times55c) + " dmgs=" + str(dmgs55c))
	check("cdfix55_rotation_damage_pattern", dmgs55c.size() >= 3 and absf(float(dmgs55c[0]) - atk55c * 9.0) < 1.5 and absf(float(dmgs55c[1]) - atk55c * 7.0) < 1.5 and absf(float(dmgs55c[2]) - atk55c * 9.0) < 1.5, "dmgs=" + str(dmgs55c) + " atk=" + str(atk55c))
	check("cdfix55_rotation_second_cast_prompt", times55c.size() >= 3 and float(times55c[1]) - float(times55c[0]) <= 2.2 and float(times55c[2]) - float(times55c[0]) >= 11.9, "times=" + str(times55c))
	game55c.free()

	var wallet: WalletManager = root.get_node("Wallet")
	wallet.disconnect_wallet()
	var wallet_game := _make_game()
	var select_wallet: Button = wallet_game.get("wallet_button_select")
	var hud_wallet: Button = wallet_game.get("wallet_button_hud")
	var panel_wallet: PanelContainer = wallet_game.get("wallet_panel")
	var fallback_wallet: Label = wallet_game.get("wallet_fallback_label")
	var status_wallet: Label = wallet_game.get("wallet_status_label")
	check("wallet_entry_initial_guest", not wallet.is_wallet_connected() and wallet.address == "", "address=" + wallet.address)
	check("wallet_entry_select_button_present", select_wallet != null and select_wallet.is_inside_tree() and select_wallet.text == "钱包", "select button")
	check("wallet_entry_select_button_in_select_panel", select_wallet != null and (wallet_game.get("select_panel") as Node).is_ancestor_of(select_wallet), "select panel ancestry")
	check("wallet_entry_hud_button_present", hud_wallet != null and hud_wallet.is_inside_tree() and hud_wallet.text == "钱包", "hud button")
	check("wallet_entry_panel_initially_hidden", panel_wallet != null and not panel_wallet.visible, "initially hidden")
	wallet_game.call("_open_wallet_panel")
	check("wallet_entry_panel_opens_unconnected", panel_wallet.visible and fallback_wallet.text == WalletManager.ERR_MWA_UNAVAILABLE and (wallet.is_mwa_available() or fallback_wallet.visible), "open and fallback")
	check("wallet_entry_panel_sane_size", panel_wallet.get_combined_minimum_size().y < 900.0 and panel_wallet.get_combined_minimum_size().x <= 600.0, "min_size=" + str(panel_wallet.get_combined_minimum_size()))
	wallet_game.call("_close_wallet_panel")
	check("wallet_entry_panel_closes", not panel_wallet.visible, "closed")
	check("wallet_entry_status_guest_text", "游客" in status_wallet.text, status_wallet.text)
	wallet_game.free()

	_finish()


func _finish() -> void:
	print("== HARNESS RESULT: passed=", passed, " failed=", failed, " total=", passed + failed, " ==")
	if failures.size() > 0:
		print("Failed checks: ", failures)
	quit(1 if failed > 0 else 0)
