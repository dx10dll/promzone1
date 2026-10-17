class_name CityBackdrop
extends Node2D
## 1.21: промышленный город за краем карты — чтобы при отдалении не было пустого поля.
## Кварталы соседних заводов: цеха с пилообразной крышей, склады, кирпичные корпуса, ёмкости,
## котельные с трубами, стоянки фур и контейнеров, пустыри с деревьями; между ними — проезды,
## сверху — железнодорожная ветка. Всё рисуется векторно один раз (не зависит от зума) и чуть притушено,
## чтобы свой участок выделялся. Случайность своя (не sim.rng) — картинка всегда одинаковая.

const T := World.T
const M := 64                    ## на сколько клеток город тянется за край карты

var sim: Sim
var _key := ""
var _rng := RandomNumberGenerator.new()

const C_GROUND := Color("#6c6a62")
const C_ASPH := Color("#4a4c4f")
const C_ASPH_L := Color("#56585b")
const C_KERB := Color("#8e8c84")
const C_SHADOW := Color(0, 0, 0, 0.28)


func _process(_d: float) -> void:
	if sim == null:
		return
	var k := "%d:%d:%d" % [sim.world.w, sim.world.h, sim.world.sidewalk_row]
	if k != _key:
		_key = k
		queue_redraw()


func _draw() -> void:
	if sim == null:
		return
	var w := sim.world
	var sw := w.sidewalk_row
	_rng.seed = 19790412
	# основа — асфальт проездов везде вокруг
	draw_rect(Rect2(-M * T, -M * T, (w.w + 2 * M) * T, (w.h + 2 * M) * T), C_ASPH)
	# кварталы: сверху, слева и справа (до тротуара), снизу — за дорогой
	_region(Rect2i(-M, -M, w.w + 2 * M, M - 12))                      # сверху, за железной дорогой
	_strip(Rect2i(-M, -8, w.w + 2 * M, 5))                            # полоса между рельсами и проездом
	_region(Rect2i(-M, -3, M - 3, sw + 3))                            # слева
	_region(Rect2i(w.w + 3, -3, M - 3, sw + 3))                       # справа
	var below := sw + 5
	if below < w.h:
		draw_rect(Rect2(-M * T, below * T, M * T, (w.h - below) * T), C_GROUND)
		draw_rect(Rect2(w.w * T, below * T, M * T, (w.h - below) * T), C_GROUND)
	_region(Rect2i(-M, w.h + 2, w.w + 2 * M, M - 2))                  # снизу
	# железнодорожная ветка над заводом
	_rail(-10)
	# бордюры вдоль проезда у забора
	draw_rect(Rect2(-3 * T, -3 * T - 3, (w.w + 6) * T, 3), C_KERB)
	draw_rect(Rect2(-3 * T - 3, -3 * T, 3, (sw + 3) * T), C_KERB)
	draw_rect(Rect2((w.w + 3) * T, -3 * T, 3, (sw + 3) * T), C_KERB)
	# разметка проезда
	for x in range(-2, w.w + 2, 2):
		draw_rect(Rect2(x * T + 6, -1.5 * T - 1.5, 20, 3), Color(0.85, 0.85, 0.8, 0.35))
	# притушить: ближе к участку — светлее, дальше — темнее (дымка)
	for k in 6:
		var g := 4 + k * 10
		var a := 0.07 + k * 0.035
		_frame(Rect2((-g) * T, (-g) * T, (w.w + 2 * g) * T, (w.h + 2 * g) * T), Rect2((-g - 10) * T, (-g - 10) * T, (w.w + 2 * g + 20) * T, (w.h + 2 * g + 20) * T), Color(0.05, 0.06, 0.08, a))
	_frame(Rect2(0, 0, w.w * T, w.h * T), Rect2((-4) * T, (-4) * T, (w.w + 8) * T, (w.h + 8) * T), Color(0.05, 0.06, 0.08, 0.12))


## Залить рамку между внутренним и внешним прямоугольником.
func _frame(inner: Rect2, outer: Rect2, col: Color) -> void:
	draw_rect(Rect2(outer.position, Vector2(outer.size.x, inner.position.y - outer.position.y)), col)
	draw_rect(Rect2(Vector2(outer.position.x, inner.end.y), Vector2(outer.size.x, outer.end.y - inner.end.y)), col)
	draw_rect(Rect2(Vector2(outer.position.x, inner.position.y), Vector2(inner.position.x - outer.position.x, inner.size.y)), col)
	draw_rect(Rect2(Vector2(inner.end.x, inner.position.y), Vector2(outer.end.x - inner.end.x, inner.size.y)), col)


## Нарезать область на кварталы с проездами в 2 клетки.
func _region(r: Rect2i) -> void:
	if r.size.x < 4 or r.size.y < 4:
		return
	var y := r.position.y
	while y < r.end.y - 3:
		var bh := mini(_rng.randi_range(8, 14), r.end.y - y)
		var x := r.position.x
		while x < r.end.x - 3:
			var bw := mini(_rng.randi_range(9, 17), r.end.x - x)
			_block(Rect2i(x, y, bw, bh))
			x += bw + 2
		y += bh + 2


