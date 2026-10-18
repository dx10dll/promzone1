class_name CityBackdrop
extends Node2D
## 1.21: промышленный город за краем карты — чтобы при отдалении не было пустого поля.
## 1.23: город понятнее и богаче. У зданий есть лицевая стена с окнами и воротами (вид «три четверти»,
## как у построек на участке), у многих — вывеска с названием. Сверху и по бокам — промзона:
## цеха, склады с рампами и фурами, заводоуправление, нефтебаза, котельные, подстанция, пункт приёма
## металлолома, гаражный кооператив. Снизу, за дорогой, — жилой квартал: пятиэтажки, дворы с деревьями
## и площадками, машины у подъездов, школа, сквер. Вдоль проездов — тротуары и фонари.
## Движение (поезд, машины, дым из труб, огни) — в CityLife, он рисуется каждый кадр.
## Всё рисуется векторно один раз; случайность своя (не sim.rng) — картинка всегда одинаковая.

const T := World.T
const M := 64                    ## на сколько клеток город тянется за край карты

var sim: Sim
var life: CityLife
var _key := ""
var _rng := RandomNumberGenerator.new()
var _font: Font
var chimneys: Array = []         ## [[Vector2 центр, радиус]] — для дыма в CityLife
var lanes: Array = []            ## [[Vector2 от, Vector2 до]] — проезды, по которым ездят машины

const C_GROUND := Color("#6c6a62")
const C_ASPH := Color("#4a4c4f")
const C_ASPH_L := Color("#56585b")
const C_WALK := Color("#7d7b74")
const C_KERB := Color("#8e8c84")
const C_SHADOW := Color(0, 0, 0, 0.28)
const C_WIN := Color("#3e5866")
const C_WIN_L := Color("#7fa3b4")

const NAMES := {
	"shop": ["Механический цех", "Литейный цех", "Цех №2", "Инструментальный цех", "Кузнечный цех", "Сборочный цех", "Цех металлоконструкций"],
	"store": ["Склад №3", "Склад готовой продукции", "Оптовая база", "Склад металла", "Логистический терминал"],
	"office": ["Заводоуправление", "Проектный институт", "Конструкторское бюро", "Учебный комбинат"],
	"tanks": ["Нефтебаза", "Склад ГСМ", "Водоочистные"],
	"boiler": ["Котельная", "ТЭЦ-2", "Котельная №4"],
	"yard": ["АТП-2", "Автобаза", "Стоянка фур"],
	"cont": ["Контейнерная площадка", "Терминал"],
	"garage": ["ГСК «Мотор»", "ГСК «Колесо»", "Гаражи"],
	"sub": ["Подстанция 110 кВ", "Подстанция"],
	"scrap": ["Приём металлолома", "Металлобаза"],
	"house": ["ул. Заводская", "ул. Строителей", "ул. Мира", "пр. Металлистов", "ул. Лесная", "ул. Рабочая"],
}


