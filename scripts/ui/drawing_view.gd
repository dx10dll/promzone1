class_name DrawingView
extends Control
## Рабочий чертёж детали к заказу — по мотивам ЕСКД (ГОСТ 2.104, 2.109, 2.307):
## лист А4 горизонтально, рамка с полем подшивки 20 мм, основная надпись, осевые линии,
## размеры со стрелками, разрезы со штриховкой 45°, шероховатость, технические требования.
## Размеры у каждого заказа свои (зависят от номера заказа), вид — по типу изделия.

const MM := 2.8                       ## пикселей на миллиметр листа
const PAPER := Color("#f7f4ea")
const INK := Color("#1f2a36")
const THIN := Color(0.12, 0.17, 0.22, 0.85)
const AXIS := Color("#9a3a2a")

var product := ""
var order_id := 0
var qty := 1
var client := ""
var sim: Sim
var rng := RandomNumberGenerator.new()
var font: Font


func setup(s: Sim, o: Dictionary) -> void:
	sim = s
	product = str(o.get("product", "pin"))
	order_id = int(o.get("id", 1))
	qty = int(o.get("qty", 1))
	client = str(o.get("client", ""))
	custom_minimum_size = Vector2(297.0 * MM, 210.0 * MM)
	font = UITheme.f_reg if UITheme.f_reg else ThemeDB.fallback_font
	queue_redraw()


func _r(a: float, b: float) -> float:
	return rng.randf_range(a, b)


func _ri(a: int, b: int) -> int:
	return rng.randi_range(a, b)


## Мм листа -> пиксели.
func P(x: float, y: float) -> Vector2:
	return Vector2(x * MM, y * MM)


# ================================================================ примитивы

func _line(a: Vector2, b: Vector2, w: float = 1.6, col: Color = INK) -> void:
	draw_line(a, b, col, w, true)


func _axis(a: Vector2, b: Vector2) -> void:
	# штрихпунктирная осевая
	var d := b - a
	var ln := d.length()
	if ln < 1.0:
		return
	var u := d / ln
	var t := 0.0
	while t < ln:
		var seg := minf(18.0, ln - t)
		draw_line(a + u * t, a + u * (t + seg), AXIS, 0.9, true)
		t += seg + 3.0
		if t < ln:
			draw_line(a + u * t, a + u * minf(t + 2.0, ln), AXIS, 0.9, true)
		t += 5.0


