class_name FaunaLayer
extends Node2D
## 1.22: голуби и мыши — рисуются векторно (чётко при любом зуме). Голубь: серое тельце, тёмные крылья,
## переливчатая шея, клюёт; в полёте машет крыльями, на земле под ним — тень. Мышь: серая, с хвостиком.

const T := World.T
var sim: Sim
var _t := 0.0
var _had := false

const BODY := Color("#9aa2ad")
const WING := Color("#717b88")
const DARK := Color("#3b4048")
const NECK_G := Color("#5f9a7a")
const NECK_P := Color("#8a6a9e")
const BELLY := Color("#b9c0ca")
const BAR := Color("#2e333a")
const LEG := Color("#d0584a")
const BEAK := Color("#5c5f66")


func _process(delta: float) -> void:
	_t += delta
	if sim and sim.fauna and (not sim.fauna.pigeons.is_empty() or not sim.fauna.mice.is_empty() or _had):
		_had = not sim.fauna.pigeons.is_empty() or not sim.fauna.mice.is_empty()
		queue_redraw()


func _draw() -> void:
	if sim == null or sim.fauna == null:
		return
	var i := 0
	for p: Dictionary in sim.fauna.pigeons:
		i += 1
		_pigeon(p, i)
	for m: Dictionary in sim.fauna.mice:
		if str(m["st"]) != "hide":
			_mouse(m)