func _block(b: Rect2i) -> void:
	var r := Rect2(Vector2(b.position) * T, Vector2(b.size) * T)
	draw_rect(r, C_GROUND)
	draw_rect(r, C_KERB, false, 2.0)
	var kind := _rng.randi_range(0, 9)
	var inset := Rect2(r.position + Vector2(T, T), r.size - Vector2(2 * T, 2 * T))
	if inset.size.x < T * 3 or inset.size.y < T * 3:
		_trees(r, 3)
		return
	match kind:
		0, 1:
			_saw_shop(inset)
		2, 3:
			_warehouse(inset)
		4:
			_brick(inset)
		5:
			_tanks(inset)
		6:
			_boiler(inset)
		7:
			_yard(inset)
		8:
			_brick(Rect2(inset.position, Vector2(inset.size.x * 0.55, inset.size.y)))
			_yard(Rect2(inset.position + Vector2(inset.size.x * 0.6, 0), Vector2(inset.size.x * 0.4, inset.size.y)))
		_:
			_trees(r, 7)


func _shadowed(r: Rect2, col: Color) -> void:
	draw_rect(Rect2(r.position + Vector2(7, 9), r.size), C_SHADOW)
	draw_rect(r, col)
	draw_rect(r, col.darkened(0.35), false, 2.0)


## Цех с пилообразной крышей: чередуются светлые скаты и тёмные полосы остекления.
func _saw_shop(r: Rect2) -> void:
	var base := Color("#8b8e8f") if _rng.randf() < 0.6 else Color("#93897a")
	_shadowed(r, base)
	var step := 22.0
	var vert := r.size.y > r.size.x
	var n := int((r.size.y if vert else r.size.x) / step)
	for i in n:
		var o := i * step
		if vert:
			draw_rect(Rect2(r.position.x + 2, r.position.y + o + 2, r.size.x - 4, step * 0.62), base.lightened(0.12))
			draw_rect(Rect2(r.position.x + 2, r.position.y + o + step * 0.62 + 2, r.size.x - 4, step * 0.3), Color("#5f7884"))
		else:
			draw_rect(Rect2(r.position.x + o + 2, r.position.y + 2, step * 0.62, r.size.y - 4), base.lightened(0.12))
			draw_rect(Rect2(r.position.x + o + step * 0.62 + 2, r.position.y + 2, step * 0.3, r.size.y - 4), Color("#5f7884"))
	if _rng.randf() < 0.5:
		_chimney(r.position + Vector2(r.size.x - 18, 18), 9.0)


## Склад с плоской кровлей: рёбра профлиста, вентиляторы, люки.
func _warehouse(r: Rect2) -> void:
	var base := [Color("#6f7477"), Color("#7b6f63"), Color("#66707a")][_rng.randi_range(0, 2)] as Color
	_shadowed(r, base)
	var vert := r.size.y > r.size.x
	var gap := 7.0
	var n := int((r.size.x if vert else r.size.y) / gap)
	for i in n:
		var o := i * gap + 3
		if vert:
			draw_line(Vector2(r.position.x + o, r.position.y + 3), Vector2(r.position.x + o, r.end.y - 3), base.lightened(0.08), 1.0)
		else:
			draw_line(Vector2(r.position.x + 3, r.position.y + o), Vector2(r.end.x - 3, r.position.y + o), base.lightened(0.08), 1.0)
	for k in _rng.randi_range(2, 5):
		var p := r.position + Vector2(_rng.randf_range(12, r.size.x - 24), _rng.randf_range(12, r.size.y - 24))
		draw_rect(Rect2(p, Vector2(12, 12)), Color("#a3a7a8"))
		draw_circle(p + Vector2(6, 6), 4.0, Color("#4b4f52"))


## Кирпичный корпус с внутренним двориком и люками.
func _brick(r: Rect2) -> void:
	var base := Color("#8a5a46") if _rng.randf() < 0.7 else Color("#9a7a5a")
	_shadowed(r, base)
	draw_rect(r.grow(-5), base.lightened(0.07))
	if r.size.x > 5 * T and r.size.y > 5 * T and _rng.randf() < 0.5:
		var c := r.grow(-r.size.x * 0.3)
		draw_rect(c, C_GROUND)
		draw_rect(c, base.darkened(0.35), false, 2.0)
	for k in _rng.randi_range(2, 4):
		var p := r.position + Vector2(_rng.randf_range(10, r.size.x - 20), _rng.randf_range(10, r.size.y - 20))
		draw_rect(Rect2(p, Vector2(10, 7)), base.darkened(0.3))