func _text(p: Vector2, s: String, size: int = 11, col: Color = INK, center: bool = false, rot: float = 0.0) -> void:
	var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var o := Vector2(-w * 0.5, 0) if center else Vector2.ZERO
	draw_set_transform(p, rot, Vector2.ONE)
	draw_string(font, o, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _arrow(tip: Vector2, dir: Vector2) -> void:
	var u := dir.normalized()
	var n := Vector2(-u.y, u.x)
	draw_colored_polygon(PackedVector2Array([tip, tip - u * 7.0 + n * 1.8, tip - u * 7.0 - n * 1.8]), INK)


## Горизонтальный размер между x1 и x2 (выносные линии от y_from до y_dim).
func _dim_h(x1: float, x2: float, y_from: float, y_dim: float, txt: String) -> void:
	var s := signf(y_dim - y_from)
	_line(Vector2(x1, y_from + s * 2.0), Vector2(x1, y_dim + s * 4.0), 0.8, THIN)
	_line(Vector2(x2, y_from + s * 2.0), Vector2(x2, y_dim + s * 4.0), 0.8, THIN)
	_line(Vector2(x1, y_dim), Vector2(x2, y_dim), 0.8, THIN)
	_arrow(Vector2(x1, y_dim), Vector2(-1, 0))
	_arrow(Vector2(x2, y_dim), Vector2(1, 0))
	_text(Vector2((x1 + x2) * 0.5, y_dim - 3.0), txt, 11, INK, true)


## Вертикальный размер между y1 и y2 (выносные от x_from до x_dim), текст повёрнут.
func _dim_v(y1: float, y2: float, x_from: float, x_dim: float, txt: String) -> void:
	var s := signf(x_dim - x_from)
	_line(Vector2(x_from + s * 2.0, y1), Vector2(x_dim + s * 4.0, y1), 0.8, THIN)
	_line(Vector2(x_from + s * 2.0, y2), Vector2(x_dim + s * 4.0, y2), 0.8, THIN)
	_line(Vector2(x_dim, y1), Vector2(x_dim, y2), 0.8, THIN)
	_arrow(Vector2(x_dim, y1), Vector2(0, -1))
	_arrow(Vector2(x_dim, y2), Vector2(0, 1))
	_text(Vector2(x_dim - 3.0, (y1 + y2) * 0.5), txt, 11, INK, true, -PI * 0.5)


## Штриховка разреза под 45° внутри прямоугольника.
func _hatch(r: Rect2, step: float = 6.0) -> void:
	var k := -r.size.y
	while k < r.size.x:
		var a := Vector2(r.position.x + k, r.end.y)
		var b := Vector2(r.position.x + k + r.size.y, r.position.y)
		# обрезать по прямоугольнику
		if a.x < r.position.x:
			a = Vector2(r.position.x, r.end.y - (r.position.x - a.x))
		if b.x > r.end.x:
			b = Vector2(r.end.x, r.position.y + (b.x - r.end.x))
		_line(a, b, 0.7, THIN)
		k += step


## Знак шероховатости (галочка с полкой и значением).
func _rough(p: Vector2, ra: String) -> void:
	_line(p, p + Vector2(-5, -8), 1.0)
	_line(p, p + Vector2(10, -16), 1.0)
	_line(p + Vector2(10, -16), p + Vector2(26, -16), 1.0)
	_text(p + Vector2(10, -19), ra, 9)


# ================================================================ лист

func _draw() -> void:
	rng.seed = hash(product) ^ (order_id * 7919)
	draw_rect(Rect2(Vector2.ZERO, size), PAPER)
	# рамка: поле подшивки 20 мм слева, 5 мм с остальных сторон
	var fr := Rect2(P(20, 5), P(272, 200))
	draw_rect(fr, INK, false, 2.0)
	_title_block()
	var area := Rect2(P(28, 20), P(255, 100))
	match _kind():
		"shaft":
			_draw_shaft(area)
		"bushing":
			_draw_bushing(area)
		"fitting":
			_draw_fitting(area)
		"flange":
			_draw_flange(area, false)
		"gear":
			_draw_flange(area, true)
		"plate":
			_draw_plate(area)
		"housing":
			_draw_housing(area)
		"weld":
			_draw_weld(area)
		_:
			_draw_assembly(area)
	_tech_req()


func _kind() -> String:
	match product:
		"pin", "shaft", "spline_shaft", "axle", "stud":
			return "shaft"
		"bushing":
			return "bushing"
		"fitting", "bolt", "nut":
			return "fitting"
		"flange":
			return "flange"
		"gear", "node12k":
			return "gear"
		"bracket", "disc":
			return "plate"
		"housing":
			return "housing"
		"frame", "beam", "truss", "harrow":
			return "weld"
	return "assembly"


func designation() -> String:
	var base := 715000 + absi(hash(product)) % 999
	return "ПРЗ.%06d.%03d" % [base, order_id % 1000]


func _material_line() -> String:
	match str(Defs.products.get(product, {}).get("material", "")):
		"bar45":
			return "Круг 40 ГОСТ 2590-2006 / 45 ГОСТ 1050-2013"
		"hex27":
			return "Шестигранник 27 ГОСТ 2879-2006 / 35 ГОСТ 1050-2013"
		"bar40x":
			return "Круг 60 ГОСТ 2590-2006 / 40Х ГОСТ 4543-2016"
		"plate8":
			return "Лист Б-ПН-8 ГОСТ 19903-2015 / Ст3сп ГОСТ 14637-89"
		"forging":
			return "Поковка гр. IV ГОСТ 8479-70 / 45 ГОСТ 1050-2013"
		"profile40":
			return "Труба 40×40×3 ГОСТ 30245-2003 / С245 ГОСТ 27772-2015"
	return ""


func _who(prof: String, fallback: String) -> String:
	if sim:
		for w in sim.workers:
			if w.prof == prof:
				return w.last
	return fallback


func _title_block() -> void:
	# основная надпись 185×55 мм в правом нижнем углу (форма 1, упрощённо)
	var o := P(292 - 185, 205 - 55)
	var W := 185.0
	var H := 55.0
	var q := func(x: float, y: float) -> Vector2: return o + P(x, y)
	draw_rect(Rect2(o, P(W, H)), INK, false, 2.0)
	# левая часть: подписи
	for y in [5, 10, 15, 20, 25, 30, 35, 40, 45, 50]:
		_line(q.call(0, y), q.call(65, y), 1.0 if y != 25 else 1.6)
	for x in [7, 17, 40, 55, 65]:
		_line(q.call(x, 0), q.call(x, H), 1.0 if x != 65 else 2.0)
	var hdr := ["Изм.", "Лист", "№ докум.", "Подп.", "Дата"]
	var xs := [0.6, 7.6, 17.6, 40.6, 55.6]
	for i in hdr.size():
		_text(q.call(float(xs[i]), 23.8), str(hdr[i]), 8)
	var roles := ["Разраб.", "Пров.", "Т.контр.", "", "Н.контр.", "Утв."]
	var names := [_who("technologist", "Петров"), _who("qc", "Савина"), _who("foreman", "Кузнецов"), "", _who("qc", "Орлова"), _who("chief", "Директор")]
	for j in roles.size():
		_text(q.call(0.6, 28.8 + j * 5.0), str(roles[j]), 7)
		_text(q.call(17.6, 28.8 + j * 5.0), str(names[j]), 8)
	var day := sim.day() if sim else 1
	for j2 in [0, 1, 5]:
		_text(q.call(55.8, 28.8 + j2 * 5.0), "%02d.%02d" % [(day % 14) + 1, 9 + int(day / 14) % 4], 7)
	# обозначение и наименование
	_line(q.call(65, 15), q.call(W, 15), 2.0)
	_line(q.call(65, 40), q.call(W, 40), 2.0)
	_line(q.call(135, 15), q.call(135, H), 2.0)
	_text(q.call(125, 10), designation(), 16, INK, true)
	var nm := str(Defs.products.get(product, {}).get("name", product))
	_text(q.call(100, 28), nm, 16 if nm.length() <= 16 else 12, INK, true)
	if _kind() == "assembly":
		_text(q.call(100, 35), "Сборочный чертёж", 11, INK, true)
	var mat := _material_line()
	if mat != "":
		var parts := mat.split(" / ")
		_text(q.call(100, 46), parts[0], 9, INK, true)
		if parts.size() > 1:
			_text(q.call(100, 51.5), parts[1], 9, INK, true)
	# литера, масса, масштаб
	for x2 in [150, 167]:
		_line(q.call(x2, 15), q.call(x2, 30), 1.0)
	_line(q.call(135, 20), q.call(W, 20), 1.0)
	_line(q.call(135, 30), q.call(W, 30), 1.6)
	_line(q.call(135, 35), q.call(W, 35), 1.0)
	_text(q.call(137, 19), "Лит.", 8)
	_text(q.call(153, 19), "Масса", 8)
	_text(q.call(169, 19), "Масштаб", 8)
	_text(q.call(142, 27), "О", 11, INK, true)
	_text(q.call(158, 27), "%.2f" % _r(0.2, 18.0), 10, INK, true)
	_text(q.call(176, 27), "1:%d" % [1, 2, 2, 4][_ri(0, 3)], 10, INK, true)
	_text(q.call(137, 34), "Лист 1", 8)
	_text(q.call(162, 34), "Листов 1", 8)
	_text(q.call(160, 47), Company.title(sim) if sim else "ООО «Прогресс»", 11, INK, true)
	# графа обозначения в перевёрнутом виде (вверху слева) — как на настоящих листах
	draw_rect(Rect2(P(20, 5), P(70, 14)), INK, false, 1.6)
	_text(P(55, 14), designation(), 11, INK, true)
	# заказ — карандашом на полях
	_text(P(26, 202), "Заказ № %d · %s · %d шт." % [order_id, client, qty], 9, Color(0.35, 0.38, 0.42))


func _tech_req() -> void:
	var lines: Array[String] = []
	match _kind():
		"weld", "assembly":
			lines = ["1. Сварные швы по ГОСТ 14771-76.", "2. Покрытие: эмаль ПФ-115 ГОСТ 6465-76, цвет по заказу.", "3. Неуказанные катеты швов — 4 мм."]
			if _kind() == "assembly":
				lines = ["1. Перед сборкой детали промыть и смазать.", "2. Узел испытать на стенде, утечки не допускаются.", "3. Остальные технические требования по ТУ заказчика."]
		_:
			lines = ["1. *Размеры для справок.", "2. Неуказанные предельные отклонения: валов h14, отв. H14, ост. ±IT14/2.", "3. Острые кромки притупить R0,5."]
			if product in ["spline_shaft", "gear", "axle", "node12k"]:
				lines.append("4. Закалка ТВЧ, HRC 45...50.")
	# технические требования — над основной надписью (ГОСТ 2.316)
	var y := 150.0 - 5.5 * lines.size() - 2.0
	for l in lines:
		_text(P(110, y), l, 10)
		y += 5.5
	if _kind() != "weld" and _kind() != "assembly":
		_rough(P(270, 24), "Ra 6,3 (√)")


# ================================================================ виды

func _draw_shaft(a: Rect2) -> void:
	var steps := _ri(3, 5) if product != "pin" else 2
	var total := _r(160.0, 230.0) if product != "pin" else _r(70.0, 110.0)
	var k := minf(MM * 1.3, a.size.x * 0.8 / total)
	var cy := a.position.y + a.size.y * 0.42
	var x := a.position.x + (a.size.x - total * k) * 0.5
	var lens: Array[float] = []
	var dias: Array[float] = []
	var left := total
	for i in steps:
		var l := left / float(steps - i) * _r(0.7, 1.3) if i < steps - 1 else left
		lens.append(l)
		left -= l
		var d := _r(20.0, 30.0) + (12.0 if i == int(steps / 2) else 0.0) + (8.0 if product == "axle" else 0.0)
		dias.append(snappedf(d, 2.0))
	var x0 := x
	_axis(Vector2(x0 - 12.0, cy), Vector2(x0 + total * k + 12.0, cy))
	var xx := x0
	for i2 in steps:
		var hw := dias[i2] * k * 0.5
		var w := lens[i2] * k
		draw_rect(Rect2(xx, cy - hw, w, hw * 2.0), INK, false, 1.8)
		# фаски на торцах
		if i2 == 0:
			_line(Vector2(xx, cy - hw + 3), Vector2(xx + 3, cy - hw), 1.2)
			_line(Vector2(xx, cy + hw - 3), Vector2(xx + 3, cy + hw), 1.2)
		if i2 == steps - 1:
			_line(Vector2(xx + w, cy - hw + 3), Vector2(xx + w - 3, cy - hw), 1.2)
			_line(Vector2(xx + w, cy + hw - 3), Vector2(xx + w - 3, cy + hw), 1.2)
		# диаметр сверху
		var dtxt := "Ø%d" % int(dias[i2]) + (" h7" if i2 == int(steps / 2) else "")
		_text(Vector2(xx + w * 0.5, cy - hw - 6.0), dtxt, 11, INK, true)
		xx += w
	# шпоночный паз или шлицы на средней ступени
	var mid := int(steps / 2)
	var xm := x0
	for j in mid:
		xm += lens[j] * k
	if product == "spline_shaft":
		var hwm := dias[mid] * k * 0.5
		for s in 6:
			_line(Vector2(xm + 6 + s * 5, cy - hwm), Vector2(xm + 6 + s * 5, cy + hwm), 0.6, THIN)
		_text(Vector2(xm + lens[mid] * k * 0.5, cy - hwm - 22.0), "D-8×%d×%d ГОСТ 1139-80" % [int(dias[mid]) - 4, int(dias[mid])], 10, INK, true)
	elif product != "pin":
		var hwm2 := dias[mid] * k * 0.5
		var kw := lens[mid] * k * 0.5
		draw_rect(Rect2(xm + lens[mid] * k * 0.25, cy - 3.5, kw, 7.0), INK, false, 1.2)
		_line(Vector2(xm + lens[mid] * k * 0.5, cy), Vector2(xm + lens[mid] * k * 0.5 + 40.0, cy - hwm2 - 30.0), 0.8, THIN)
		_text(Vector2(xm + lens[mid] * k * 0.5 + 42.0, cy - hwm2 - 32.0), "Паз 8P9", 10)
	# длины снизу
	var yd := cy + 62.0
	xx = x0
	for i3 in steps:
		_dim_h(xx, xx + lens[i3] * k, cy + dias[i3] * k * 0.5, yd, str(int(lens[i3])))
		xx += lens[i3] * k
	_dim_h(x0, x0 + total * k, cy + 10.0, yd + 22.0, "%d*" % int(total))
	_text(Vector2(x0 - 70.0, cy + 4.0), "2 фаски 1×45°", 10)
	_rough(Vector2(x0 + lens[0] * k * 0.5, cy - dias[0] * k * 0.5 - 18.0), "Ra 1,6")


func _draw_bushing(a: Rect2) -> void:
	var k := MM * 1.5
	var D := snappedf(_r(36.0, 40.0), 1.0)
	var d := snappedf(_r(18.0, 26.0), 1.0)
	var L := snappedf(_r(30.0, 55.0), 1.0)
	var c := a.get_center() + Vector2(-60, -6)
	var r := Rect2(c.x - L * k * 0.5, c.y - D * k * 0.5, L * k, D * k)
	# разрез: верх и низ — металл (заштрихован), середина — отверстие
	var wall := (D - d) * 0.5 * k
	var top := Rect2(r.position, Vector2(r.size.x, wall))
	var bot := Rect2(Vector2(r.position.x, r.end.y - wall), Vector2(r.size.x, wall))
	_hatch(top)
	_hatch(bot)
	draw_rect(r, INK, false, 1.8)
	_line(Vector2(r.position.x, top.end.y), Vector2(r.end.x, top.end.y), 1.6)
	_line(Vector2(r.position.x, bot.position.y), Vector2(r.end.x, bot.position.y), 1.6)
	_axis(Vector2(r.position.x - 12, c.y), Vector2(r.end.x + 12, c.y))
	_dim_v(r.position.y, r.end.y, r.position.x, r.position.x - 30.0, "Ø%d" % int(D))
	_dim_v(top.end.y, bot.position.y, r.end.x, r.end.x + 24.0, "Ø%d H7" % int(d))
	_dim_h(r.position.x, r.end.x, r.end.y, r.end.y + 26.0, str(int(L)))
	_text(Vector2(r.get_center().x, r.position.y - 26.0), "А–А", 13, INK, true)
	# вид слева: кольцо
	var vc := Vector2(r.end.x + 120.0, c.y)
	draw_arc(vc, D * k * 0.5, 0.0, TAU, 64, INK, 1.8, true)
	draw_arc(vc, d * k * 0.5, 0.0, TAU, 48, INK, 1.8, true)
	_axis(vc - Vector2(D * k * 0.6, 0), vc + Vector2(D * k * 0.6, 0))
	_axis(vc - Vector2(0, D * k * 0.6), vc + Vector2(0, D * k * 0.6))
	_rough(Vector2(r.get_center().x, top.end.y + 2), "Ra 0,8")


func _draw_fitting(a: Rect2) -> void:
	var k := MM * 2.0
	var c := a.get_center() + Vector2(-40, 0)
	var S := 27.0
	var L := snappedf(_r(40.0, 55.0), 1.0)
	var hexl := snappedf(_r(12.0, 16.0), 1.0)
	var M: int = [16, 18, 20][_ri(0, 2)]
	var x0 := c.x - L * k * 0.5
	_axis(Vector2(x0 - 12, c.y), Vector2(x0 + L * k + 12, c.y))
	# резьбовая часть слева, шестигранник, хвостовик
	var tl := (L - hexl) * 0.55 * k
	draw_rect(Rect2(x0, c.y - M * k * 0.5, tl, M * k), INK, false, 1.8)
	_line(Vector2(x0, c.y - M * k * 0.42), Vector2(x0 + tl, c.y - M * k * 0.42), 0.8, THIN)
	_line(Vector2(x0, c.y + M * k * 0.42), Vector2(x0 + tl, c.y + M * k * 0.42), 0.8, THIN)
	var hx := x0 + tl
	draw_rect(Rect2(hx, c.y - S * k * 0.5, hexl * k, S * k), INK, false, 1.8)
	_line(Vector2(hx, c.y - S * k * 0.25), Vector2(hx + hexl * k, c.y - S * k * 0.25), 1.2)
	_line(Vector2(hx, c.y + S * k * 0.25), Vector2(hx + hexl * k, c.y + S * k * 0.25), 1.2)
	var rx := hx + hexl * k
	var rl := L * k - tl - hexl * k
	draw_rect(Rect2(rx, c.y - 7.0 * k, rl, 14.0 * k), INK, false, 1.8)
	# сквозное отверстие (скрытые линии)
	for yy in [-4.0, 4.0]:
		var xh := x0
		while xh < x0 + L * k:
			_line(Vector2(xh, c.y + yy * k), Vector2(minf(xh + 6.0, x0 + L * k), c.y + yy * k), 0.8, THIN)
			xh += 10.0
	_text(Vector2(x0 + tl * 0.5, c.y - M * k * 0.5 - 8.0), "M%d×1,5-6g" % M, 11, INK, true)
	_dim_h(hx, hx + hexl * k, c.y + S * k * 0.5, c.y + S * k * 0.5 + 24.0, str(int(hexl)))
	_dim_h(x0, x0 + L * k, c.y + S * k * 0.5, c.y + S * k * 0.5 + 46.0, str(int(L)))
	_dim_v(c.y - S * k * 0.5, c.y + S * k * 0.5, hx + hexl * k, rx + rl + 30.0, "S%d" % int(S))


func _draw_flange(a: Rect2, gear: bool) -> void:
	var D := snappedf(_r(110.0, 160.0), 5.0)
	var k := minf(MM * 0.9, a.size.y * 0.78 / D)
	var d := snappedf(D * _r(0.3, 0.45), 1.0)
	var B := snappedf(_r(16.0, 30.0), 1.0)
	var c := Vector2(a.position.x + a.size.x * 0.32, a.get_center().y)
	# вид спереди
	var R := D * k * 0.5
	if gear:
		var z := _ri(24, 40)
		var pts := PackedVector2Array()
		for i in z * 4:
			var ang := TAU * i / float(z * 4)
			var rr := R if i % 4 < 2 else R - 7.0
			pts.append(c + Vector2(cos(ang), sin(ang)) * rr)
		pts.append(pts[0])
		draw_polyline(pts, INK, 1.4, true)
		draw_arc(c, R - 3.5, 0.0, TAU, 96, AXIS, 0.8, true)
		_text(c + Vector2(0, R + 22.0), "m = %d,%d; z = %d" % [_ri(2, 4), [0, 5][_ri(0, 1)], z], 11, INK, true)
	else:
		draw_arc(c, R, 0.0, TAU, 96, INK, 1.8, true)
		var holes: int = [4, 6, 8][_ri(0, 2)]
		var pr := R * 0.75
		draw_arc(c, pr, 0.0, TAU, 96, AXIS, 0.8, true)
		for h in holes:
			var ang2: float = TAU * h / float(holes)
			draw_arc(c + Vector2(cos(ang2), sin(ang2)) * pr, R * 0.09, 0.0, TAU, 20, INK, 1.4, true)
		_text(c + Vector2(0, R + 22.0), "%d отв. Ø%d равном. на Ø%d" % [holes, int(D * 0.09 * 2), int(D * 0.75)], 11, INK, true)
	draw_arc(c, d * k * 0.5, 0.0, TAU, 64, INK, 1.8, true)
	_axis(c - Vector2(R + 10, 0), c + Vector2(R + 10, 0))
	_axis(c - Vector2(0, R + 10), c + Vector2(0, R + 10))
	# разрез сбоку
	var sx := c.x + R + 70.0
	var r1 := Rect2(sx, c.y - R, B * k, R - d * k * 0.5)
	var r2 := Rect2(sx, c.y + d * k * 0.5, B * k, R - d * k * 0.5)
	_hatch(r1)
	_hatch(r2)
	draw_rect(Rect2(sx, c.y - R, B * k, R * 2.0), INK, false, 1.8)
	_line(Vector2(sx, c.y - d * k * 0.5), Vector2(sx + B * k, c.y - d * k * 0.5), 1.6)
	_line(Vector2(sx, c.y + d * k * 0.5), Vector2(sx + B * k, c.y + d * k * 0.5), 1.6)
	_axis(Vector2(sx - 10, c.y), Vector2(sx + B * k + 10, c.y))
	_dim_h(sx, sx + B * k, c.y + R, c.y + R + 24.0, str(int(B)))
	_dim_v(c.y - R, c.y + R, sx + B * k, sx + B * k + 34.0, "Ø%d" % int(D))
	_dim_v(c.y - d * k * 0.5, c.y + d * k * 0.5, sx, sx - 22.0, "Ø%d H7" % int(d))
	_text(Vector2(sx + B * k * 0.5, c.y - R - 12.0), "А–А", 13, INK, true)


func _draw_plate(a: Rect2) -> void:
	var k := MM * 0.85
	var W := snappedf(_r(140.0, 200.0), 5.0)
	var H := snappedf(_r(80.0, 120.0), 5.0)
	var o := Vector2(a.position.x + 30.0, a.position.y + 26.0)
	if product == "disc":
		var c := o + Vector2(H * k * 0.6, H * k * 0.6)
		var R := H * k * 0.6
		draw_arc(c, R, 0.0, TAU, 96, INK, 1.8, true)
		var notches := _ri(8, 12)
		for i in notches:
			var ang := TAU * i / float(notches)
			draw_arc(c + Vector2(cos(ang), sin(ang)) * R, 7.0, ang + PI * 0.6, ang + PI * 1.4, 10, INK, 1.4, true)
		draw_rect(Rect2(c - Vector2(8, 8), Vector2(16, 16)), INK, false, 1.6)
		_axis(c - Vector2(R + 10, 0), c + Vector2(R + 10, 0))
		_axis(c - Vector2(0, R + 10), c + Vector2(0, R + 10))
		_dim_h(c.x - R, c.x + R, c.y + R, c.y + R + 26.0, "Ø%d" % int(H * 1.2))
		_text(c + Vector2(R + 40.0, -10), "□%d (под ось)" % _ri(30, 40), 11)
		_text(c + Vector2(R + 40.0, 10), "%d вырезов R%d" % [notches, _ri(15, 25)], 11)
		return
	# кронштейн: Г-образная пластина с отверстиями
	var r := Rect2(o, Vector2(W * k, H * k))
	var cut := Vector2(W * k * 0.55, H * k * 0.45)
	var pts := PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), Vector2(r.end.x, r.position.y + cut.y),
		Vector2(r.position.x + cut.x, r.position.y + cut.y), Vector2(r.position.x + cut.x, r.end.y), Vector2(r.position.x, r.end.y), r.position])
	draw_polyline(pts, INK, 1.8, true)
	var holes := [Vector2(0.18, 0.2), Vector2(0.8, 0.2), Vector2(0.18, 0.75)]
	var hd: int = [9, 11, 13][_ri(0, 2)]
	for hpos: Vector2 in holes:
		var hc := r.position + Vector2(hpos.x * r.size.x, hpos.y * r.size.y)
		draw_arc(hc, hd * k * 0.5, 0.0, TAU, 24, INK, 1.4, true)
		_axis(hc - Vector2(10, 0), hc + Vector2(10, 0))
		_axis(hc - Vector2(0, 10), hc + Vector2(0, 10))
	_text(r.position + Vector2(r.size.x * 0.18 + 10, r.size.y * 0.2 - 10), "3 отв. Ø%d" % hd, 11)
	_dim_h(r.position.x, r.end.x, r.position.y, r.position.y - 22.0, str(int(W)))
	_dim_v(r.position.y, r.end.y, r.position.x, r.position.x - 24.0, str(int(H)))
	_dim_h(r.position.x, r.position.x + cut.x, r.end.y, r.end.y + 24.0, str(int(W * 0.55)))
	_text(Vector2(r.end.x + 20.0, r.position.y + 20.0), "s = 8", 12)