func _ready() -> void:
	life = CityLife.new()
	life.backdrop = self
	add_child(life)


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
	_font = UITheme.f_semi if UITheme.f_semi else ThemeDB.fallback_font
	chimneys.clear()
	lanes.clear()
	var w := sim.world
	var sw := w.sidewalk_row
	_rng.seed = 19790412
	# основа — асфальт проездов везде вокруг
	draw_rect(Rect2(-M * T, -M * T, (w.w + 2 * M) * T, (w.h + 2 * M) * T), C_ASPH)
	# кварталы: сверху и по бокам — промзона, снизу за дорогой — жилой квартал
	_region(Rect2i(-M, -M, w.w + 2 * M, M - 12), false)               # сверху, за железной дорогой
	_strip(Rect2i(-M, -8, w.w + 2 * M, 5))                            # полоса между рельсами и проездом
	_region(Rect2i(-M, -3, M - 3, sw + 3), false)                     # слева
	_region(Rect2i(w.w + 3, -3, M - 3, sw + 3), false)                # справа
	var below := sw + 5
	if below < w.h:
		draw_rect(Rect2(-M * T, below * T, M * T, (w.h - below) * T), C_GROUND)
		draw_rect(Rect2(w.w * T, below * T, M * T, (w.h - below) * T), C_GROUND)
	_region(Rect2i(-M, w.h + 2, w.w + 2 * M, M - 2), true)            # снизу — жилой квартал
	# железнодорожная ветка и ЛЭП вдоль неё
	_rail(-10)
	_power_line(-6)
	# бордюры и разметка проезда вокруг участка
	draw_rect(Rect2(-3 * T, -3 * T - 3, (w.w + 6) * T, 3), C_KERB)
	draw_rect(Rect2(-3 * T - 3, -3 * T, 3, (sw + 3) * T), C_KERB)
	draw_rect(Rect2((w.w + 3) * T, -3 * T, 3, (sw + 3) * T), C_KERB)
	for x in range(-2, w.w + 2, 2):
		draw_rect(Rect2(x * T + 6, -1.5 * T - 1.5, 20, 3), Color(0.85, 0.85, 0.8, 0.35))
	for y in range(-2, sw, 2):
		draw_rect(Rect2(-1.5 * T - 1.5, y * T + 6, 3, 20), Color(0.85, 0.85, 0.8, 0.3))
		draw_rect(Rect2((w.w + 1.5) * T - 1.5, y * T + 6, 3, 20), Color(0.85, 0.85, 0.8, 0.3))
	# по проезду вокруг участка ездят машины
	lanes.append([Vector2(-M * T, -1.2 * T), Vector2((w.w + M) * T, -1.2 * T)])
	lanes.append([Vector2((w.w + M) * T, -1.8 * T), Vector2(-M * T, -1.8 * T)])
	lanes.append([Vector2(-1.2 * T, -M * 0.5 * T), Vector2(-1.2 * T, sw * T)])
	lanes.append([Vector2((w.w + 1.8) * T, sw * T), Vector2((w.w + 1.8) * T, -M * 0.5 * T)])
	# притушить: ближе к участку — светлее, дальше — темнее (дымка)
	for k in 6:
		var g := 6 + k * 10
		var a := 0.05 + k * 0.03
		_frame(Rect2((-g) * T, (-g) * T, (w.w + 2 * g) * T, (w.h + 2 * g) * T), Rect2((-g - 10) * T, (-g - 10) * T, (w.w + 2 * g + 20) * T, (w.h + 2 * g + 20) * T), Color(0.05, 0.06, 0.08, a))
	_frame(Rect2(0, 0, w.w * T, w.h * T), Rect2((-4) * T, (-4) * T, (w.w + 8) * T, (w.h + 8) * T), Color(0.05, 0.06, 0.08, 0.08))
	if life:
		life.reset()


## Залить рамку между внутренним и внешним прямоугольником.
func _frame(inner: Rect2, outer: Rect2, col: Color) -> void:
	draw_rect(Rect2(outer.position, Vector2(outer.size.x, inner.position.y - outer.position.y)), col)
	draw_rect(Rect2(Vector2(outer.position.x, inner.end.y), Vector2(outer.size.x, outer.end.y - inner.end.y)), col)
	draw_rect(Rect2(Vector2(outer.position.x, inner.position.y), Vector2(inner.position.x - outer.position.x, inner.size.y)), col)
	draw_rect(Rect2(Vector2(inner.end.x, inner.position.y), Vector2(outer.end.x - inner.end.x, inner.size.y)), col)


## Нарезать область на кварталы с проездами в 2 клетки (разметка, машины).
func _region(r: Rect2i, homes: bool) -> void:
	if r.size.x < 4 or r.size.y < 4:
		return
	var y := r.position.y
	while y < r.end.y - 3:
		var bh := mini(_rng.randi_range(9, 14), r.end.y - y)
		var x := r.position.x
		while x < r.end.x - 3:
			var bw := mini(_rng.randi_range(10, 17), r.end.x - x)
			var b := Rect2i(x, y, bw, bh)
			if homes:
				_home_block(b)
			else:
				_block(b)
			# проезд справа от квартала: разметка
			var px := (x + bw + 1) * T
			if x + bw + 2 < r.end.x:
				for yy in range(y, y + bh, 2):
					draw_rect(Rect2(px - 1, yy * T + 8, 2, 14), Color(0.85, 0.85, 0.8, 0.22))
				if _rng.randf() < 0.35 and lanes.size() < 24:
					lanes.append([Vector2(px + 0.35 * T, y * T), Vector2(px + 0.35 * T, (y + bh) * T)])
			x += bw + 2
		# проезд под рядом кварталов
		var py := (y + bh + 1) * T
		if y + bh + 2 < r.end.y:
			for xx in range(r.position.x, r.end.x, 2):
				draw_rect(Rect2(xx * T + 8, py - 1, 14, 2), Color(0.85, 0.85, 0.8, 0.22))
			if _rng.randf() < 0.5 and lanes.size() < 24:
				lanes.append([Vector2(r.position.x * T, py + 0.35 * T), Vector2(r.end.x * T, py + 0.35 * T)])
		y += bh + 2


