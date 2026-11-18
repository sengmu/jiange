extends Node3D
## Quick anchor diagnostic for the 0.1.44 geometry round: prints anchor
## values + sizes of the UI root and right-anchored controls, then quits.

var game: Node


func _ready() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	_run()


func _run() -> void:
	await get_tree().create_timer(2.0).timeout
	var vp := get_viewport().get_visible_rect().size
	var win := get_window().size
	print("GEOQ vp=", vp, " window=", win)
	var mm = game.get("_minimap")
	if mm != null:
		var c := mm as Control
		print("GEOQ minimap anchors L/T/R/B=", c.anchor_left, "/", c.anchor_top, "/", c.anchor_right, "/", c.anchor_bottom, " offsets=", c.offset_left, "/", c.offset_right, " rect=", c.get_global_rect(), " parent_size=", (c.get_parent() as Control).size if c.get_parent() is Control else "n/a")
	var bs = game.get("_big_skill_button")
	if bs != null:
		var b := bs as Control
		print("GEOQ bigskill anchors R/B=", b.anchor_right, "/", b.anchor_bottom, " offsets=", b.offset_left, "/", b.offset_right, " rect=", b.get_global_rect())
	var msg = game.get("message_label")
	if msg != null:
		var m := msg as Control
		print("GEOQ message anchors L/R=", m.anchor_left, "/", m.anchor_right, " offsets=", m.offset_left, "/", m.offset_right, " rect=", m.get_global_rect(), " minsize=", m.get_combined_minimum_size())
	print("GEOQ insets=", game.get("_safe_insets"))
	get_tree().quit()
