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
	# лапки
	if alt < 1.0:
		draw_line(Vector2(-0.6, -2.0), Vector2(-1.2, 0.2), Color("#d0584a"), 1.0)
		draw_line(Vector2(1.2, -2.0), Vector2(1.6, 0.2), Color("#d0584a"), 1.0)
	# хвост, тельце, крыло
	var by := -5.2 - bob
	draw_colored_polygon(PackedVector2Array([Vector2(-4.6, by - 0.6), Vector2(-9.2, by + 1.0), Vector2(-8.8, by - 1.6), Vector2(-4.2, by - 2.2)]), DARK.lightened(0.15))
	draw_set_transform(at + Vector2(0, -alt) + Vector2(0, by) * Vector2(1, 1), 0.0, Vector2(dir, 1))
	_ellipse(Vector2.ZERO, 5.4, 3.4, BODY)
	_ellipse(Vector2(0.4, 1.2), 4.4, 2.0, BODY.lightened(0.12))
	if st == "fly":
		var flap := sin(_t * 22.0 + i) * 0.5 + 0.5
		var tip_y := -9.0 + flap * 12.0
		# 1.38.2: крыло — двумя треугольниками: четырёхугольник в середине взмаха выворачивался («бантиком»),
		# и движок на каждом кадре писал в журнал «triangulation failed»
		_quad(Vector2(-2.6, -1.0), Vector2(2.4, -1.4), Vector2(-1.0, tip_y), Vector2(-5.0, tip_y + 2.0), WING)
		_quad(Vector2(-1.6, -0.6), Vector2(3.0, -1.0), Vector2(1.4, tip_y * 0.7 + 1.0), Vector2(-2.6, tip_y * 0.7 + 2.0), WING.darkened(0.15))
	else:
		_ellipse(Vector2(-0.8, -0.4), 3.6, 2.2, WING)
		draw_line(Vector2(-3.2, 0.2), Vector2(1.4, -0.4), DARK, 0.9)
		draw_line(Vector2(-3.0, 1.2), Vector2(1.0, 0.8), DARK, 0.9)
	# голова и шея
	var hx := 4.6
	var hy := -2.6 + (3.4 if peck else 0.0)
	draw_line(Vector2(3.0, -1.0), Vector2(hx, hy + 1.0), NECK_G, 2.6)
	draw_line(Vector2(3.4, -0.2), Vector2(hx - 0.2, hy + 1.6), NECK_P, 1.4)
	draw_circle(Vector2(hx, hy), 2.0, DARK.lightened(0.25))
	draw_colored_polygon(PackedVector2Array([Vector2(hx + 1.6, hy - 0.4), Vector2(hx + 3.4, hy + 0.3), Vector2(hx + 1.6, hy + 0.7)]), Color("#e8dccb"))
	draw_circle(Vector2(hx + 0.6, hy - 0.6), 0.55, Color("#f0a030"))
	_ellipse_line(Vector2.ZERO, 5.4, 3.4, DARK, 0.8)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


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