## Квартал: тротуар по краю, фонари на углах; возвращает прямоугольник квартала.
func _lot(b: Rect2i) -> Rect2:
	var r := Rect2(Vector2(b.position) * T, Vector2(b.size) * T)
	draw_rect(r, C_WALK)
	draw_rect(r.grow(-10), C_GROUND)
	draw_rect(r, C_KERB, false, 2.0)
	for c: Vector2 in [r.position + Vector2(5, 5), Vector2(r.end.x - 5, r.position.y + 5), Vector2(r.position.x + 5, r.end.y - 5), r.end - Vector2(5, 5)]:
		draw_circle(c + Vector2(2, 3), 3.0, C_SHADOW)
		draw_circle(c, 3.0, Color("#3b3f42"))
		draw_circle(c, 1.6, Color("#e8d9a0"))
	return r


func _block(b: Rect2i) -> void:
	var r := _lot(b)
	var inset := Rect2(r.position + Vector2(T, T), r.size - Vector2(2 * T, 2 * T))
	if inset.size.x < T * 3 or inset.size.y < T * 3:
		_trees(r.grow(-10), 3)
		return
	var kind := _rng.randi_range(0, 15)
	match kind:
		0, 1, 2:
			_saw_shop(inset)
		3, 4:
			_warehouse(inset)
		5:
			_office(inset)
		6:
			_tanks(inset)
		7:
			_boiler(inset)
		8:
			_truck_yard(inset)
		9:
			_containers(inset)
		10:
			_garages(inset)
		11:
			_substation(inset)
		12:
			_scrap(inset)
		13:
			_office(Rect2(inset.position, Vector2(inset.size.x * 0.56, inset.size.y)))
			_truck_yard(Rect2(inset.position + Vector2(inset.size.x * 0.62, 0), Vector2(inset.size.x * 0.38, inset.size.y)))
		14:
			_saw_shop(Rect2(inset.position, Vector2(inset.size.x, inset.size.y * 0.6)))
			_truck_yard(Rect2(inset.position + Vector2(0, inset.size.y * 0.68), Vector2(inset.size.x, inset.size.y * 0.32)))
		_:
			_trees(r.grow(-10), 8)


## Жилой квартал: пятиэтажки по краям двора, во дворе деревья, площадка, машины.
func _home_block(b: Rect2i) -> void:
	var r := _lot(b)
	var inset := Rect2(r.position + Vector2(T * 0.8, T * 0.8), r.size - Vector2(T * 1.6, T * 1.6))
	if inset.size.x < T * 4 or inset.size.y < T * 4:
		_trees(r.grow(-10), 3)
		return
	var k := _rng.randi_range(0, 9)
	if k == 0:
		_school(inset)
		return
	if k == 1:
		_trees(r.grow(-10), 10)
		_label(r.get_center(), "Сквер", 0.8)
		return
	draw_rect(inset, Color("#6a6f58"))
	var house_h := T * 2.2
	var top := Rect2(inset.position, Vector2(inset.size.x, house_h))
	_panel_house(top)
	var bot := Rect2(Vector2(inset.position.x, inset.end.y - house_h), Vector2(inset.size.x * (0.55 if k % 2 == 0 else 1.0), house_h))
	_panel_house(bot)
	var yard := Rect2(Vector2(inset.position.x, top.end.y + 8), Vector2(inset.size.x, bot.position.y - top.end.y - 16))
	if yard.size.y > T * 1.2:
		draw_rect(Rect2(yard.position.x, yard.get_center().y - 4, yard.size.x, 8), C_WALK)
		_trees(Rect2(yard.position, Vector2(yard.size.x * 0.5, yard.size.y)), 4)
		var pg := Rect2(yard.position + Vector2(yard.size.x * 0.58, 6), Vector2(minf(yard.size.x * 0.24, T * 2.5), yard.size.y - 12))
		draw_rect(pg, Color("#b39a6a"))
		draw_rect(pg, Color("#7a6a4a"), false, 1.5)
		draw_line(pg.position + Vector2(6, 6), pg.position + Vector2(pg.size.x - 6, 6), Color("#c8463a"), 2.0)
		draw_circle(pg.get_center(), minf(pg.size.x, pg.size.y) * 0.16, Color("#d9c27a"))
		var cx := pg.end.x + 10
		while cx + 14 < yard.end.x:
			if _rng.randf() < 0.7:
				_car(Vector2(cx, yard.position.y + 8), true)
			cx += 20
	if bot.size.x < inset.size.x:
		_trees(Rect2(bot.end.x + 8, bot.position.y, inset.end.x - bot.end.x - 8, bot.size.y), 3)
	if _rng.randf() < 0.6:
		_label(Vector2(top.get_center().x, top.position.y + 14), "%s, %d" % [_pick("house"), _rng.randi_range(2, 48)], 0.8)