func _draw_housing(a: Rect2) -> void:
	var W := snappedf(_r(150.0, 190.0), 5.0)
	var H := snappedf(_r(100.0, 130.0), 5.0)
	var k := minf(MM * 0.85, a.size.y * 0.7 / H)
	var bore := snappedf(_r(52.0, 72.0), 1.0)
	var o := Vector2(a.position.x + 40.0, a.position.y + 20.0)
	var r := Rect2(o, Vector2(W * k, H * k))
	var bc := r.get_center()
	# разрез по оси расточки: стенки заштрихованы
	_hatch(Rect2(r.position, Vector2(r.size.x, r.size.y * 0.5 - bore * k * 0.5)))
	_hatch(Rect2(Vector2(r.position.x, bc.y + bore * k * 0.5), Vector2(r.size.x, r.size.y * 0.5 - bore * k * 0.5)))
	draw_rect(r, INK, false, 1.8)
	draw_rect(Rect2(r.position.x, bc.y - bore * k * 0.5, r.size.x, bore * k), PAPER)
	_line(Vector2(r.position.x, bc.y - bore * k * 0.5), Vector2(r.end.x, bc.y - bore * k * 0.5), 1.6)
	_line(Vector2(r.position.x, bc.y + bore * k * 0.5), Vector2(r.end.x, bc.y + bore * k * 0.5), 1.6)
	_axis(Vector2(r.position.x - 12, bc.y), Vector2(r.end.x + 12, bc.y))
	# лапы с отверстиями
	draw_rect(Rect2(r.position.x - 18.0, r.end.y - 14.0, r.size.x + 36.0, 14.0), INK, false, 1.6)
	for fx in [r.position.x - 9.0, r.end.x + 9.0]:
		_axis(Vector2(fx, r.end.y - 20.0), Vector2(fx, r.end.y + 6.0))
	_dim_v(bc.y - bore * k * 0.5, bc.y + bore * k * 0.5, r.end.x, r.end.x + 46.0, "Ø%d H7" % int(bore))
	_dim_h(r.position.x - 18.0, r.end.x + 18.0, r.end.y, r.end.y + 26.0, str(int(W + 40)))
	_dim_v(r.position.y, r.end.y, r.position.x - 18.0, r.position.x - 40.0, str(int(H)))
	_text(Vector2(bc.x, r.position.y - 14.0), "Б–Б", 13, INK, true)
	_rough(Vector2(bc.x + 30.0, bc.y - bore * k * 0.5 + 2.0), "Ra 1,6")


