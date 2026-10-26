class_name CompanySign
extends Node2D
## 1.17: арка с вывеской над воротами участка — эмблема и название завода. Ночью вывеска подсвечена.

const T := World.T

var sim: Sim
var _sig := ""


func _process(_d: float) -> void:
	if sim == null:
		return
	var sig := "%d|%s|%s|%.3f" % [sim.company_rev, _is_lit(), sim.progress.ooo, Tex.wscale()]
	if sig != _sig:
		_sig = sig
		queue_redraw()


func _is_lit() -> bool:
	return sim.tod() < 7.0 * 60.0 or sim.tod() > 19.0 * 60.0


func _draw() -> void:
	if sim == null:
		return
	var w := sim.world
	var fy := w.plot.end.y
	var gx := sim.gate_x
	if not w.inb(Vector2i(gx, fy)) or w.wall[w.idx(Vector2i(gx, fy))] != World.W_FENCE_GATE:
		return
	var x0 := gx * T - 6.0
	var x1 := (gx + 4) * T + 6.0
	var base := (fy + 1) * T - 4.0
	var bh := T * 1.05
	var by := fy * T - T * 1.55
	# столбы арки
	for x in [x0, x1 - 7.0]:
		draw_rect(Rect2(x + 1.5, by + 4.0, 7, base - by - 4.0), Color(0, 0, 0, 0.18))
		draw_rect(Rect2(x, by + 2.0, 7, base - by - 2.0), Color("#5a6268"))
		draw_rect(Rect2(x, by + 2.0, 2, base - by - 2.0), Color("#7d878d"))
		draw_rect(Rect2(x - 2.0, base - 4.0, 11, 4), Color("#3a3f43"))
	# табличка
	var r := Rect2(x0 - 4.0, by, x1 - x0 + 8.0, bh)
	draw_rect(Rect2(r.position + Vector2(2, 3), r.size), Color(0, 0, 0, 0.25))
	draw_rect(r, Color("#8a9399"))
	var inner := r.grow(-3.0)
	draw_rect(inner, Color("#1d2a38"))
	draw_rect(Rect2(inner.position, Vector2(inner.size.x, 3)), Color(1, 1, 1, 0.07))
	var spec := Company.emblem_of(sim)
	var lit := _is_lit()
	var col := Color("#fff4d6") if lit else Color("#f2efe6")
	Emblem.draw_sign_plate(self, inner, spec, Company.name_of(sim), L.t("ООО") if sim.progress.ooo else L.t("МАСТЕРСКАЯ"), col, true)
	if lit:
		draw_rect(r.grow(6.0), Color(1.0, 0.85, 0.5, 0.06))
		draw_rect(r.grow(2.0), Color(1.0, 0.85, 0.5, 0.08))