func _pigeon(p: Dictionary, i: int) -> void:
	var pos: Vector2 = p["pos"]
	var at := pos * T
	var dir := float(p.get("dir", 1))
	var st := str(p["st"])
	if st == "gone":
		return
	var alt := 0.0
	if st == "fly":
		var from: Vector2 = p.get("from", pos)
		var to: Vector2 = p["to"]
		var tot := maxf(0.5, from.distance_to(to))
		var k := clampf(1.0 - pos.distance_to(to) / tot, 0.0, 1.0)
		alt = sin(k * PI) * minf(46.0, 12.0 + tot * 2.0)
		if bool(p.get("leave", false)):
			alt = maxf(alt, 18.0 + k * 40.0)
	# тень
	draw_set_transform(at + Vector2(0, 1), 0.0, Vector2(1, 0.45))
	draw_circle(Vector2.ZERO, 4.6 if alt < 1.0 else 3.6, Color(0, 0, 0, 0.22 if alt < 1.0 else 0.12))
	draw_set_transform(at + Vector2(0, -alt), 0.0, Vector2(dir, 1))
	var bob := 0.0
	var peck := st == "peck" and fmod(_t * 1.7 + i * 0.37, 1.6) < 0.35
	if st == "walk":
		bob = absf(sin(_t * 12.0 + i)) * 0.8
	var by := -5.2 - bob
	var fly := st == "fly"
	var flap := sin(_t * 22.0 + i) * 0.5 + 0.5
	var tip_y := -9.0 + flap * 12.0
	# лапки: красно-розовые, с пальцами
	if not fly:
		var step := sin(_t * 12.0 + i) * 0.9 if st == "walk" else 0.0
		for lx: float in [-0.8 - step, 1.6 + step]:
			draw_line(Vector2(lx, -2.2), Vector2(lx - 0.2, 0.0), LEG, 0.9)
			draw_line(Vector2(lx - 1.5, 0.1), Vector2(lx + 1.2, 0.1), LEG, 0.8)
			draw_line(Vector2(lx - 0.2, 0.0), Vector2(lx - 0.4, 0.5), LEG, 0.6)
	else:
		draw_line(Vector2(0.6, by + 3.0), Vector2(-0.4, by + 4.2), LEG, 0.8)
	draw_set_transform(at + Vector2(0, -alt) + Vector2(0, by), 0.0, Vector2(dir, 1))
	# дальнее крыло (в полёте), хвост веером
	if fly:
		_wing(tip_y, WING.darkened(0.22), true)
	_poly(PackedVector2Array([Vector2(-4.4, -1.0), Vector2(-10.6, -2.0), Vector2(-11.4, 0.0), Vector2(-10.4, 1.9), Vector2(-4.2, 1.6)]), BODY.darkened(0.2), DARK, 0.6)
	draw_line(Vector2(-6.0, -0.2), Vector2(-10.4, -1.2), DARK, 0.5)
	draw_line(Vector2(-6.0, 0.6), Vector2(-10.9, 0.3), DARK, 0.5)
	_fill(PackedVector2Array([Vector2(-9.2, -1.7), Vector2(-10.6, -2.0), Vector2(-11.4, 0.0), Vector2(-10.4, 1.9), Vector2(-9.0, 1.7)]), DARK.lightened(0.05))
	# тельце: сизое, брюшко светлее, зоб с переливом
	var body := PackedVector2Array([Vector2(-6.8, 0.6), Vector2(-5.2, -2.0), Vector2(-2.4, -3.5), Vector2(1.2, -3.7), Vector2(4.0, -3.0), Vector2(5.6, -1.4), Vector2(6.1, 0.6), Vector2(5.0, 2.4), Vector2(2.6, 3.4), Vector2(-1.0, 3.5), Vector2(-4.0, 2.6)])
	_poly(body, BODY, DARK, 0.8)
	_ellipse(Vector2(1.2, 1.8), 4.6, 1.5, BELLY)
	_ellipse(Vector2(4.2, -0.4), 2.1, 2.3, NECK_G.darkened(0.15))
	_ellipse(Vector2(4.4, -0.9), 1.5, 1.5, NECK_P)
	_ellipse(Vector2(4.0, -1.5), 0.9, 0.8, NECK_G.lightened(0.3))
	if fly:
		_wing(tip_y, WING, false)
	else:
		# сложенное крыло: перья, две тёмные «полоски», тёмные кончики
		_poly(PackedVector2Array([Vector2(2.6, -2.7), Vector2(-0.8, -3.2), Vector2(-5.4, -1.8), Vector2(-9.0, 1.1), Vector2(-5.4, 1.5), Vector2(-0.6, 1.7), Vector2(2.8, 0.5)]), WING, DARK, 0.6)
		draw_line(Vector2(0.6, -2.6), Vector2(0.4, 0.8), BAR, 0.8)
		draw_line(Vector2(-1.8, -2.5), Vector2(-2.2, 1.0), BAR, 0.8)
		draw_line(Vector2(-3.4, -1.0), Vector2(-8.2, 0.9), WING.lightened(0.18), 0.5)
		draw_line(Vector2(-3.0, 0.2), Vector2(-8.4, 1.1), WING.darkened(0.2), 0.5)
		_fill(PackedVector2Array([Vector2(-7.0, 0.5), Vector2(-9.2, 1.2), Vector2(-6.4, 1.5)]), DARK)
	# шея и голова с переливом
	var hx := 4.8
	var hy := -3.0 + (3.8 if peck else 0.0)
	_poly(PackedVector2Array([Vector2(2.2, -3.6), Vector2(4.4, hy + 0.6), Vector2(6.2, hy + 1.8), Vector2(5.6, -0.6), Vector2(3.4, 0.2)]), BODY.darkened(0.08), Color(0, 0, 0, 0), 0.0)
	draw_line(Vector2(3.0, -2.2), Vector2(hx + 0.2, hy + 1.4), NECK_G, 2.4)
	draw_line(Vector2(3.8, -1.4), Vector2(hx + 0.6, hy + 1.6), NECK_P, 1.5)
	draw_line(Vector2(3.4, -2.6), Vector2(hx - 0.4, hy + 1.0), NECK_G.lightened(0.25), 0.7)
	draw_circle(Vector2(hx, hy), 2.15, BODY.lightened(0.1))
	draw_arc(Vector2(hx, hy), 2.15, 0.0, TAU, 14, DARK, 0.6)
	var bx := hx + 1.9
	_fill(PackedVector2Array([Vector2(bx - 0.2, hy - 0.8), Vector2(bx + 2.8, hy + 0.3), Vector2(bx - 0.1, hy + 1.0)]), BEAK)
	draw_circle(Vector2(bx + 0.3, hy - 0.5), 0.55, Color("#f1ece4"))
	draw_circle(Vector2(hx + 0.7, hy - 0.5), 0.8, Color("#ee8f2e"))
	draw_circle(Vector2(hx + 0.8, hy - 0.5), 0.38, Color("#16110d"))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Крыло в полёте: перекрытые перья, тёмные кончики; far — дальнее.