## Ёмкости: круглые баки на бетонной площадке и трубы между ними.
func _tanks(r: Rect2) -> void:
	draw_rect(r, Color("#7c7a72"))
	var n := 2 if r.size.x < 6 * T else 3
	var rad := minf(r.size.y * 0.32, r.size.x / float(n) * 0.38)
	var cy := r.get_center().y
	var prev := Vector2.ZERO
	for i in n:
		var c := Vector2(r.position.x + r.size.x * (i + 0.5) / n, cy)
		draw_circle(c + Vector2(6, 8), rad, C_SHADOW)
		draw_circle(c, rad, Color("#c2c0b6"))
		draw_arc(c, rad, 0, TAU, 40, Color("#8c8a82"), 2.0)
		draw_arc(c, rad * 0.62, 0, TAU, 32, Color("#a9a79e"), 1.5)
		draw_circle(c, rad * 0.14, Color("#8c8a82"))
		if i > 0:
			draw_line(prev + Vector2(rad, 0), c - Vector2(rad, 0), Color("#5d6a73"), 4.0)
		prev = c


## Котельная: корпус и высокая труба с красно-белыми кольцами и дымом.
func _boiler(r: Rect2) -> void:
	var body := Rect2(r.position, Vector2(r.size.x * 0.62, r.size.y))
	_shadowed(body, Color("#7d7f80"))
	draw_rect(body.grow(-6), Color("#8a8c8d"))
	var c := Vector2(r.position.x + r.size.x * 0.82, r.get_center().y)
	_chimney(c, minf(r.size.x * 0.12, 22.0))


func _chimney(c: Vector2, rad: float) -> void:
	draw_circle(c + Vector2(14, 18), rad, C_SHADOW)
	draw_circle(c, rad, Color("#e6e1d6"))
	draw_arc(c, rad * 0.78, 0, TAU, 32, Color("#b8463a"), rad * 0.22)
	draw_arc(c, rad * 0.4, 0, TAU, 24, Color("#b8463a"), rad * 0.16)
	draw_circle(c, rad * 0.22, Color("#2e2f31"))
	# дым — полупрозрачные клубы по ветру
	for k in 4:
		var p := c + Vector2(rad * (1.2 + k * 1.3), -rad * (0.4 + k * 0.5))
		draw_circle(p, rad * (0.8 + k * 0.35), Color(0.85, 0.85, 0.85, 0.16 - k * 0.03))


## Стоянка: фуры, контейнеры, разметка.
func _yard(r: Rect2) -> void:
	draw_rect(r, C_ASPH_L)
	var cols := [Color("#3f6a8a"), Color("#a8462f"), Color("#5f7d4a"), Color("#c49a3a"), Color("#8b8f91")]
	var cw := 18.0
	var ch := 54.0
	var x := r.position.x + 6
	while x + cw < r.end.x - 4:
		var y := r.position.y + 6
		while y + ch < r.end.y - 4:
			if _rng.randf() < 0.75:
				var col: Color = cols[_rng.randi_range(0, cols.size() - 1)]
				draw_rect(Rect2(Vector2(x + 3, y + 4), Vector2(cw, ch)), C_SHADOW)
				draw_rect(Rect2(Vector2(x, y), Vector2(cw, ch)), col)
				for k in 5:
					draw_line(Vector2(x + 2, y + 6 + k * 10), Vector2(x + cw - 2, y + 6 + k * 10), col.darkened(0.25), 1.0)
			y += ch + 8
		x += cw + 8


## Узкая полоса: пустырь с кустами и забором соседей.
func _strip(r: Rect2i) -> void:
	var rr := Rect2(Vector2(r.position) * T, Vector2(r.size) * T)
	draw_rect(rr, Color("#615f55"))
	var x := rr.position.x
	while x < rr.end.x:
		var seg := _rng.randf_range(4, 12) * T
		if _rng.randf() < 0.55:
			_trees(Rect2(x, rr.position.y + 6, minf(seg, rr.end.x - x), rr.size.y - 12), int(seg / T / 3.0) + 1)
		x += seg
	draw_line(Vector2(rr.position.x, rr.end.y - 4), Vector2(rr.end.x, rr.end.y - 4), Color("#8a8f92"), 2.0)


## Пустырь с деревьями.
func _trees(r: Rect2, n: int) -> void:
	draw_rect(r.grow(-2), Color("#5f6a4a"))
	for k in n:
		var p := r.position + Vector2(_rng.randf_range(10, maxf(11.0, r.size.x - 10)), _rng.randf_range(10, maxf(11.0, r.size.y - 10)))
		var rad := _rng.randf_range(9, 17)
		draw_circle(p + Vector2(5, 6), rad, C_SHADOW)
		draw_circle(p, rad, Color("#4b5e3a"))
		draw_circle(p - Vector2(rad * 0.3, rad * 0.3), rad * 0.55, Color("#5c7146"))


## Железнодорожная ветка: щебень, шпалы, два рельса.
func _rail(row: int) -> void:
	var w := sim.world
	var y := row * T
	draw_rect(Rect2(-M * T, y - 6, (w.w + 2 * M) * T, T + 12), Color("#6e6a64"))
	var x := -M * T
	while x < (w.w + M) * T:
		draw_rect(Rect2(x, y, 6, T), Color("#5a4a3a"))
		x += 14.0
	draw_line(Vector2(-M * T, y + 8), Vector2((w.w + M) * T, y + 8), Color("#b9bcbe"), 2.5)
	draw_line(Vector2(-M * T, y + T - 8), Vector2((w.w + M) * T, y + T - 8), Color("#b9bcbe"), 2.5)