func _draw_weld(a: Rect2) -> void:
	var k := MM * 0.6
	var L := snappedf(_r(1200.0, 3000.0), 50.0)
	var H := snappedf(_r(300.0, 800.0), 50.0)
	var sc := minf(a.size.x * 0.8 / (L * 0.1), a.size.y * 0.7 / (H * 0.1)) * 0.1
	var o := a.position + Vector2(40.0, 30.0)
	var w := L * sc
	var h := H * sc
	var t := 4.0
	draw_rect(Rect2(o, Vector2(w, t)), INK, false, 1.6)
	draw_rect(Rect2(o + Vector2(0, h - t), Vector2(w, t)), INK, false, 1.6)
	match product:
		"truss":
			var n := _ri(4, 7)
			for i in n + 1:
				var x := o.x + w * i / float(n)
				_line(Vector2(x, o.y + t), Vector2(x, o.y + h - t), 1.4)
				if i < n:
					var x2 := o.x + w * (i + 1) / float(n)
					if i % 2 == 0:
						_line(Vector2(x, o.y + h - t), Vector2(x2, o.y + t), 1.4)
					else:
						_line(Vector2(x, o.y + t), Vector2(x2, o.y + h - t), 1.4)
		"beam":
			draw_rect(Rect2(o + Vector2(0, t), Vector2(w, h - t * 2.0)), INK, false, 1.2)
			for i2 in _ri(3, 6):
				var x3 := o.x + w * (i2 + 1) / 7.0
				_line(Vector2(x3, o.y + t), Vector2(x3, o.y + h - t), 1.0)
		_:
			for xx in [o.x, o.x + w - t]:
				draw_rect(Rect2(xx, o.y, t, h), INK, false, 1.6)
			var n2 := _ri(1, 3)
			for i3 in n2:
				var x4 := o.x + w * (i3 + 1) / float(n2 + 1)
				draw_rect(Rect2(x4 - t * 0.5, o.y, t, h), INK, false, 1.2)
	# знак сварного шва с полкой
	var p := o + Vector2(w * 0.3, h)
	_line(p, p + Vector2(18, 26), 1.0)
	_line(p + Vector2(18, 26), p + Vector2(110, 26), 1.0)
	_text(p + Vector2(22, 23), "ГОСТ 14771-76-Т1-△4", 10)
	_dim_h(o.x, o.x + w, o.y + h, o.y + h + 46.0, str(int(L)))
	_dim_v(o.y, o.y + h, o.x + w, o.x + w + 24.0, str(int(H)))
	_text(o + Vector2(w * 0.5, -10.0), "Профиль □40×3", 11, INK, true)