func _wing(tip_y: float, col: Color, far: bool) -> void:
	var sx := -0.6 if far else 0.0
	var pts := PackedVector2Array([Vector2(2.2 + sx, -2.4), Vector2(-3.8 + sx, -1.8), Vector2(-7.0 + sx, tip_y + 2.4), Vector2(-4.6 + sx, tip_y + 0.4), Vector2(-2.4 + sx, tip_y - 0.6), Vector2(0.4 + sx, tip_y + 0.4), Vector2(1.4 + sx, tip_y * 0.6)])
	_poly(pts, col, DARK, 0.6)
	for k in 4:
		var f := float(k) / 3.0
		var a := Vector2(1.2 + sx - f * 4.2, -2.0 + f * 0.4)
		var b := Vector2(0.8 + sx - f * 7.0, tip_y * (0.55 + 0.15 * f) + 1.5)
		draw_line(a, b, col.darkened(0.25), 0.5)
	_fill(PackedVector2Array([Vector2(-7.0 + sx, tip_y + 2.4), Vector2(-4.6 + sx, tip_y + 0.4), Vector2(-2.4 + sx, tip_y - 0.6), Vector2(-3.6 + sx, tip_y + 1.6)]), DARK)


## Заливка веером из центра: для наших «звёздчатых» контуров не бывает «triangulation failed».
func _fill(pts: PackedVector2Array, col: Color) -> void:
	var c := Vector2.ZERO
	for q in pts:
		c += q
	c /= float(pts.size())
	var cols := PackedColorArray([col, col, col])
	for k in pts.size():
		draw_primitive(PackedVector2Array([c, pts[k], pts[(k + 1) % pts.size()]]), cols, PackedVector2Array())


func _poly(pts: PackedVector2Array, col: Color, line: Color, wdt: float) -> void:
	_fill(pts, col)
	if wdt > 0.0:
		var cl := pts.duplicate()
		cl.append(pts[0])
		draw_polyline(cl, line, wdt)


func _mouse(m: Dictionary) -> void:
	var pos: Vector2 = m["pos"]
	var at := pos * T
	var dir := float(m.get("dir", 1))
	var run := str(m["st"]) == "run"
	draw_set_transform(at, 0.0, Vector2(dir, 1))
	_ellipse(Vector2(0, 0.6), 4.0, 1.4, Color(0, 0, 0, 0.2))
	var wig := sin(_t * 30.0) * (1.2 if run else 0.3)
	draw_polyline(PackedVector2Array([Vector2(-3.6, -1.0), Vector2(-6.0, -1.6 + wig), Vector2(-8.4, -0.6 - wig)]), Color("#c79a92"), 0.9)
	_ellipse(Vector2(0, -1.8), 3.8, 2.2, Color("#8a8580"))
	draw_circle(Vector2(3.2, -2.2), 1.7, Color("#8a8580"))
	draw_circle(Vector2(2.4, -4.0), 1.1, Color("#d6a8a0"))
	draw_circle(Vector2(4.4, -2.6), 0.4, Color("#1a1a1a"))
	draw_circle(Vector2(4.9, -1.9), 0.4, Color("#e08a90"))
	_ellipse_line(Vector2(0, -1.8), 3.8, 2.2, Color("#4a4642"), 0.7)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _ellipse(c: Vector2, rx: float, ry: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for k in 16:
		var a := TAU * k / 16.0
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	draw_colored_polygon(pts, col)


func _ellipse_line(c: Vector2, rx: float, ry: float, col: Color, wdt: float) -> void:
	var pts := PackedVector2Array()
	for k in 17:
		var a := TAU * k / 16.0
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	draw_polyline(pts, col, wdt)


func _quad(a: Vector2, b: Vector2, c: Vector2, d: Vector2, col: Color) -> void:
	var cols := PackedColorArray([col, col, col])
	draw_primitive(PackedVector2Array([a, b, c]), cols, PackedVector2Array())
	draw_primitive(PackedVector2Array([a, c, d]), cols, PackedVector2Array())