## Пятиэтажка: кровля с выходами на крышу, лицевая стена с рядами окон и подъездами.
func _panel_house(r: Rect2) -> void:
	var base := [Color("#b9b2a4"), Color("#a9b3b5"), Color("#c2a88f"), Color("#b5b09c")][_rng.randi_range(0, 3)] as Color
	var face_h := r.size.y * 0.42
	var roof := Rect2(r.position, Vector2(r.size.x, r.size.y - face_h))
	draw_rect(Rect2(r.position + Vector2(6, 8), r.size), C_SHADOW)
	draw_rect(roof, Color("#6d6f70"))
	draw_rect(roof, Color("#4e5052"), false, 2.0)
	var n := maxi(1, int(r.size.x / (T * 2.4)))
	for i in n:
		var hx := r.position.x + r.size.x * (i + 0.5) / n
		draw_rect(Rect2(hx - 6, roof.position.y + 6, 12, 10), Color("#8a8c8d"))
	var face := Rect2(Vector2(r.position.x, roof.end.y), Vector2(r.size.x, face_h))
	draw_rect(face, base)
	draw_line(face.position, Vector2(face.end.x, face.position.y), base.darkened(0.35), 1.5)
	var rows := 2
	var cols := int(r.size.x / 11.0)
	for ry in rows:
		for cx in cols:
			var p := Vector2(face.position.x + 4 + cx * 11.0, face.position.y + 3 + ry * (face_h - 4) / rows)
			var lit := _rng.randf() < 0.12
			draw_rect(Rect2(p, Vector2(6, (face_h - 4) / rows - 4)), Color("#e9d68a") if lit else C_WIN)
	for i2 in n:
		var dx := r.position.x + r.size.x * (i2 + 0.5) / n
		draw_rect(Rect2(dx - 5, face.end.y - 7, 10, 7), Color("#5a4636"))


func _school(r: Rect2) -> void:
	draw_rect(r, Color("#6a6f58"))
	var body := Rect2(r.position, Vector2(r.size.x, r.size.y * 0.45))
	_building(body, Color("#c9b98f"), Color("#d8c9a2"), 0, "Школа №%d" % _rng.randi_range(3, 27))
	var field := Rect2(r.position + Vector2(r.size.x * 0.1, r.size.y * 0.55), Vector2(r.size.x * 0.8, r.size.y * 0.4))
	draw_rect(field, Color("#5f8a4a"))
	draw_rect(field.grow(-4), Color(1, 1, 1, 0.5), false, 1.5)
	draw_line(Vector2(field.get_center().x, field.position.y + 4), Vector2(field.get_center().x, field.end.y - 4), Color(1, 1, 1, 0.5), 1.5)
	draw_arc(field.get_center(), minf(field.size.y * 0.2, 20.0), 0, TAU, 24, Color(1, 1, 1, 0.5), 1.5)


