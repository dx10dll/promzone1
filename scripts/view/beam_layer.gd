class_name BeamLayer
extends Node2D
## Полосы дневного света из окон на полу.

const T := World.T

var sim: Sim
var alpha := 0.0
var _drawn_alpha := -1.0


func set_alpha(a: float) -> void:
	alpha = a
	if absf(alpha - _drawn_alpha) > 0.02:
		queue_redraw()


func _draw() -> void:
	_drawn_alpha = alpha
	if sim == null or alpha <= 0.01:
		return
	var w := sim.world
	var col := Color(1.0, 0.96, 0.82, 0.13 * alpha)
	for y in w.h:
		for x in w.w:
			var c := Vector2i(x, y)
			if w.get_wall(c) != World.W_WINDOW:
				continue
			var vertical := WallKinds.is_room_wall(w.get_wall(c + Vector2i(0, -1))) or WallKinds.is_room_wall(w.get_wall(c + Vector2i(0, 1)))
			if vertical:
				# окно в боковой стене: свет падает внутрь вправо или влево
				var right_in := w.get_floor(c + Vector2i(1, 0)) > 0 and w.get_wall(c + Vector2i(1, 0)) == World.W_NONE
				var x0 := (x + 1) * T if right_in else x * T
				var dir := 1.0 if right_in else -1.0
				var pts := PackedVector2Array([
					Vector2(x0, y * T + 3), Vector2(x0, y * T + T - 3),
					Vector2(x0 + dir * 2.6 * T, y * T + T - 3 + 0.8 * T), Vector2(x0 + dir * 2.6 * T, y * T + 3 + 0.8 * T)])
				draw_colored_polygon(pts, col)
				continue
			if w.get_floor(c + Vector2i(0, 1)) == 0:
				continue
			var top := (y + 1) * T + 2.0
			var pts2 := PackedVector2Array([
				Vector2(x * T + 3, top), Vector2(x * T + T - 3, top),
				Vector2(x * T + T - 3 + 1.1 * T, top + 2.8 * T), Vector2(x * T + 3 + 1.1 * T, top + 2.8 * T)])
			draw_colored_polygon(pts2, col)
