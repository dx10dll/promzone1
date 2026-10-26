class_name NetGhostLayer
extends Node2D
## 1.50b: заказанные, но ещё не проложенные сети (кабель, труба, воздуховод, пневмомагистраль) — всегда на карте
## полупрозрачным призраком (~40%). Тянут сейчас — оранжевый пунктир по клетке; не могут начать (нет доступа
## или некому тянуть) — красноватый призрак с «!» и причиной рядом с курсором. Построенные рисует прежний код.

const T := World.T
const LAYERS := ["cable", "pipe", "air", "duct"]
const COLS := {"cable": Color("#f2c84b"), "pipe": Color("#4a9fe0"), "air": Color("#e2843a"), "duct": Color("#a3adb4")}
const LANE := {"cable": -9.0, "pipe": -3.0, "air": 3.0, "duct": 9.0}
const WIDTH := {"cable": 2.6, "pipe": 4.8, "air": 3.0, "duct": 7.6}
const ALPHA := 0.4

var sim: Sim
var _sig := ""
var _hover := Vector2i(-1, -1)


## Почему сеть в этой клетке не может быть проложена сейчас ("" — всё в порядке).
static func reason(s: Sim, layer: String, i: int) -> String:
	var w := s.world
	var c := w.cell_of(i)
	var ok := w.passable(c)
	if not ok:
		for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			if w.passable(c + d):
				ok = true
				break
	if not ok:
		return L.t("Нет доступа: к клетке не подойти")
	var can := false
	for wk: Worker in s.workers:
		if wk.visitor:
			continue
		var p := str(wk.prof)
		if p in ["builder", "laborer"] or (layer == "cable" and p == "electrician"):
			can = true
			break
	if not can:
		return L.t("Некому тянуть: нужен строитель") if layer != "cable" else L.t("Некому тянуть: нужен электрик или строитель")
	return ""


func _process(_d: float) -> void:
	if sim == null:
		return
	var mc := Vector2i(floori(get_local_mouse_position().x / T), floori(get_local_mouse_position().y / T))
	var w := sim.world
	var s := "%d|%d|%d|%d|%d|%d|%d" % [w.cable_rev, w.pipe_rev, w.duct_rev, w.air_rev, sim.net_res.size(), sim.workers.size(), int(Time.get_ticks_msec() / 400) if not sim.net_res.is_empty() else 0]
	if sim.net_plans().is_empty():
		if _sig != "":
			_sig = ""
			queue_redraw()
		return
	if mc != _hover:
		_hover = mc
		s += "h%d,%d" % [mc.x, mc.y]
	else:
		s += "h%d,%d" % [_hover.x, _hover.y]
	if s != _sig:
		_sig = s
		queue_redraw()


func _pt(c: Vector2i, o: float) -> Vector2:
	return (Vector2(c) + Vector2(0.5, 0.5)) * T + Vector2(o, o)


func _draw() -> void:
	if sim == null:
		return
	var w := sim.world
	var hint := ""
	var hint_at := Vector2.ZERO
	for pr: Array in sim.net_plans():
		var lay := str(pr[0])
		var i := int(pr[1])
		var c := w.cell_of(i)
		var arr := w.net_layer(lay)
		var o: float = LANE[lay]
		var busy := sim.net_res.has("%s:%d" % [lay, i])
		var why := ""
		if not busy:
			why = reason(sim, lay, i)
		var col: Color = COLS[lay]
		if why != "":
			col = Color("#d8584a")
		var a := _pt(c, o)
		var wd: float = WIDTH[lay]
		var linked := false
		for d: Vector2i in [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1)]:
			var nc := c + d
			if not w.inb(nc):
				continue
			var nv := int(arr[w.idx(nc)])
			if nv == 0 or (nv == 2 and (d.x < 0 or d.y < 0)):
				continue
			linked = true
			var b := _pt(nc, o)
			if nv == 1:
				b = a.lerp(b, 0.5)
			draw_line(a, b, Color(col.r, col.g, col.b, ALPHA), wd)
		draw_circle(a, wd * 0.8 + 1.0, Color(col.r, col.g, col.b, ALPHA + (0.1 if linked else 0.0)))
		if busy:
			var r := Rect2(Vector2(c) * T, Vector2(T, T)).grow(-3)
			# пунктирная рамка — клетку тянут прямо сейчас
			var seg := 6.0
			var ph := float(int(Time.get_ticks_msec() / 400) % 2) * seg
			var pts := [r.position, r.position + Vector2(r.size.x, 0), r.end, r.position + Vector2(0, r.size.y), r.position]
			for k in 4:
				var p0: Vector2 = pts[k]
				var p1: Vector2 = pts[k + 1]
				var ln := p0.distance_to(p1)
				var t := ph
				while t < ln:
					draw_line(p0.lerp(p1, t / ln), p0.lerp(p1, minf(ln, t + seg) / ln), Color(1.0, 0.6, 0.2, 0.9), 1.6)
					t += seg * 2.0
		elif why != "":
			draw_rect(Rect2(Vector2(c) * T, Vector2(T, T)).grow(-2), Color(0.85, 0.3, 0.25, 0.14))
			if c == _hover:
				hint = why
				hint_at = Vector2(c) * T + Vector2(T * 0.5, -6.0)
	if hint != "":
		var f := ThemeDB.fallback_font
		var z := maxf(0.25, get_global_transform_with_canvas().get_scale().x)
		draw_set_transform(hint_at, 0.0, Vector2(1.0 / z, 1.0 / z))
		var px := 13
		var sz := f.get_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, -1, px)
		draw_rect(Rect2(Vector2(-sz.x * 0.5 - 4.0, -sz.y - 1.0), sz + Vector2(8.0, 4.0)), Color(0.1, 0.05, 0.05, 0.85))
		draw_string(f, Vector2(-sz.x * 0.5, -3.0), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, px, Color("#ff9a8a"))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