## Здание «три четверти»: кровля сверху, снизу — лицевая стена (окна, ворота).
## gates: сколько ворот в лицевой стене. Возвращает прямоугольник кровли (для узора крыши).
func _building(r: Rect2, roof_col: Color, wall_col: Color, gates: int = 0, sign_text: String = "") -> Rect2:
	var face_h := clampf(r.size.y * 0.22, 14.0, 30.0)
	var roof := Rect2(r.position, Vector2(r.size.x, r.size.y - face_h))
	var face := Rect2(Vector2(r.position.x, roof.end.y), Vector2(r.size.x, face_h))
	draw_rect(Rect2(r.position + Vector2(8, 10), r.size), C_SHADOW)
	draw_rect(roof, roof_col)
	draw_rect(roof, roof_col.darkened(0.35), false, 2.0)
	draw_rect(face, wall_col)
	draw_line(face.position, Vector2(face.end.x, face.position.y), wall_col.darkened(0.45), 2.0)
	draw_line(Vector2(face.position.x, face.end.y), face.end, wall_col.darkened(0.5), 2.0)
	var wx := face.position.x + 6
	while wx + 10 < face.end.x - 4:
		draw_rect(Rect2(wx, face.position.y + 4, 9, face_h * 0.4), C_WIN if _rng.randf() < 0.85 else C_WIN_L)
		wx += 15
	for g in gates:
		var gx := face.position.x + face.size.x * (g + 0.5) / gates - 14
		var gr := Rect2(gx, face.position.y + face_h * 0.25, 28, face_h * 0.75)
		draw_rect(gr, Color("#9aa0a3"))
		for k in 4:
			draw_line(Vector2(gr.position.x + 2, gr.position.y + 3 + k * gr.size.y / 4.0), Vector2(gr.end.x - 2, gr.position.y + 3 + k * gr.size.y / 4.0), Color("#6f7578"), 1.0)
		draw_rect(Rect2(gx - 3, gr.position.y, 3, gr.size.y), Color("#d4b13a"))
		draw_rect(Rect2(gr.end.x, gr.position.y, 3, gr.size.y), Color("#d4b13a"))
	if sign_text != "":
		_label(Vector2(roof.get_center().x, roof.position.y + minf(roof.size.y * 0.5, 30.0)), sign_text, 1.0)
	return roof


## Вывеска на крыше: светлые буквы на тёмной табличке. k — масштаб.
func _label(c: Vector2, s: String, k: float) -> void:
	var px := int(round(22 * k))
	var sz := _font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, px)
	var r := Rect2(c - Vector2(sz.x * 0.5 + 6, sz.y * 0.5 + 2), sz + Vector2(12, 4))
	draw_rect(r, Color(0.1, 0.12, 0.14, 0.78))
	draw_string(_font, Vector2(r.position.x + 6, r.position.y + sz.y * 0.78 + 2), s, HORIZONTAL_ALIGNMENT_LEFT, -1, px, Color("#e6e2d6"))


func _pick(kind: String) -> String:
	var arr: Array = NAMES[kind]
	return str(arr[_rng.randi_range(0, arr.size() - 1)])


## Цех с пилообразной крышей: светлые скаты и тёмные полосы остекления, ворота в лицевой стене.
func _saw_shop(r: Rect2) -> void:
	var base := Color("#8b8e8f") if _rng.randf() < 0.6 else Color("#93897a")
	var roof := _building(r, base, Color("#a39c8e") if _rng.randf() < 0.5 else Color("#9a6a52"), 1 + int(r.size.x > 8 * T), "")
	var step := 22.0
	var n := int(roof.size.x / step)
	for i in n:
		var o := i * step
		draw_rect(Rect2(roof.position.x + o + 2, roof.position.y + 2, step * 0.62, roof.size.y - 4), base.lightened(0.12))
		draw_rect(Rect2(roof.position.x + o + step * 0.62 + 2, roof.position.y + 2, step * 0.3, roof.size.y - 4), Color("#5f7884"))
	if _rng.randf() < 0.5:
		_chimney(roof.position + Vector2(roof.size.x - 18, 18), 9.0)
	if _rng.randf() < 0.7:
		_label(Vector2(roof.get_center().x, roof.position.y + minf(roof.size.y * 0.5, 30.0)), _pick("shop"), 1.0)


