extends SceneTree
## Diagnostic probe: reproduce Test 28 (CJK font) step by step with a
## flushed file log, to locate the hang seen in the full harness (stalls
## right after Test 27's last PASS in two runs).
## Run: godot --headless --path . --script res://scripts/probe_font28.gd

var _log: FileAccess


func _w(msg: String) -> void:
	if _log != null:
		_log.store_line(msg)
		_log.flush()
	print(msg)


func _initialize() -> void:
	_log = FileAccess.open("res://.tmp/probe_font28.log", FileAccess.WRITE)
	_w("step0 start")
	_run()


func _run() -> void:
	_w("step1 setting=" + str(ProjectSettings.get_setting("gui/theme/custom_font")))
	var font_reg: Font = load("res://assets/fonts/NotoSansCJKsc-Regular.ttf")
	var font_bold: Font = load("res://assets/fonts/NotoSansCJKsc-Bold.ttf")
	_w("step2 fonts loaded reg=" + str(font_reg != null) + " bold=" + str(font_bold != null))
	var sample: Array = [0x5251, 0x59DC, 0x7EF4, 0x9009, 0x62E9, 0x82F1, 0x96C4, 0x5C01, 0x5370, 0x6838, 0x8BAD, 0x7EC3, 0x573A, 0x4E0A, 0x65B9, 0x8C37, 0x51B3, 0x6218, 0x5E7F, 0x5175, 0x5C06]
	var ok := true
	for cp in sample:
		if not font_reg.has_char(cp):
			ok = false
	_w("step3 has_char sample ok=" + str(ok))
	_w("step4 make_game start")
	var packed: PackedScene = load("res://scenes/main.tscn")
	var game: Node = packed.instantiate()
	root.add_child(game)
	_w("step5 game added")
	await process_frame
	await process_frame
	_w("step6 two frames done")
	var msg: Label = game.get("message_label")
	_w("step7 message_label font==bold " + str(msg != null and msg.get_theme_font("font") == font_bold))
	var detail: Label = game.get("hero_detail_label")
	_w("step8 detail_label font==reg " + str(detail != null and detail.get_theme_font("font") == font_reg))
	var signs: Array = game.find_children("*", "Label3D", true, false)
	var sign_ok := false
	for s in signs:
		var l := s as Label3D
		if l != null and String(l.text).contains("训练场"):
			sign_ok = l.font == font_reg
	_w("step9 signs=" + str(signs.size()) + " sign_ok=" + str(sign_ok))
	_w("step10 free start")
	game.free()
	_w("step11 freed, quitting")
	_log.close()
	quit(0)
