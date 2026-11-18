extends Control
## Virtual joystick overlay (touch UI only, 2026-11-14 手游操作改版).
## main.gd routes the touch events; this control only tracks the
## geometry (floating origin + clamped knob) and draws itself.

var active: bool = false
var origin: Vector2 = Vector2.ZERO
var knob: Vector2 = Vector2.ZERO
var radius: float = 92.0


func is_in_zone(pos: Vector2, vp: Vector2) -> bool:
	return pos.x < vp.x * 0.45 and pos.y > vp.y * 0.35


func engage(pos: Vector2) -> void:
	active = true
	origin = pos
	knob = pos
	queue_redraw()


func drag_to(pos: Vector2) -> void:
	if not active:
		return
	knob = pos
	if knob.distance_to(origin) > radius:
		knob = origin + (knob - origin).normalized() * radius
	queue_redraw()


func disengage() -> void:
	active = false
	queue_redraw()


func travel() -> float:
	return knob.distance_to(origin)


func value() -> Vector2:
	if not active:
		return Vector2.ZERO
	var v := (knob - origin) / radius
	if v.length() > 1.0:
		v = v.normalized()
	if v.length() < 0.16:
		return Vector2.ZERO
	return v


func _draw() -> void:
	if not active:
		return
	draw_circle(origin, radius, Color(0.09, 0.07, 0.03, 0.38))
	draw_arc(origin, radius, 0.0, TAU, 48, Color(0.788, 0.635, 0.153, 0.75), 3.5)
	draw_circle(knob, 38.0, Color(0.788, 0.635, 0.153, 0.35))
	draw_arc(knob, 38.0, 0.0, TAU, 40, Color(0.910, 0.780, 0.400, 0.85), 3.0)