## Склад: кровля из профлиста с вентиляторами, рампа с воротами и фуры у рампы.
func _warehouse(r: Rect2) -> void:
	var base := [Color("#6f7477"), Color("#7b6f63"), Color("#66707a")][_rng.randi_range(0, 2)] as Color
	var body := Rect2(r.position, Vector2(r.size.x, r.size.y * 0.72))
	var roof := _building(body, base, Color("#b5b2a8"), clampi(int(r.size.x / (T * 3)), 1, 4), "")
	for i in int(roof.size.y / 7.0):
		draw_line(Vector2(roof.position.x + 3, roof.position.y + 3 + i * 7), Vector2(roof.end.x - 3, roof.position.y + 3 + i * 7), base.lightened(0.08), 1.0)
	for k in _rng.randi_range(2, 4):
		var p := roof.position + Vector2(_rng.randf_range(12, roof.size.x - 24), _rng.randf_range(8, maxf(9.0, roof.size.y - 20)))
		draw_rect(Rect2(p, Vector2(12, 12)), Color("#a3a7a8"))
		draw_circle(p + Vector2(6, 6), 4.0, Color("#4b4f52"))
	draw_rect(Rect2(Vector2(r.position.x, body.end.y), Vector2(r.size.x, 8)), Color("#8d8a82"))
	var tx := r.position.x + 10
	while tx + 22 < r.end.x and _rng.randf() < 0.8:
		_truck(Vector2(tx, body.end.y + 10), true)
		tx += 34
	if _rng.randf() < 0.75:
		_label(Vector2(roof.get_center().x, roof.position.y + minf(roof.size.y * 0.5, 28.0)), _pick("store"), 0.95)


## Административный корпус (кирпич, ряды окон, крыльцо, флаг).
func _office(r: Rect2) -> void:
	var base := Color("#8a5a46") if _rng.randf() < 0.7 else Color("#9a7a5a")
	var roof := _building(r, Color("#6a6c6e"), base, 0, "")
	draw_rect(roof.grow(-5), Color("#75777a"))
	draw_rect(Rect2(r.get_center().x - 12, r.end.y - 4, 24, 8), Color("#9a9890"))
	draw_rect(Rect2(r.get_center().x - 16, roof.end.y + 2, 32, 4), Color("#4a4c4f"))
	if _rng.randf() < 0.5:
		var fp := Vector2(r.position.x + 14, r.end.y + 8)
		draw_line(fp, fp - Vector2(0, 26), Color("#c8c8c0"), 2.0)
		draw_rect(Rect2(fp - Vector2(0, 26), Vector2(14, 9)), Color("#b23a2e"))
	_label(Vector2(roof.get_center().x, roof.position.y + minf(roof.size.y * 0.5, 30.0)), _pick("office"), 0.95)


## Ёмкости: круглые баки с лесенками на бетонной площадке, трубы между ними.
func _tanks(r: Rect2) -> void:
	draw_rect(r, Color("#7c7a72"))
	draw_rect(r, Color("#9a9a92"), false, 2.0)
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
		draw_arc(c, rad * 0.98, -0.6, 0.2, 8, Color("#5b5f62"), 3.0)
		if i > 0:
			draw_line(prev + Vector2(rad, 0), c - Vector2(rad, 0), Color("#5d6a73"), 4.0)
		prev = c
	_label(Vector2(r.get_center().x, r.end.y - 14), _pick("tanks"), 0.85)


## Котельная: корпус и высокая труба с красно-белыми кольцами (дым — в CityLife), кучи угля.
func _boiler(r: Rect2) -> void:
	var body := Rect2(r.position, Vector2(r.size.x * 0.62, r.size.y))
	var roof := _building(body, Color("#7d7f80"), Color("#a4795e"), 1, "")
	draw_rect(roof.grow(-6), Color("#8a8c8d"))
	var c := Vector2(r.position.x + r.size.x * 0.82, r.get_center().y)
	_chimney(c, minf(r.size.x * 0.12, 22.0))
	draw_circle(Vector2(c.x, r.end.y - 18), 14.0, Color("#2e2f31"))
	draw_circle(Vector2(c.x - 10, r.end.y - 12), 10.0, Color("#3a3b3d"))
	_label(Vector2(roof.get_center().x, roof.position.y + minf(roof.size.y * 0.5, 28.0)), _pick("boiler"), 0.9)


func _chimney(c: Vector2, rad: float) -> void:
	draw_circle(c + Vector2(14, 18), rad, C_SHADOW)
	draw_circle(c, rad, Color("#e6e1d6"))
	draw_arc(c, rad * 0.78, 0, TAU, 32, Color("#b8463a"), rad * 0.22)
	draw_arc(c, rad * 0.4, 0, TAU, 24, Color("#b8463a"), rad * 0.16)
	draw_circle(c, rad * 0.22, Color("#2e2f31"))
	chimneys.append([c, rad])


