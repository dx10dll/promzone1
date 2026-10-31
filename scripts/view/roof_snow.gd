class_name RoofSnow
extends Node2D
## 1.55: снег на крышах городских зданий зимой (и тонкий — в снегопад в соседние сезоны не рисуется).

var sim: Sim
var roofs: Array[Rect2] = []
var _on := false


func _process(_d: float) -> void:
	if sim == null:
		return
	var on := SeasonLook.look(sim.season.season_id()) == "winter"
	if on != _on:
		_on = on
		queue_redraw()


func _draw() -> void:
	if not _on:
		return
	for r in roofs:
		draw_rect(r, Color(0.94, 0.96, 1.0, 0.82))
		draw_rect(r.grow(-3.0), Color(1, 1, 1, 0.5))
		draw_rect(Rect2(r.position, Vector2(r.size.x, 3.0)), Color(0.8, 0.86, 0.95, 0.9))