func _draw_assembly(a: Rect2) -> void:
	# сборочный чертёж: контур узла, позиции на полках-выносках и спецификация
	var c := Vector2(a.position.x + a.size.x * 0.3, a.get_center().y)
	var W := 220.0
	var H := 150.0
	var body := Rect2(c - Vector2(W, H) * 0.5, Vector2(W, H))
	draw_rect(body, INK, false, 1.8)
	draw_rect(body.grow(-14.0), INK, false, 1.0)
	_axis(Vector2(body.position.x - 20, c.y), Vector2(body.end.x + 40, c.y))
	draw_rect(Rect2(body.end.x, c.y - 10.0, 46.0, 20.0), INK, false, 1.6)
	draw_arc(c, 34.0, 0.0, TAU, 48, INK, 1.4, true)
	var comps := Defs.components(product)
	var i := 1
	var spec: Array = []
	for cid in comps.keys():
		var ang := -0.9 + i * 0.55
		var p := c + Vector2(cos(ang) * W * 0.4, sin(ang) * H * 0.4)
		var q := p + Vector2(60.0 + i * 8.0, -40.0 + i * 6.0)
		draw_circle(p, 2.2, INK)
		_line(p, q, 0.9)
		_line(q, q + Vector2(22, 0), 0.9)
		_text(q + Vector2(6, -3), str(i), 12)
		spec.append([i, str(Defs.products.get(cid, {}).get("name", cid)), int(comps[cid])])
		i += 1
	# спецификация справа
	var sx := a.position.x + a.size.x * 0.66
	var sy := a.position.y + 10.0
	draw_rect(Rect2(sx, sy, 230.0, 18.0 * (spec.size() + 1)), INK, false, 1.4)
	_text(Vector2(sx + 6, sy + 13), "Поз.", 10)
	_text(Vector2(sx + 44, sy + 13), "Наименование", 10)
	_text(Vector2(sx + 196, sy + 13), "Кол.", 10)
	for j in spec.size():
		var yy := sy + 18.0 * (j + 1)
		_line(Vector2(sx, yy), Vector2(sx + 230.0, yy), 0.8)
		var row: Array = spec[j]
		_text(Vector2(sx + 10, yy + 13), str(row[0]), 10)
		_text(Vector2(sx + 44, yy + 13), str(row[1]), 10)
		_text(Vector2(sx + 200, yy + 13), str(row[2]), 10)
	_line(Vector2(sx + 36, sy), Vector2(sx + 36, sy + 18.0 * (spec.size() + 1)), 0.8)
	_line(Vector2(sx + 190, sy), Vector2(sx + 190, sy + 18.0 * (spec.size() + 1)), 0.8)
	_dim_h(body.position.x, body.end.x + 46.0, body.end.y, body.end.y + 28.0, "%d*" % int(snappedf(_r(280.0, 520.0), 10.0)))