## Автобаза: фуры в ряд, будка диспетчера.
func _truck_yard(r: Rect2) -> void:
	draw_rect(r, C_ASPH_L)
	for x in range(int(r.position.x) + 4, int(r.end.x) - 4, 30):
		draw_line(Vector2(x, r.position.y + 4), Vector2(x, r.position.y + 60), Color(0.9, 0.9, 0.85, 0.35), 1.0)
	var x2 := r.position.x + 8
	while x2 + 22 < r.end.x:
		if _rng.randf() < 0.7:
			_truck(Vector2(x2, r.position.y + 6), false)
		x2 += 30
	draw_rect(Rect2(r.end.x - 26, r.end.y - 22, 20, 16), Color("#c8c2b0"))
	draw_rect(Rect2(r.end.x - 22, r.end.y - 18, 8, 6), C_WIN)
	if r.size.x > 5 * T and _rng.randf() < 0.7:
		_label(Vector2(r.get_center().x, r.end.y - 14), _pick("yard"), 0.8)


## Фура сверху: полуприцеп и тягач. to_dock — задом к рампе (кабина снизу).
func _truck(p: Vector2, to_dock: bool) -> void:
	var cols := [Color("#d8d6d0"), Color("#3f6a8a"), Color("#a8462f"), Color("#5f7d4a"), Color("#c49a3a")]
	var col: Color = cols[_rng.randi_range(0, cols.size() - 1)]
	var trailer := Rect2(p, Vector2(20, 44))
	var cab := Rect2(p + Vector2(1, 47), Vector2(18, 14))
	if not to_dock:
		cab = Rect2(p + Vector2(1, 0), Vector2(18, 14))
		trailer.position.y += 17
	draw_rect(Rect2(p + Vector2(3, 4), Vector2(20, 61)), C_SHADOW)
	draw_rect(trailer, col)
	draw_rect(trailer, col.darkened(0.3), false, 1.0)
	draw_rect(cab, Color("#c23b2f") if _rng.randf() < 0.5 else Color("#2f5f8f"))
	draw_rect(Rect2(cab.position.x + 2, cab.position.y + (9 if to_dock else 2), 14, 3), C_WIN_L)


## Легковушка сверху.
func _car(p: Vector2, vertical: bool) -> void:
	var cols := [Color("#c8c8c0"), Color("#8a2f2a"), Color("#2f4f6f"), Color("#d6c27a"), Color("#4f6f4a"), Color("#e8e6e0"), Color("#222426")]
	var col: Color = cols[_rng.randi_range(0, cols.size() - 1)]
	var sz := Vector2(11, 20) if vertical else Vector2(20, 11)
	draw_rect(Rect2(p + Vector2(2, 3), sz), C_SHADOW)
	draw_rect(Rect2(p, sz), col)
	if vertical:
		draw_rect(Rect2(p + Vector2(1.5, 4), Vector2(8, 4)), C_WIN)
		draw_rect(Rect2(p + Vector2(1.5, 13), Vector2(8, 3)), C_WIN)
	else:
		draw_rect(Rect2(p + Vector2(4, 1.5), Vector2(4, 8)), C_WIN)
		draw_rect(Rect2(p + Vector2(13, 1.5), Vector2(3, 8)), C_WIN)


## Контейнерная площадка: штабели контейнеров и козловой кран.
func _containers(r: Rect2) -> void:
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
	draw_line(Vector2(r.position.x + 2, r.position.y + r.size.y * 0.4), Vector2(r.end.x - 2, r.position.y + r.size.y * 0.4), Color("#d4b13a"), 5.0)
	draw_rect(Rect2(r.get_center().x - 8, r.position.y + r.size.y * 0.4 - 7, 16, 14), Color("#b8943a"))
	_label(Vector2(r.get_center().x, r.end.y - 14), _pick("cont"), 0.8)


## Гаражный кооператив: ряды боксов с разноцветными воротами.
func _garages(r: Rect2) -> void:
	draw_rect(r, C_ASPH_L)
	var doors := [Color("#6f7f5a"), Color("#8a4a3a"), Color("#4a6a8a"), Color("#9a9a90"), Color("#a8823a")]
	var rowh := 34.0
	var y := r.position.y + 4
	while y + rowh < r.end.y - 4:
		var row := Rect2(r.position.x + 4, y, r.size.x - 8, rowh - 10)
		draw_rect(Rect2(row.position + Vector2(4, 5), row.size), C_SHADOW)
		draw_rect(Rect2(row.position, Vector2(row.size.x, row.size.y - 8)), Color("#5f6163"))
		var x := row.position.x
		while x + 16 < row.end.x:
			draw_rect(Rect2(x, row.end.y - 8, 15, 8), doors[_rng.randi_range(0, doors.size() - 1)])
			draw_line(Vector2(x + 16, row.position.y), Vector2(x + 16, row.end.y), Color("#4a4c4e"), 1.0)
			x += 17
		y += rowh + 10
	_label(Vector2(r.get_center().x, r.end.y - 12), _pick("garage"), 0.8)


## Подстанция: трансформаторы и порталы за сетчатым забором.
func _substation(r: Rect2) -> void:
	draw_rect(r, Color("#7a776d"))
	for x in range(int(r.position.x) + 6, int(r.end.x) - 6, 6):
		draw_line(Vector2(x, r.position.y + 6), Vector2(x, r.end.y - 6), Color(0.6, 0.6, 0.55, 0.25), 1.0)
	draw_rect(r.grow(-4), Color("#a6a8a0"), false, 2.0)
	var n := clampi(int(r.size.x / (T * 2.2)), 2, 5)
	for i in n:
		var c := Vector2(r.position.x + r.size.x * (i + 0.5) / n, r.get_center().y)
		draw_rect(Rect2(c - Vector2(14, 12) + Vector2(4, 5), Vector2(28, 24)), C_SHADOW)
		draw_rect(Rect2(c - Vector2(14, 12), Vector2(28, 24)), Color("#5f7a6a"))
		for k in 3:
			draw_line(c + Vector2(-10 + k * 10, -12), c + Vector2(-10 + k * 10, -26), Color("#c8c8c0"), 2.0)
		draw_line(c + Vector2(-16, -26), c + Vector2(16, -26), Color("#9a9c96"), 3.0)
	_label(Vector2(r.get_center().x, r.end.y - 14), _pick("sub"), 0.8)


## Пункт приёма металлолома: кучи лома, весовая.
func _scrap(r: Rect2) -> void:
	draw_rect(r, Color("#6a6258"))
	for k in 7:
		var p := r.position + Vector2(_rng.randf_range(20, r.size.x - 20), _rng.randf_range(20, r.size.y - 30))
		var rad := _rng.randf_range(12, 26)
		draw_circle(p + Vector2(4, 5), rad, C_SHADOW)
		draw_circle(p, rad, Color("#6e5444"))
		draw_circle(p + Vector2(-rad * 0.2, -rad * 0.2), rad * 0.6, Color("#85705e"))
		for j in 4:
			var a := _rng.randf() * TAU
			draw_line(p, p + Vector2(cos(a), sin(a)) * rad * 0.8, Color("#4e4a46"), 1.5)
	draw_rect(Rect2(r.position.x + 6, r.end.y - 22, 40, 14), Color("#8a8c8d"))
	_label(Vector2(r.get_center().x, r.end.y - 14), _pick("scrap"), 0.8)


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
	var px := rr.position.x
	while px < rr.end.x:
		draw_line(Vector2(px, rr.end.y - 8), Vector2(px, rr.end.y), Color("#7a7f82"), 1.5)
		px += 24


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


## ЛЭП вдоль железной дороги: опоры и провода.
func _power_line(row: int) -> void:
	var w := sim.world
	var y := row * T
	var x := -M * T + 40.0
	var prev := Vector2.ZERO
	while x < (w.w + M) * T:
		var p := Vector2(x, y)
		draw_rect(Rect2(p - Vector2(7, 7) + Vector2(10, 12), Vector2(14, 14)), C_SHADOW)
		draw_rect(Rect2(p - Vector2(7, 7), Vector2(14, 14)), Color("#8a8f92"), false, 2.0)
		draw_line(p - Vector2(7, 7), p + Vector2(7, 7), Color("#8a8f92"), 1.0)
		draw_line(p + Vector2(-7, 7), p + Vector2(7, -7), Color("#8a8f92"), 1.0)
		draw_line(p - Vector2(16, 0), p + Vector2(16, 0), Color("#9a9fa2"), 2.0)
		if prev != Vector2.ZERO:
			for o: float in [-14.0, 0.0, 14.0]:
				draw_line(prev + Vector2(0, o * 0.3 - 1), p + Vector2(0, o * 0.3 - 1), Color(0.15, 0.15, 0.15, 0.5), 1.0)
		prev = p
		x += 9 * T
