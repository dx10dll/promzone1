class_name CityBackdrop
extends Node2D
## 1.21: город за краем карты — чтобы при отдалении не было пустого поля.
## 1.23: у зданий лицевая стена с окнами и воротами (вид «три четверти»), вывески, промзона, жилой квартал.
## 1.30 «Тамбов за забором»: город не случайный, а сжатый Тамбов. Завод стоит как бы в Северной промзоне:
## перед ним — ул. Московская (на востоке мост через Цну, дальше Рассказовское шоссе и «Тамбовский волк»),
## слева от участка на север уходит Моршанское шоссе к трубам ТЭЦ, за ним — ул. Мичуринская с телебашней,
## справа — пр. Энергетиков, Цна и лес на правом берегу; на юге — центр: Т‑34 на углу Советской,
## Студенецкая набережная, Коммунальная, собор, пл. Ленина и драмтеатр, Интернациональная к вокзалу,
## Казанский монастырь с колокольней, набережная Цны, усадьба Асеевых. На перекрёстках — синие таблички.
## Геометрия примерная (сжата раз в пять, стороны света сохранены). Реальные предприятия — под вымышленными
## названиями. Движение (поезд, машины, дым, огни) — в CityLife. Всё рисуется один раз; случайность своя.

const T := World.T
const M := 80                    ## на сколько клеток город тянется за край карты
const MICH := -22                ## ул. Мичуринская: столбцы MICH..MICH+3 (к северу от главной дороги)
const RIV := 24                  ## р. Цна: от w.w + RIV, ширина RIV_W
const RIV_W := 8
const NAB := 16                  ## ул. Набережная (к югу от главной дороги): w.w + NAB .. +3

var sim: Sim
var life: CityLife
var _key := ""
var _rng := RandomNumberGenerator.new()
var _font: Font
var chimneys: Array = []         ## [[Vector2 центр, радиус]] — для дыма в CityLife
var lanes: Array = []            ## [[Vector2 от, Vector2 до]] — проезды, по которым ездят машины
## 1.30: подъезды пятиэтажек (во двор): {door — низ двери, yard_y — дорожка двора, lx/rx — тротуары
## квартала слева/справа, top — верх квартала}. По ним ходят люди с завода и горожане (StreetFolk).
var doors: Array = []
var beacons: Array = []          ## 1.30: красные заградительные огни (телебашня) — мигают в CityLife
var _signs: Array = []           ## [Vector2, [строки]] — уличные таблички, рисуются поверх всего
var _tags: Array = []            ## [Vector2, текст, подпись, размер] — подписи достопримечательностей
var _rec := DrawChunks.new()
var _tiles: Node2D
var _tiles_n := 0
var _meshes: Array[ArrayMesh] = []   ## меши леса — держим, пока они нарисованы

const C_GROUND := Color("#6c6a62")
const C_ASPH := Color("#4a4c4f")
const C_ASPH_L := Color("#56585b")
const C_WALK := Color("#7d7b74")
const C_KERB := Color("#8e8c84")
const C_SHADOW := Color(0, 0, 0, 0.28)
const C_WIN := Color("#3e5866")
const C_WIN_L := Color("#7fa3b4")
const C_WATER := Color("#3b6a80")
const C_LAWN := Color("#5f6d4a")
const C_PAVE := Color("#9a958a")
const C_SIGN := Color("#1f4f9e")
const C_WHITE := Color("#f1eee6")
const C_RED := Color("#c8382e")
const C_GOLD := Color("#d9b347")
const SUN := Vector2(0.92, 0.39)  ## куда падают длинные тени высоких сооружений

const NAMES := {
	"shop": ["Механический цех", "Литейный цех", "Цех №2", "Инструментальный цех", "Кузнечный цех", "Сборочный цех", "Цех металлоконструкций"],
	"store": ["Склад №3", "Склад готовой продукции", "Оптовая база", "Склад металла", "Логистический терминал"],
	"office": ["Заводоуправление", "Проектный институт", "Конструкторское бюро", "Учебный комбинат"],
	"tanks": ["Нефтебаза", "Склад ГСМ", "Водоочистные"],
	"boiler": ["Котельная", "Котельная №4", "Котельная №2"],
	"yard": ["АТП-2", "Автобаза", "Стоянка фур"],
	"cont": ["Контейнерная площадка", "Терминал"],
	"garage": ["ГСК «Мотор»", "ГСК «Колесо»", "Гаражи"],
	"sub": ["Подстанция 110 кВ", "Подстанция"],
	"scrap": ["Металлобаза", "Вторчермет"],
}


func _ready() -> void:
	_tiles = Node2D.new()   # плитки рисунка — раньше life: машины и поезд поверх города
	add_child(_tiles)
	life = CityLife.new()
	life.backdrop = self
	add_child(life)
	if sim != null:
		_key = "%d:%d:%d" % [sim.world.w, sim.world.h, sim.world.sidewalk_row]
		_build()


func _process(_d: float) -> void:
	if sim == null:
		return
	var k := "%d:%d:%d" % [sim.world.w, sim.world.h, sim.world.sidewalk_row]
	if k != _key:
		_key = k
		_build()


## Мост ул. Московской через Цну: столбцы главной дороги над рекой (там нет газона и деревьев).
static func bridge_at(w: World, x: int) -> bool:
	return x >= w.w + RIV - 1 and x < w.w + RIV + RIV_W + 1


## Ул. Мичуринская выходит на главную дорогу — северный тротуар здесь прерывается.
static func avenue_at(_w: World, x: int) -> bool:
	return x >= MICH and x < MICH + 4


func _c(x: float, y: float) -> Vector2:
	return Vector2(x, y) * T


func _rc(x0: float, y0: float, x1: float, y1: float) -> Rect2:
	return Rect2(x0 * T, y0 * T, (x1 - x0) * T, (y1 - y0) * T)


## 1.40: рисунок собирается раз в плитки (DrawChunks): невидимые плитки Godot не отправляет на отрисовку.
func _build() -> void:
	if sim == null or _tiles == null:
		return
	for c in _tiles.get_children():
		c.queue_free()
	_rec.clear()
	_compose()
	_tiles_n = _rec.build(_tiles)


func _compose() -> void:
	_font = UITheme.f_semi if UITheme.f_semi else ThemeDB.fallback_font
	chimneys.clear()
	lanes.clear()
	doors.clear()
	beacons.clear()
	_meshes.clear()
	_signs.clear()
	_tags.clear()
	var w := sim.world
	var W := w.w
	var H := w.h
	var sw := w.sidewalk_row
	var rx := W + RIV
	_rng.seed = 19790412
	# основа — асфальт проездов везде вокруг
	_rec.draw_rect(Rect2(-M * T, -M * T, (W + 2 * M) * T, (H + 2 * M) * T), C_ASPH)

	# ---------------- север: Северная промзона за ж/д веткой
	_region(Rect2i(0, -M, W, M - 12), false)                                    # цеха над участком
	_region(Rect2i(MICH + 5, -M, -3 - MICH - 5, M - 48), false)
	_tec(Rect2(_c(MICH + 5, -44), _c(-3 - MICH - 5, 32)))                       # ТЭЦ у Моршанского шоссе
	_region(Rect2i(W + 3, -M, RIV - 7, M - 46), false)
	_chem(Rect2(_c(W + 3, -42), _c(RIV - 7, 30)))                               # химкомбинат у Цны
	_victory_park(_rc(-47, -42, MICH - 1, -13))
	_towers(_rc(-M, -M, -48, -13), "ул. Рылеева", 61)
	_towers(_rc(-47, -M, MICH - 1, -43), "б-р Энтузиастов", 12)
	# ---------------- середина: по сторонам участка
	_nine_storeys(_rc(MICH + 5, -2, -3, sw - 7))
	_mig_square(_rc(MICH + 5, sw - 6, -3, sw))
	_bus_station(_rc(-37, -2, MICH - 1, 7))
	_tv_yard(_rc(-37, 8, MICH - 1, sw))
	_private(_rc(-M, -2, -38, sw), 1)
	_region(Rect2i(W + 3, -3, RIV - 7, sw + 3), false)
	var below := sw + 5
	if below < H:
		_rec.draw_rect(Rect2(-M * T, below * T, M * T, (H - below) * T), C_GROUND)
		_rec.draw_rect(Rect2(W * T, below * T, M * T, (H - below) * T), C_GROUND)
	# ---------------- река, берега, лес за рекой
	_bank_north(_rc(W + RIV - 4, -M, rx, sw))
	_river(rx, -M, H + M)
	_forest(_rc(rx + RIV_W, -M, W + M, sw), true)
	_forest(_rc(rx + RIV_W, H + 1, W + M, H + M), false)
	# ---------------- юг: центр города
	_south(w)
	_bridge(w)
	_wolf(_c(rx + RIV_W + 9, H + 4.2))
	# ---------------- улицы: Мичуринская, Моршанское шоссе (через ж/д переезд к ТЭЦ)
	_strip(Rect2i(-M, -8, MICH + M, 5))
	_strip(Rect2i(MICH + 4, -8, -3 - MICH - 4, 5))
	_strip(Rect2i(0, -8, W + RIV - 4, 5))
	_avenue(_rc(MICH, -M, MICH + 4, sw), true)
	_avenue(_rc(-3, -M, 0, -3), false)
	_rail(-10, rx)
	_power_line(-6)
	# бордюры и разметка проезда вокруг участка (ул. Монтажников и боковые улицы)
	_rec.draw_rect(Rect2(-3 * T, -3 * T - 3, (W + 6) * T, 3), C_KERB)
	_rec.draw_rect(Rect2(-3 * T - 3, -3 * T, 3, (sw + 3) * T), C_KERB)
	_rec.draw_rect(Rect2((W + 3) * T, -3 * T, 3, (sw + 3) * T), C_KERB)
	for x in range(-2, W + 2, 2):
		_rec.draw_rect(Rect2(x * T + 6, -1.5 * T - 1.5, 20, 3), Color(0.85, 0.85, 0.8, 0.35))
	for y in range(-2, sw, 2):
		_rec.draw_rect(Rect2(-1.5 * T - 1.5, y * T + 6, 3, 20), Color(0.85, 0.85, 0.8, 0.3))
		_rec.draw_rect(Rect2((W + 1.5) * T - 1.5, y * T + 6, 3, 20), Color(0.85, 0.85, 0.8, 0.3))
	# по проезду вокруг участка ездят машины
	lanes.append([Vector2(-M * T, -1.2 * T), Vector2((W + M) * T, -1.2 * T)])
	lanes.append([Vector2((W + M) * T, -1.8 * T), Vector2(-M * T, -1.8 * T)])
	# 1.30: боковые улицы выходят на главную дорогу — машины поворачивают, а не пропадают у тротуара
	lanes.append([Vector2(-1.2 * T, -M * T), Vector2(-1.2 * T, (sw + 1.9) * T), Vector2(-M * T, (sw + 1.9) * T)])
	lanes.append([Vector2((W + M) * T, (sw + 1.9) * T), Vector2((W + 1.8) * T, (sw + 1.9) * T), Vector2((W + 1.8) * T, -M * T)])
	lanes.append([_c(MICH + 1.1, -M), _c(MICH + 1.1, sw + 1.9), _c(-M, sw + 1.9)])
	lanes.append([_c(-M, sw + 2.9), _c(MICH + 2.9, sw + 2.9), _c(MICH + 2.9, -M)])
	# высокие сооружения — поверх кварталов
	_tv_tower(_c(-29.5, sw - 5.5))
	# таблички улиц
	_sign(_c(-3.55, sw - 0.75), ["Моршанское ш.", "ул. Московская"])
	_sign(_c(-3.55, -3.6), ["ул. Монтажников", "Моршанское ш."])
	_sign(_c(MICH + 4.55, sw - 0.75), ["ул. Мичуринская", "ул. Московская"])
	_sign(_c(MICH - 0.55, -12.6), ["ул. Мичуринская"])
	_sign(_c(W + 3.6, sw - 0.75), ["пр. Энергетиков"])
	_sign(_c(W + 3.6, -3.6), ["ул. Монтажников"])
	_sign(_c(rx + RIV_W + 1.2, sw - 0.75), ["Рассказовское ш."])
	_road_name(_c(MICH + 2, 2), "ул. Мичуринская", true)
	_road_name(_c(MICH + 2, -28), "ул. Мичуринская", true)
	_road_name(_c(-1.5, -26), "Моршанское шоссе", true)
	_water_name(_c(rx + RIV_W * 0.5, 4), "р. Цна")
	_water_name(_c(rx + RIV_W * 0.5, -30), "р. Цна")
	_water_name(_c(rx + RIV_W * 0.5, H + 22), "р. Цна")
	# притушить дальние кварталы — лёгкая дымка, чтобы участок выделялся
	for k in 5:
		var g := 6 + k * 10
		_frame(Rect2((-g) * T, (-g) * T, (W + 2 * g) * T, (H + 2 * g) * T), Rect2((-g - 10) * T, (-g - 10) * T, (W + 2 * g + 20) * T, (H + 2 * g + 20) * T), Color(0.05, 0.06, 0.08, 0.03 + k * 0.02))
	_frame(Rect2(0, 0, W * T, H * T), Rect2((-4) * T, (-4) * T, (W + 8) * T, (H + 8) * T), Color(0.05, 0.06, 0.08, 0.08))
	# подписи — поверх всего
	for t: Array in _tags:
		_draw_tag(t[0], str(t[1]), str(t[2]), float(t[3]))
	for s: Array in _signs:
		_draw_sign(s[0], s[1])
	if life:
		life.reset()


## Юг: первый ряд пятиэтажек вдоль ул. Московской (их подъезды нужны StreetFolk), дальше — исторический центр.
func _south(w: World) -> void:
	var W := w.w
	var H := w.h
	var y0 := H + 2
	var y1 := H + 12
	var rx := W + RIV
	# первый ряд вдоль Московской
	_private(_rc(-M, y0, -58, y1), 2)
	_arena(_rc(-57, y0, -43, y1))
	var num := 71
	for b: Vector2i in [Vector2i(-41, -31), Vector2i(-29, -18), Vector2i(-16, -4)]:
		_home_block(Rect2i(b.x, y0, b.y - b.x, y1 - y0), "ул. Московская", num)
		num -= 4
	_t34(_rc(1, y0, 7, y1))
	var x := 9
	while x < W + 2:
		var bw := mini(12, W + 2 - x)
		if bw >= 6:
			_home_block(Rect2i(x, y0, bw, y1 - y0), "ул. Московская", num)
			num -= 4
		x += bw + 2
	_monastery_vozn(_rc(W + 4, y0, W + NAB - 1, y1))
	# Студенецкая набережная — поперёк, от вокзала до Набережной
	var ys := H + 13
	_hroad(-M, W + NAB, ys, 2)
	# Советская (на юг от перекрёстка) и Набережная — вдоль
	_vroad(-3, 0, H + 1, H + M)
	_vroad(W + NAB, W + NAB + 3, H + 1, H + M)
	# квартал между Студенецкой и Интернациональной
	_merchant_row(_rc(-46, H + 15.6, -4, H + 19.6))
	_pedestrian(_rc(-46, H + 20, -3, H + 22))
	_merchant_row(_rc(-46, H + 22.4, -4, H + 26))
	_cathedral(_rc(1, H + 15.5, W - 8, H + 26))
	_city_park(_rc(W - 6, H + 15.5, W + NAB - 1, H + 26))
	# Интернациональная (к вокзалу) и М. Горького (к Казанскому монастырю)
	var yi := H + 27
	_hroad(-M, W + NAB, yi, 2)
	_station(_rc(-70, H + 15.5, -48, H + 26))
	_university(_rc(-46, H + 29.5, -33, H + 38))
	_theatre(_rc(-31, H + 29.5, -18, H + 38))
	_lenin_square(_rc(-16, H + 29.5, -4, H + 42))
	_merchant_row(_rc(1, H + 29.5, W - 10, H + 33.5))
	_merchant_row(_rc(1, H + 35, W - 10, H + 39))
	_kazan(_rc(W - 8, H + 29.5, W + NAB - 1, H + 40))
	_aseev(_rc(W + 2, H + 42, W + NAB - 1, H + 52))
	_merchant_row(_rc(1, H + 41, W - 10, H + 45))
	_private(_rc(-M, H + 29.5, -48, H + M), 3)
	_private(_rc(-M, H + 15.5, -71, H + 26), 6)
	_private(_rc(-46, H + 43, -4, H + M), 4)
	_private(_rc(1, H + 47, W + 1, H + M), 5)
	_embankment(W + NAB + 3, rx, H + 1, H + M)
	# машины
	# 1.40: каждая машина едет от края города до края (с поворотами), а не пропадает на перекрёстке
	lanes.append([_c(-M, ys + 0.6), _c(W + NAB + 0.8, ys + 0.6), _c(W + NAB + 0.8, H + M)])
	lanes.append([_c(W + NAB + 2.2, H + M), _c(W + NAB + 2.2, ys + 1.4), _c(-M, ys + 1.4)])
	lanes.append([_c(-2.2, H + M), _c(-2.2, w.sidewalk_row + 1.9), _c(-M, w.sidewalk_row + 1.9)])
	lanes.append([_c(-M, w.sidewalk_row + 2.9), _c(-0.8, w.sidewalk_row + 2.9), _c(-0.8, H + M)])
	lanes.append([_c(-M, yi + 1.4), _c(-0.8, yi + 1.4), _c(-0.8, H + M)])
	lanes.append([_c(W + M, w.sidewalk_row + 1.9), _c(W + NAB + 0.8, w.sidewalk_row + 1.9), _c(W + NAB + 0.8, H + M)])
	# таблички и названия
	_sign(_c(0.45, H + 1.6), ["ул. Советская", "ул. Московская"])
	_sign(_c(-3.55, ys - 0.45), ["ул. Советская", "Студенецкая наб."])
	_sign(_c(-3.55, H + 19.7), ["ул. Коммунальная"])
	_sign(_c(-3.55, yi - 0.45), ["ул. Интернациональная"])
	_sign(_c(0.45, yi + 2.5), ["ул. М. Горького", "ул. Советская"])
	_sign(_c(W + NAB - 0.5, H + 1.6), ["ул. Набережная"])
	_sign(_c(W + NAB - 0.5, yi + 2.5), ["ул. М. Горького", "ул. Набережная"])
	_road_name(_c(-24, ys + 1), "Студенецкая набережная", false)
	_road_name(_c(-30, yi + 1), "ул. Интернациональная", false)
	_road_name(_c(24, yi + 1), "ул. Максима Горького", false)
	_road_name(_c(-1.5, H + 50), "ул. Советская", true)
	_road_name(_c(W + NAB + 1.5, H + 50), "ул. Набережная", true)
	_road_name(_c(-24, H + 21), "Коммунальная — пешеходная", false)


# ================================================================ улицы, вода, зелень

## Горизонтальная улица: асфальт, бордюры, прерывистая осевая.
func _hroad(x0: float, x1: float, y: float, rows: float) -> void:
	var r := _rc(x0, y, x1, y + rows)
	_rec.draw_rect(r, C_ASPH)
	_rec.draw_rect(Rect2(r.position.x, r.position.y - 2, r.size.x, 3), C_KERB)
	_rec.draw_rect(Rect2(r.position.x, r.end.y - 1, r.size.x, 3), C_KERB)
	var xx := r.position.x + 6
	while xx < r.end.x - 22:
		_rec.draw_rect(Rect2(xx, r.get_center().y - 1.5, 20, 3), Color(0.88, 0.88, 0.82, 0.3))
		xx += 64.0


func _vroad(x0: float, x1: float, y0: float, y1: float) -> void:
	var r := _rc(x0, y0, x1, y1)
	_rec.draw_rect(r, C_ASPH)
	_rec.draw_rect(Rect2(r.position.x - 2, r.position.y, 3, r.size.y), C_KERB)
	_rec.draw_rect(Rect2(r.end.x - 1, r.position.y, 3, r.size.y), C_KERB)
	var yy := r.position.y + 6
	while yy < r.end.y - 22:
		_rec.draw_rect(Rect2(r.get_center().x - 1.5, yy, 3, 20), Color(0.88, 0.88, 0.82, 0.3))
		yy += 64.0


## Широкий проспект (Мичуринская) или шоссе: две полосы в каждую сторону, двойная сплошная, троллейбусные провода.
func _avenue(r: Rect2, wide: bool) -> void:
	_rec.draw_rect(r, C_ASPH)
	_rec.draw_rect(Rect2(r.position.x - 3, r.position.y, 3, r.size.y), C_KERB)
	_rec.draw_rect(Rect2(r.end.x, r.position.y, 3, r.size.y), C_KERB)
	var cx := r.get_center().x
	if wide:
		_rec.draw_rect(Rect2(cx - 4, r.position.y, 2, r.size.y), Color(0.9, 0.9, 0.85, 0.5))
		_rec.draw_rect(Rect2(cx + 2, r.position.y, 2, r.size.y), Color(0.9, 0.9, 0.85, 0.5))
		var yy := r.position.y + 4
		while yy < r.end.y - 20:
			for o: float in [-r.size.x * 0.25, r.size.x * 0.25]:
				_rec.draw_rect(Rect2(cx + o - 1, yy, 2, 16), Color(0.9, 0.9, 0.85, 0.28))
			yy += 48.0
		# троллейбусные провода и опоры
		for o2: float in [-r.size.x * 0.3, -r.size.x * 0.22, r.size.x * 0.22, r.size.x * 0.3]:
			_rec.draw_line(Vector2(cx + o2, r.position.y), Vector2(cx + o2, r.end.y), Color(0.1, 0.1, 0.1, 0.35), 1.0)
		var py := r.position.y + 20
		while py < r.end.y:
			_rec.draw_line(Vector2(r.position.x - 6, py), Vector2(r.end.x + 6, py), Color(0.1, 0.1, 0.1, 0.3), 1.0)
			for ex: float in [r.position.x - 6, r.end.x + 6]:
				_rec.draw_circle(Vector2(ex + 3, py + 4), 3.5, C_SHADOW)
				_rec.draw_circle(Vector2(ex, py), 3.0, Color("#6f7477"))
			py += 6 * T
	else:
		var yy2 := r.position.y + 6
		while yy2 < r.end.y - 22:
			_rec.draw_rect(Rect2(cx - 1.5, yy2, 3, 20), Color(0.88, 0.88, 0.82, 0.3))
			yy2 += 64.0


## Цна: вода с течением, отмели, отблески.
func _river(x0: float, y0: float, y1: float) -> void:
	var r := _rc(x0, y0, x0 + RIV_W, y1)
	_rec.draw_rect(r, C_WATER)
	_rec.draw_rect(Rect2(r.position.x + r.size.x * 0.25, r.position.y, r.size.x * 0.5, r.size.y), C_WATER.darkened(0.12))
	_rec.draw_rect(Rect2(r.position.x, r.position.y, 6, r.size.y), C_WATER.lightened(0.12))
	_rec.draw_rect(Rect2(r.end.x - 6, r.position.y, 6, r.size.y), C_WATER.lightened(0.1))
	var lines := PackedVector2Array()
	var yy := r.position.y + 10
	while yy < r.end.y:
		var xx := r.position.x + _rng.randf_range(20, r.size.x - 50)
		var ln := _rng.randf_range(16, 40)
		lines.append(Vector2(xx, yy))
		lines.append(Vector2(xx, yy - ln))
		yy += _rng.randf_range(20, 46)
	_rec.draw_multiline(lines, Color(0.8, 0.9, 0.95, 0.16), 2.0)


## 1.40: надписи города на языке игры. В английском — перевод из таблицы, а улицы — латиницей
## с английским словом: «ул. Мичуринская» → «Michurinskaya St.», «Моршанское ш.» → «Morshanskoe Hwy».
static func _tx(s: String) -> String:
	if not L.is_en() or s == "":
		return s
	var t := L.t(s)
	if t != s:
		return t
	for p: Array in [["ул. ", "", " St."], ["пр. ", "", " Ave."], ["б-р ", "", " Blvd."], ["р. ", "", " River"]]:
		if s.begins_with(str(p[0])):
			return L.translit(s.trim_prefix(str(p[0]))) + str(p[2])
	for q: Array in [[" ш.", " Hwy"], [" шоссе", " Highway"], [" наб.", " Emb."], [" набережная", " Embankment"]]:
		if s.ends_with(str(q[0])):
			return L.translit(s.trim_suffix(str(q[0]))) + str(q[1])
	return L.translit(s)


func _water_name(c: Vector2, s0: String) -> void:
	var s := _tx(s0)
	_rec.draw_set_transform(c, -PI * 0.5, Vector2.ONE)
	var sz := _font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, 34)
	_rec.draw_string(_font, Vector2(-sz.x * 0.5, 12), s, HORIZONTAL_ALIGNMENT_LEFT, -1, 34, Color(0.82, 0.92, 0.98, 0.5))
	_rec.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Название улицы прямо на асфальте — как на карте, читается и при отдалении.
func _road_name(c: Vector2, s0: String, vertical: bool) -> void:
	var s := _tx(s0)
	_rec.draw_set_transform(c, -PI * 0.5 if vertical else 0.0, Vector2.ONE)
	var sz := _font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, 22)
	_rec.draw_string(_font, Vector2(-sz.x * 0.5, 8), s, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(0.95, 0.95, 0.9, 0.42))
	_rec.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Левый берег к северу от моста: луг, тропинка, ивы, камыш у воды.
func _bank_north(r: Rect2) -> void:
	_rec.draw_rect(r, C_LAWN)
	_rec.draw_rect(Rect2(r.position.x + r.size.x * 0.35, r.position.y, 10, r.size.y), Color("#8a8270"))
	var yy := r.position.y + 20
	while yy < r.end.y - 20:
		if _rng.randf() < 0.6:
			_tree(Vector2(r.position.x + _rng.randf_range(10, r.size.x * 0.3), yy), _rng.randf_range(12, 18), Color("#5a6e42"))
		for k in 3:
			var rp := Vector2(r.end.x - _rng.randf_range(3, 14), yy + k * 9)
			_rec.draw_line(rp, rp + Vector2(-3, -9), Color("#7f8a52"), 1.5)
		yy += _rng.randf_range(30, 60)


## Лес на правом берегу Цны: сосны пятнами, песчаный пляж у воды. near — ближе к дороге гуще.
func _forest(r: Rect2, _north: bool) -> void:
	_rec.draw_rect(r, Color("#3d5233"))
	_rec.draw_rect(Rect2(r.position.x, r.position.y, 34, r.size.y), Color("#b9ab84"))
	_rec.draw_rect(Rect2(r.position.x + 34, r.position.y, 22, r.size.y), Color("#6a7a4c"))
	# деревья — только там, куда может заглянуть камера
	var vis := Rect2(r.position.x, -48 * T, 44 * T, (sim.world.h + 104) * T).intersection(r)
	# деревья — одним мешем (много кругов отдельными командами дорого обходятся при отрисовке)
	var vs := PackedVector2Array()
	var cs := PackedColorArray()
	var step := 64.0
	var yy := vis.position.y + 24
	var row := 0
	while yy < vis.end.y:
		var xx := vis.position.x + 76 + (32.0 if row % 2 == 1 else 0.0)
		while xx < vis.end.x:
			var p := Vector2(xx + _rng.randf_range(-12, 12), yy + _rng.randf_range(-12, 12))
			var rad := _rng.randf_range(24, 34)
			_blob(vs, cs, p + Vector2(8, 7), rad, Color(0, 0, 0, 0.28))
			_blob(vs, cs, p, rad, Color("#2f4a2c") if _rng.randf() < 0.6 else Color("#36522f"))
			_blob(vs, cs, p - Vector2(rad * 0.3, rad * 0.3), rad * 0.5, Color("#47663b"))
			xx += step
		yy += step * 0.86
		row += 1
	if vs.size() > 0:
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = vs
		arr[Mesh.ARRAY_COLOR] = cs
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		_meshes.append(mesh)
		_rec.draw_mesh(mesh, null)


## Восьмиугольник-«крона» в общий меш.
func _blob(vs: PackedVector2Array, cs: PackedColorArray, c: Vector2, rad: float, col: Color) -> void:
	for i in 8:
		var a0 := i * TAU / 8.0
		var a1 := (i + 1) * TAU / 8.0
		vs.append(c)
		vs.append(c + Vector2(cos(a0), sin(a0)) * rad)
		vs.append(c + Vector2(cos(a1), sin(a1)) * rad)
		cs.append(col)
		cs.append(col)
		cs.append(col)


func _tree(p: Vector2, rad: float, col: Color) -> void:
	_rec.draw_circle(p + Vector2(5, 6), rad, C_SHADOW)
	_rec.draw_circle(p, rad, col)
	_rec.draw_circle(p - Vector2(rad * 0.3, rad * 0.3), rad * 0.55, col.lightened(0.15))


## Мост ул. Московской через Цну: дорогу рисует WorldView, здесь — перила, фонари и тени опор на воде.
func _bridge(w: World) -> void:
	var x0 := (w.w + RIV - 1) * T
	var x1 := (w.w + RIV + RIV_W + 1) * T
	var yn := w.sidewalk_row * T
	var ys := (w.h + 1) * T
	_rec.draw_rect(Rect2(x0, ys, x1 - x0, 18), Color(0, 0, 0, 0.35))
	_rec.draw_rect(Rect2(x0, ys, x1 - x0, 6), Color("#a8a59c"))
	for yb: float in [yn - 8, ys + 2]:
		_rec.draw_rect(Rect2(x0, yb, x1 - x0, 6), Color("#d8d4c8"))
		_rec.draw_rect(Rect2(x0, yb + 5, x1 - x0, 2), Color("#8e8a80"))
		var bx := x0 + 4
		while bx < x1:
			_rec.draw_rect(Rect2(bx, yb + 1, 2, 4), Color("#8e8a80"))
			bx += 8.0
	var lx := x0 + T
	while lx < x1:
		for yl: float in [yn - 6, ys + 4]:
			_rec.draw_circle(Vector2(lx + 3, yl + 4), 4.0, C_SHADOW)
			_rec.draw_circle(Vector2(lx, yl), 4.0, Color("#3b3f42"))
			_rec.draw_circle(Vector2(lx, yl), 2.2, Color("#f2e3a8"))
		lx += 2.5 * T
	for k in 2:
		var px := x0 + T + (k + 1) * (x1 - x0 - 2 * T) / 3.0
		_rec.draw_rect(Rect2(px - 10, ys + 6, 20, 30), Color(0, 0, 0, 0.22))
	_tag(Vector2((x0 + x1) * 0.5, ys + 2.0 * T), "Мост через Цну", "ул. Московская → Рассказовское ш.", 24)


# ================================================================ кварталы

## Частный сектор: участки с заборами, домики под шиферными крышами, сады.
func _private(r: Rect2, salt: int) -> void:
	_rec.draw_rect(r, Color("#66704f"))
	var vis := Rect2(-74 * T, -48 * T, (sim.world.w + 148) * T, (sim.world.h + 104) * T).intersection(r)
	var lw := 3.0 * T
	var lh := 2.6 * T
	var yy := vis.position.y + 6
	while yy + lh < vis.end.y:
		var xx := vis.position.x + 6
		while xx + lw < vis.end.x:
			var lot := Rect2(xx, yy, lw - 8, lh - 8)
			_rec.draw_rect(lot, Color("#6d7a52") if (int(xx / lw) + int(yy / lh) + salt) % 3 != 0 else Color("#76804e"))
			_rec.draw_rect(lot, Color("#8a7458"), false, 1.5)
			var roof_cols := [Color("#8d9196"), Color("#8a5a44"), Color("#5f7a5a"), Color("#9a9a8e")]
			var hc: Color = roof_cols[_rng.randi_range(0, 3)]
			var hr := Rect2(lot.position + Vector2(_rng.randf_range(4, 18), 5), Vector2(_rng.randf_range(34, 46), _rng.randf_range(26, 32)))
			_rec.draw_rect(Rect2(hr.position + Vector2(4, 5), hr.size), C_SHADOW)
			_rec.draw_rect(Rect2(hr.position, Vector2(hr.size.x, hr.size.y * 0.5)), hc.lightened(0.12))
			_rec.draw_rect(Rect2(hr.position + Vector2(0, hr.size.y * 0.5), Vector2(hr.size.x, hr.size.y * 0.5)), hc.darkened(0.12))
			_rec.draw_line(hr.position + Vector2(0, hr.size.y * 0.5), hr.position + Vector2(hr.size.x, hr.size.y * 0.5), hc.darkened(0.35), 1.5)
			if _rng.randf() < 0.7:
				_tree(lot.end - Vector2(_rng.randf_range(12, 26), _rng.randf_range(12, 20)), _rng.randf_range(9, 14), Color("#4f6a3c"))
			for g in 3:
				var gy := lot.end.y - 8 - g * 6
				_rec.draw_line(Vector2(lot.position.x + 6, gy), Vector2(lot.position.x + lot.size.x * 0.45, gy), Color("#5a6a3a"), 2.0)
			xx += lw
		yy += lh


## Панельные 9–10-этажки вдоль Мичуринской, во дворах деревья и машины, номера домов.
func _nine_storeys(r: Rect2) -> void:
	_rec.draw_rect(r, C_WALK)
	_rec.draw_rect(r.grow(-8), Color("#67704f"))
	var y := r.position.y + 14
	var num := 2
	while y + 3.6 * T < r.end.y - 10:
		_panel_tall(Rect2(r.position.x + 14, y, r.size.x - 28, 2.6 * T), 9, "ул. Мичуринская", num)
		num += 2
		var yard := Rect2(r.position.x + 14, y + 2.6 * T + 6, r.size.x - 28, 1.6 * T)
		var cx := yard.position.x + 6
		while cx + 24 < yard.end.x:
			if _rng.randf() < 0.45:
				_car(Vector2(cx, yard.position.y + 6), true)
			elif _rng.randf() < 0.5:
				_tree(Vector2(cx + 10, yard.get_center().y), _rng.randf_range(10, 15), Color("#4f6a3c"))
			cx += 22
		y += 4.6 * T


## Многоэтажка: плоская кровля, высокая лицевая стена с рядами окон (floors этажей), табличка с адресом.
func _panel_tall(r: Rect2, floors: int, street: String, num: int) -> void:
	var face_h := floors * 5.0 + 6.0
	var roof := Rect2(r.position, Vector2(r.size.x, r.size.y - face_h))
	_rec.draw_rect(Rect2(r.position + Vector2(12, 14), r.size), C_SHADOW)
	_rec.draw_rect(roof, Color("#6f7173"))
	_rec.draw_rect(roof, Color("#505254"), false, 2.0)
	var n := maxi(1, int(r.size.x / (T * 3.0)))
	for i in n:
		var hx := r.position.x + r.size.x * (i + 0.5) / n
		_rec.draw_rect(Rect2(hx - 7, roof.position.y + 5, 14, 11), Color("#8a8c8d"))
	var base := [Color("#c9c4b6"), Color("#b8c0c2"), Color("#d2b89a")][_rng.randi_range(0, 2)] as Color
	var face := Rect2(Vector2(r.position.x, roof.end.y), Vector2(r.size.x, face_h))
	_rec.draw_rect(face, base)
	_rec.draw_line(face.position, Vector2(face.end.x, face.position.y), base.darkened(0.35), 1.5)
	# бежевые и терракотовые вставки
	for i2 in n:
		var ix := r.position.x + r.size.x * (i2 + 0.5) / n
		_rec.draw_rect(Rect2(ix - 9, face.position.y + 2, 18, face_h - 2), Color("#c27a5a") if i2 % 2 == 0 else Color("#d9c49a"))
	var wins := PackedVector2Array()
	for f in floors:
		var fy := face.position.y + 4 + f * 5.0
		var wx := face.position.x + 4
		while wx + 5 < face.end.x - 3:
			wins.append(Vector2(wx, fy + 1.5))
			wins.append(Vector2(wx + 5, fy + 1.5))
			wx += 9.0
	_rec.draw_multiline(wins, C_WIN, 3.0)
	var lit := PackedVector2Array()
	for k in int(r.size.x / 30.0):
		var lx := face.position.x + 4 + 9.0 * _rng.randi_range(0, int((r.size.x - 12) / 9.0))
		var ly := face.position.y + 5.5 + 5.0 * _rng.randi_range(0, floors - 1)
		lit.append(Vector2(lx, ly))
		lit.append(Vector2(lx + 5, ly))
	_rec.draw_multiline(lit, Color("#e9d68a"), 3.0)
	for i3 in n:
		var dx := r.position.x + r.size.x * (i3 + 0.5) / n
		_rec.draw_rect(Rect2(dx - 5, face.end.y - 7, 10, 7), Color("#5a4636"))
	_house_plate(Vector2(face.position.x + 6, face.end.y - 18), street, num)


## Домовой знак: синяя табличка — улица и номер дома.
func _house_plate(p: Vector2, street: String, num: int) -> void:
	var s := _tx(street.replace("ул. ", ""))
	var sz := _font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, 7)
	var r := Rect2(p, Vector2(sz.x + 22, 11))
	_rec.draw_rect(r, C_SIGN)
	_rec.draw_rect(r.grow(-1), C_WHITE, false, 0.8)
	_rec.draw_string(_font, p + Vector2(3, 8.2), s, HORIZONTAL_ALIGNMENT_LEFT, -1, 7, C_WHITE)
	_rec.draw_string(_font, p + Vector2(sz.x + 5, 9.2), str(num), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, C_WHITE)


## Старый центр: ряд купеческих особняков в 1–3 этажа — охра, жёлтый, розовый, бело-голубой, красный кирпич.
func _merchant_row(r: Rect2) -> void:
	_rec.draw_rect(r, C_WALK)
	var cols := [Color("#d9b46a"), Color("#e3cf7a"), Color("#e2b9a8"), Color("#c9d6dc"), Color("#a5533f"), Color("#e8e0cc")]
	var roofs := [Color("#5f7a62"), Color("#7d8285"), Color("#6e7f6a"), Color("#8a6a58")]
	var x := r.position.x + 6
	while x < r.end.x - 30:
		var hw := minf(_rng.randf_range(2.4, 4.2) * T, r.end.x - 6 - x)
		var wall: Color = cols[_rng.randi_range(0, cols.size() - 1)]
		var roof: Color = roofs[_rng.randi_range(0, roofs.size() - 1)]
		var hr := Rect2(x, r.position.y + 6 + _rng.randf_range(0, 6), hw, r.size.y - 14)
		var face_h := clampf(hr.size.y * 0.32, 14.0, 24.0)
		_rec.draw_rect(Rect2(hr.position + Vector2(5, 7), hr.size), C_SHADOW)
		var rf := Rect2(hr.position, Vector2(hr.size.x, hr.size.y - face_h))
		_rec.draw_rect(rf, roof)
		_rec.draw_line(rf.position + Vector2(0, rf.size.y * 0.5), rf.position + Vector2(rf.size.x, rf.size.y * 0.5), roof.darkened(0.3), 1.5)
		var face := Rect2(Vector2(hr.position.x, rf.end.y), Vector2(hr.size.x, face_h))
		_rec.draw_rect(face, wall)
		_rec.draw_line(face.position, Vector2(face.end.x, face.position.y), wall.darkened(0.4), 1.5)
		var wx := face.position.x + 5
		while wx + 8 < face.end.x - 3:
			_rec.draw_rect(Rect2(wx - 1, face.position.y + 3, 8, face_h * 0.55 + 2), Color("#f4f1ea"))
			_rec.draw_rect(Rect2(wx, face.position.y + 4, 6, face_h * 0.55), C_WIN)
			wx += 12.0
		x += hw + _rng.randf_range(4, 10)


## Пешеходная Коммунальная: плитка, фонари, лавочки, клумбы.
func _pedestrian(r: Rect2) -> void:
	_rec.draw_rect(r, Color("#b3a58c"))
	var tiles := PackedVector2Array()
	var x := r.position.x
	while x < r.end.x:
		tiles.append(Vector2(x, r.position.y))
		tiles.append(Vector2(x, r.end.y))
		x += 16.0
	_rec.draw_multiline(tiles, Color(0.55, 0.5, 0.42, 0.35), 1.0)
	_rec.draw_rect(Rect2(r.position.x, r.get_center().y - 4, r.size.x, 8), Color("#c9bca0"))
	var lx := r.position.x + 30
	var k := 0
	while lx < r.end.x - 20:
		_rec.draw_circle(Vector2(lx + 3, r.position.y + 11), 4.0, C_SHADOW)
		_rec.draw_circle(Vector2(lx, r.position.y + 8), 4.0, Color("#2e3236"))
		_rec.draw_circle(Vector2(lx, r.position.y + 8), 2.2, Color("#f2e3a8"))
		if k % 2 == 0:
			_rec.draw_rect(Rect2(lx + 20, r.end.y - 12, 22, 6), Color("#6b4f3a"))
		else:
			_rec.draw_circle(Vector2(lx + 30, r.end.y - 10), 8.0, Color("#b0506a"))
			_rec.draw_circle(Vector2(lx + 30, r.end.y - 10), 4.0, Color("#e2c35a"))
		lx += 3.5 * T
		k += 1


## Жилые высотки (Северный район): дома-«свечки» и длинные девятиэтажки рядами.
func _towers(r: Rect2, street: String, num0: int) -> void:
	_rec.draw_rect(r, Color("#68704f"))
	var vis := Rect2(-74 * T, -48 * T, (sim.world.w + 148) * T, (sim.world.h + 104) * T).intersection(r)
	var y := vis.position.y + 10
	var num := num0
	while y + 3.4 * T < vis.end.y:
		var x := vis.position.x + 10
		while x + 6 * T < vis.end.x:
			var wd := minf(_rng.randf_range(6, 11) * T, vis.end.x - 10 - x)
			_panel_tall(Rect2(x, y, wd, 2.6 * T), 9 if _rng.randf() < 0.7 else 16, street, num)
			num += 2
			x += wd + 1.4 * T
		y += 4.4 * T


# ================================================================ достопримечательности

## Подпись достопримечательности: светлая табличка, тёмный крупный текст, вторая строка — мельче.
func _tag(c: Vector2, s: String, sub: String = "", px: float = 26.0) -> void:
	_tags.append([c, s, sub, px])


func _draw_tag(c: Vector2, s0: String, sub0: String, px: float) -> void:
	var s := _tx(s0)
	var sub := _tx(sub0)
	var fs := int(px)
	var ss := int(px * 0.62)
	var sz := _font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	var sz2 := _font.get_string_size(sub, HORIZONTAL_ALIGNMENT_LEFT, -1, ss) if sub != "" else Vector2.ZERO
	var bw := maxf(sz.x, sz2.x) + 18
	var bh := px * 1.25 + (ss * 1.2 if sub != "" else 0.0) + 4
	var r := Rect2(c - Vector2(bw * 0.5, bh * 0.5), Vector2(bw, bh))
	_rec.draw_rect(Rect2(r.position + Vector2(3, 4), r.size), Color(0, 0, 0, 0.35))
	_rec.draw_rect(r, Color(0.95, 0.93, 0.87, 0.93))
	_rec.draw_rect(Rect2(r.position, Vector2(5, r.size.y)), Color("#b8463a"))
	_rec.draw_string(_font, Vector2(r.position.x + 11, r.position.y + px * 1.02), s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color("#25272a"))
	if sub != "":
		_rec.draw_string(_font, Vector2(r.position.x + 11, r.position.y + px * 1.1 + ss * 1.05), sub, HORIZONTAL_ALIGNMENT_LEFT, -1, ss, Color("#5a5650"))


## Уличная табличка на столбе: синие плашки с белыми буквами, как на перекрёстках в Тамбове.
func _sign(p: Vector2, names: Array) -> void:
	_signs.append([p, names])


func _draw_sign(p: Vector2, names0: Array) -> void:
	var names := names0.map(func(x: Variant) -> String: return _tx(str(x)))
	var fs := 15
	var bw := 0.0
	for s: String in names:
		bw = maxf(bw, _font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x)
	bw += 14.0
	var bh := 21.0
	var top := p.y - 14 - bh * names.size()
	_rec.draw_rect(Rect2(p.x + 1, top + 4, 3, p.y - top), Color(0, 0, 0, 0.3))
	_rec.draw_rect(Rect2(p.x - 1.5, top, 3, p.y - top), Color("#8a9196"))
	_rec.draw_circle(p + Vector2(2, 2), 4.0, C_SHADOW)
	for i in names.size():
		var r := Rect2(p.x - bw * 0.5, top + i * bh, bw, bh - 2)
		_rec.draw_rect(Rect2(r.position + Vector2(3, 4), r.size), Color(0, 0, 0, 0.3))
		_rec.draw_rect(r, C_SIGN)
		_rec.draw_rect(r.grow(-2), C_WHITE, false, 1.2)
		_rec.draw_string(_font, Vector2(r.position.x + 7, r.position.y + 15), str(names[i]), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, C_WHITE)


## Длинная тень высокого сооружения: клин от основания по направлению SUN. w0 — полуширина у земли.
func _long_shadow(b: Vector2, hgt: float, w0: float, w1: float) -> void:
	var sd := SUN.normalized()
	var pp := Vector2(-sd.y, sd.x)
	var tip := b + sd * hgt
	_rec.draw_colored_polygon(PackedVector2Array([b - pp * w0, b + pp * w0, tip + pp * w1, tip - pp * w1]), Color(0, 0, 0, 0.22))


## Телебашня на Мичуринской: 180 м, типовая решётчатая (3803 КМ), красно-белая, площадки на 140 и 148 м.
## Вид «три четверти»: основание на земле, башня поднимается вверх по экрану, длинная тень ложится на квартал.
func _tv_tower(b: Vector2) -> void:
	var hgt := 12.0 * T
	var knots := [[0.0, 40.0], [0.16, 27.0], [0.38, 17.0], [0.6, 11.0], [0.78, 8.0], [0.86, 6.0]]
	# тень — решётчатая, с утолщением площадок
	var sd := SUN.normalized()
	var pp := Vector2(-sd.y, sd.x)
	var sl := hgt * 1.25
	_long_shadow(b, sl * 0.86, 40.0, 6.0)
	_rec.draw_line(b + sd * sl * 0.86, b + sd * sl, Color(0, 0, 0, 0.22), 3.0)
	for kp: float in [0.78, 0.82]:
		var c := b + sd * sl * kp
		_rec.draw_colored_polygon(PackedVector2Array([c - pp * 18 - sd * 4, c + pp * 18 - sd * 4, c + pp * 18 + sd * 4, c - pp * 18 + sd * 4]), Color(0, 0, 0, 0.2))
	var hatch := PackedVector2Array()
	for i in 12:
		var k0 := float(i) / 12.0 * 0.86
		var k1 := float(i + 1) / 12.0 * 0.86
		var w0 := _knot(knots, k0)
		var w1 := _knot(knots, k1)
		hatch.append_array([b + sd * sl * k0 - pp * w0, b + sd * sl * k1 + pp * w1, b + sd * sl * k0 + pp * w0, b + sd * sl * k1 - pp * w1])
	_rec.draw_multiline(hatch, Color(0, 0, 0, 0.14), 2.0)
	# основание: бетонная площадка, четыре фундамента, будка аппаратной
	_rec.draw_rect(Rect2(b - Vector2(56, 40), Vector2(112, 56)), Color("#8e8b82"))
	_rec.draw_rect(Rect2(b - Vector2(56, 40), Vector2(112, 56)), Color("#a9a69c"), false, 2.0)
	for o: Vector2 in [Vector2(-40, 0), Vector2(40, 0), Vector2(-30, -26), Vector2(30, -26)]:
		_rec.draw_rect(Rect2(b + o - Vector2(6, 5), Vector2(12, 10)), Color("#5f5d58"))
	# решётка: задние пояса темнее, передние — красно-белыми секциями
	var n := 14
	for i in n:
		var k0 := float(i) / n * 0.86
		var k1 := float(i + 1) / n * 0.86
		var hw0 := _knot(knots, k0)
		var hw1 := _knot(knots, k1)
		var y0 := b.y - hgt * k0
		var y1 := b.y - hgt * k1
		var col := C_RED if int(i / 2.0) % 2 == 0 else C_WHITE
		var back := Color(col.darkened(0.45), 0.8)
		_rec.draw_line(Vector2(b.x - hw0 * 0.72, y0 - 26 * (1.0 - k0)), Vector2(b.x - hw1 * 0.72, y1 - 26 * (1.0 - k1)), back, 2.0)
		_rec.draw_line(Vector2(b.x + hw0 * 0.72, y0 - 26 * (1.0 - k0)), Vector2(b.x + hw1 * 0.72, y1 - 26 * (1.0 - k1)), back, 2.0)
		_rec.draw_colored_polygon(PackedVector2Array([Vector2(b.x - hw0, y0), Vector2(b.x + hw0, y0), Vector2(b.x + hw1, y1), Vector2(b.x - hw1, y1)]), Color(col, 0.16))
		_rec.draw_line(Vector2(b.x - hw0, y0), Vector2(b.x + hw1, y1), col, 1.5)
		_rec.draw_line(Vector2(b.x + hw0, y0), Vector2(b.x - hw1, y1), col, 1.5)
		_rec.draw_line(Vector2(b.x - hw0, y0), Vector2(b.x - hw1, y1), col, 3.5)
		_rec.draw_line(Vector2(b.x + hw0, y0), Vector2(b.x + hw1, y1), col, 3.5)
		_rec.draw_line(Vector2(b.x - hw1, y1), Vector2(b.x + hw1, y1), col, 2.0)
	# площадки на 140 и 148 м
	for kp2: float in [0.78, 0.82]:
		var py := b.y - hgt * kp2
		var hw := _knot(knots, kp2) + 12
		_rec.draw_rect(Rect2(b.x - hw, py - 4, hw * 2, 8), Color("#d8d4cc"))
		_rec.draw_rect(Rect2(b.x - hw, py + 2, hw * 2, 3), Color("#6a6862"))
		_rec.draw_line(Vector2(b.x - hw, py - 4), Vector2(b.x + hw, py - 4), Color("#3c3c3c"), 1.0)
	# антенная мачта
	var m0 := b.y - hgt * 0.86
	var m1 := b.y - hgt
	for j in 6:
		var a := lerpf(m0, m1, float(j) / 6.0)
		var c2 := lerpf(m0, m1, float(j + 1) / 6.0)
		_rec.draw_line(Vector2(b.x, a), Vector2(b.x, c2), C_RED if j % 2 == 0 else C_WHITE, 4.0 - j * 0.35)
	beacons.append(Vector2(b.x, m1))
	beacons.append(Vector2(b.x, b.y - hgt * 0.82 - 5))
	_tag(b + Vector2(0, 2.4 * T), "Телебашня", "180 м · ул. Мичуринская", 34)


func _knot(kn: Array, k: float) -> float:
	for i in range(1, kn.size()):
		var a: Array = kn[i - 1]
		var b: Array = kn[i]
		if k <= float(b[0]):
			return lerpf(float(a[1]), float(b[1]), (k - float(a[0])) / maxf(0.001, float(b[0]) - float(a[0])))
	return float((kn[kn.size() - 1] as Array)[1])


## Огороженная территория телебашни: газон, дорожка, аппаратная РТПЦ, забор.
func _tv_yard(r: Rect2) -> void:
	_rec.draw_rect(r, C_LAWN)
	_rec.draw_rect(r.grow(-6), Color("#9aa0a3"), false, 1.5)
	_building(Rect2(r.position + Vector2(18, 16), Vector2(3.4 * T, 2.2 * T)), Color("#7a7c7e"), Color("#c9c3b4"), 1, "")
	var p := r.position + Vector2(r.size.x - 40, 30)
	for k in 5:
		_tree(p + Vector2(_rng.randf_range(-20, 10), k * 2.4 * T), _rng.randf_range(11, 16), Color("#4f6a3c"))


## Северный автовокзал: павильон, перроны, автобусы.
func _bus_station(r: Rect2) -> void:
	_rec.draw_rect(r, C_ASPH_L)
	var body := Rect2(r.position + Vector2(12, 10), Vector2(r.size.x * 0.5, r.size.y * 0.5))
	_building(body, Color("#76797c"), Color("#d8d0bc"), 0, "")
	_rec.draw_rect(Rect2(body.position.x, body.end.y - 4, body.size.x, 4), Color("#3d6aa8"))
	var bx := body.end.x + 18
	while bx + 22 < r.end.x - 6:
		_rec.draw_rect(Rect2(bx + 3, r.position.y + 16, 20, 70), C_SHADOW)
		_rec.draw_rect(Rect2(bx, r.position.y + 12, 20, 70), Color("#e8e2c8") if _rng.randf() < 0.6 else Color("#d9a83a"))
		_rec.draw_rect(Rect2(bx + 2, r.position.y + 14, 16, 8), C_WIN)
		bx += 32
	for k in 3:
		_rec.draw_rect(Rect2(r.position.x + 12, r.end.y - 30 + k * 9, r.size.x - 24, 3), Color(0.9, 0.9, 0.85, 0.3))
	_tag(Vector2(r.get_center().x, r.end.y - 22), "Северный автовокзал", "", 20)


## МиГ‑21 на постаменте у Мичуринской.
func _mig_square(r: Rect2) -> void:
	_rec.draw_rect(r, C_WALK)
	_rec.draw_rect(r.grow(-6), C_LAWN)
	var c := r.position + Vector2(5 * T, r.size.y * 0.5)
	_rec.draw_rect(Rect2(c - Vector2(30, 6), Vector2(60, 16)), Color("#8d8b84"))
	_rec.draw_set_transform(c - Vector2(0, 8), -0.35, Vector2.ONE)
	var jet := PackedVector2Array([Vector2(46, 0), Vector2(14, -4), Vector2(-6, -26), Vector2(-14, -26), Vector2(-8, -5), Vector2(-34, -4), Vector2(-40, -12), Vector2(-44, -12), Vector2(-42, 0), Vector2(-44, 12), Vector2(-40, 12), Vector2(-34, 4), Vector2(-8, 5), Vector2(-14, 26), Vector2(-6, 26), Vector2(14, 4)])
	var sh := PackedVector2Array()
	for q in jet:
		sh.append(q + Vector2(10, 14))
	_rec.draw_colored_polygon(sh, C_SHADOW)
	_rec.draw_colored_polygon(jet, Color("#c3c8cc"))
	_rec.draw_polyline(jet + PackedVector2Array([jet[0]]), Color("#7d8388"), 1.2)
	_rec.draw_rect(Rect2(Vector2(18, -3), Vector2(12, 6)), Color("#3e5866"))
	_rec.draw_circle(Vector2(-8, -18), 3.0, C_RED)
	_rec.draw_circle(Vector2(-8, 18), 3.0, C_RED)
	_rec.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	_tag(c + Vector2(0, 1.6 * T), "МиГ‑21", "", 20)


## Парк Победы: аллеи, фонтан, клумбы, деревья.
func _victory_park(r: Rect2) -> void:
	_rec.draw_rect(r, Color("#5b7146"))
	var c := r.get_center()
	_rec.draw_rect(Rect2(r.position.x, c.y - 10, r.size.x, 20), Color("#b8ad94"))
	_rec.draw_rect(Rect2(c.x - 10, r.position.y, 20, r.size.y), Color("#b8ad94"))
	_rec.draw_line(r.position, r.end, Color("#b8ad94"), 12.0)
	_rec.draw_line(Vector2(r.end.x, r.position.y), Vector2(r.position.x, r.end.y), Color("#b8ad94"), 12.0)
	_rec.draw_circle(c, 70.0, Color("#b8ad94"))
	_rec.draw_circle(c, 52.0, Color("#8a8a84"))
	_rec.draw_circle(c, 46.0, Color("#5b9ab8"))
	_rec.draw_circle(c, 30.0, Color("#7cb8d0"))
	_rec.draw_circle(c, 10.0, Color("#e6f2f6"))
	for k in 70:
		var p := r.position + Vector2(_rng.randf_range(20, r.size.x - 20), _rng.randf_range(20, r.size.y - 20))
		if absf(p.x - c.x) < 28 or absf(p.y - c.y) < 28 or p.distance_to(c) < 90:
			continue
		_tree(p, _rng.randf_range(12, 20), Color("#45633a") if k % 3 else Color("#557a42"))
	_tag(c + Vector2(0, 3.4 * T), "Парк Победы", "", 28)


## ТЭЦ (вымышленная «ТЭЦ‑Север»): главный корпус, высокие красно-белые трубы, градирня, ОРУ.
func _tec(r: Rect2) -> void:
	_rec.draw_rect(r, Color("#6e6c64"))
	_rec.draw_rect(r.grow(-4), Color("#9a9a92"), false, 2.0)
	var main := Rect2(r.position + Vector2(14, r.size.y * 0.1), Vector2(r.size.x * 0.6, r.size.y * 0.36))
	var roof := _building(main, Color("#7b7e80"), Color("#a69a88"), 2, "")
	_rec.draw_rect(Rect2(roof.position + Vector2(8, 8), Vector2(roof.size.x - 16, roof.size.y * 0.4)), Color("#8a8d8f"))
	_substation(Rect2(Vector2(r.position.x + 14, r.position.y + r.size.y * 0.56), Vector2(r.size.x * 0.5, r.size.y * 0.18)))
	# градирня
	var gc := Vector2(r.end.x - 3.2 * T, r.position.y + 4 * T)
	_rec.draw_circle(gc + Vector2(12, 14), 2.3 * T, C_SHADOW)
	_rec.draw_circle(gc, 2.3 * T, Color("#b9b6ac"))
	_rec.draw_circle(gc, 1.9 * T, Color("#5e6366"))
	_rec.draw_circle(gc, 1.5 * T, Color("#6e7478"))
	chimneys.append([gc, 11.5])   # пар из градирни (без огня)
	_tall_stack(Vector2(r.end.x - 2.6 * T, r.end.y - 1.6 * T), 10.0 * T, 16.0)
	_tall_stack(Vector2(r.end.x - 5.8 * T, r.end.y - 2.4 * T), 8.6 * T, 14.0)
	_tag(Vector2(main.get_center().x, main.position.y + 26), "ТЭЦ‑Север", "Моршанское ш.", 28)


## Высокая труба «три четверти»: красно-белые кольца, площадки; дым и огни — в CityLife.
func _tall_stack(b: Vector2, hgt: float, rad: float) -> void:
	_long_shadow(b, hgt * 1.15, rad, rad * 0.7)
	_rec.draw_circle(b, rad + 6, Color("#8a877e"))
	var n := 8
	for i in n:
		var k0 := float(i) / n
		var k1 := float(i + 1) / n
		var w0 := lerpf(rad, rad * 0.68, k0)
		var w1 := lerpf(rad, rad * 0.68, k1)
		var y0 := b.y - hgt * k0
		var y1 := b.y - hgt * k1
		var col := C_RED if (i >= n - 3 and i % 2 == 1) or (i < n - 3 and i % 3 == 2) else C_WHITE
		_rec.draw_colored_polygon(PackedVector2Array([Vector2(b.x - w0, y0), Vector2(b.x + w0, y0), Vector2(b.x + w1, y1), Vector2(b.x - w1, y1)]), col)
		_rec.draw_colored_polygon(PackedVector2Array([Vector2(b.x + w0 * 0.35, y0), Vector2(b.x + w0, y0), Vector2(b.x + w1, y1), Vector2(b.x + w1 * 0.35, y1)]), Color(0, 0, 0, 0.14))
	var top := Vector2(b.x, b.y - hgt)
	_rec.draw_rect(Rect2(top.x - rad * 0.68, top.y - 3, rad * 1.36, 6), Color("#2e2f31"))
	for kp: float in [0.5, 0.8]:
		var w2 := lerpf(rad, rad * 0.68, kp) + 3
		_rec.draw_rect(Rect2(b.x - w2, b.y - hgt * kp - 2, w2 * 2, 4), Color("#4a4c4e"))
	chimneys.append([top, rad * 0.9])


## Химкомбинат (вымышленный «Цна‑Колор») у левого берега Цны: резервуары, колонны, эстакада трубопроводов.
func _chem(r: Rect2) -> void:
	_rec.draw_rect(r, Color("#6c6a60"))
	_rec.draw_rect(r.grow(-4), Color("#9a9a92"), false, 2.0)
	_tanks(Rect2(r.position + Vector2(10, 10), Vector2(r.size.x - 20, r.size.y * 0.3)))
	var py := r.position.y + r.size.y * 0.42
	for k in 3:
		var pc: Color = [Color("#8a6a3a"), Color("#5d6a73"), Color("#7a7f82")][k]
		_rec.draw_line(Vector2(r.position.x + 8, py + k * 6), Vector2(r.end.x - 8, py + k * 6), pc, 3.0)
	var sx := r.position.x + 20
	while sx < r.end.x - 10:
		_rec.draw_rect(Rect2(sx, py - 3, 4, 18), Color("#4a4c4e"))
		sx += 40
	_saw_shop(Rect2(Vector2(r.position.x + 10, r.end.y - r.size.y * 0.4), Vector2(r.size.x * 0.55, r.size.y * 0.36)))
	for k2 in 3:
		_column(Vector2(r.end.x - 2.0 * T - k2 * 1.6 * T, r.end.y - 1.4 * T - k2 * 0.5 * T), (3.4 + k2 * 0.6) * T, 9.0)
	_tag(Vector2(r.get_center().x, r.position.y + r.size.y * 0.55), "Химкомбинат «Цна‑Колор»", "", 22)


## Ректификационная колонна: серый цилиндр с площадками.
func _column(b: Vector2, hgt: float, rad: float) -> void:
	_long_shadow(b, hgt * 1.1, rad, rad)
	_rec.draw_rect(Rect2(b.x - rad, b.y - hgt, rad * 2, hgt), Color("#b9bcbc"))
	_rec.draw_rect(Rect2(b.x + rad * 0.3, b.y - hgt, rad * 0.7, hgt), Color("#9a9d9e"))
	for k in 4:
		_rec.draw_rect(Rect2(b.x - rad - 3, b.y - hgt * (0.2 + k * 0.22), rad * 2 + 6, 3), Color("#c8a83a"))
	_rec.draw_circle(Vector2(b.x, b.y - hgt), rad, Color("#d0d2d2"))


## Ледовый дворец «Кристалл»: светлая коробка арены со сводчатой кровлей.
func _arena(r: Rect2) -> void:
	_rec.draw_rect(r, C_PAVE)
	var body := Rect2(r.position + Vector2(16, 12), r.size - Vector2(32, 30))
	var roof := _building(body, Color("#c9d3d8"), Color("#e8eef0"), 0, "")
	for k in int(roof.size.x / 18.0):
		_rec.draw_line(Vector2(roof.position.x + 9 + k * 18, roof.position.y + 3), Vector2(roof.position.x + 9 + k * 18, roof.end.y - 3), Color("#aebbc2"), 2.0)
	_rec.draw_rect(Rect2(body.position.x + 10, body.end.y - 16, body.size.x - 20, 12), Color("#5a9ad0"))
	_tag(Vector2(r.get_center().x, roof.get_center().y), "Ледовый дворец «Кристалл»", "", 22)


## Т‑34 «Тамбовский колхозник» на постаменте — угол Советской и Московской.
func _t34(r: Rect2) -> void:
	_rec.draw_rect(r, C_PAVE)
	_rec.draw_rect(r.grow(-8), C_LAWN)
	var c := r.get_center() - Vector2(0, 14)
	_rec.draw_rect(Rect2(c - Vector2(34, 34) + Vector2(8, 10), Vector2(68, 68)), C_SHADOW)
	_rec.draw_rect(Rect2(c - Vector2(34, 34), Vector2(68, 68)), Color("#b9b3a6"))
	_rec.draw_rect(Rect2(c - Vector2(34, 34), Vector2(68, 68)), Color("#8d887c"), false, 2.0)
	_rec.draw_rect(Rect2(c - Vector2(16, 26), Vector2(32, 52)), Color("#4a5a3a"))
	_rec.draw_rect(Rect2(c - Vector2(20, 26), Vector2(5, 52)), Color("#2e3326"))
	_rec.draw_rect(Rect2(c + Vector2(15, -26), Vector2(5, 52)), Color("#2e3326"))
	_rec.draw_circle(c + Vector2(0, -4), 11.0, Color("#56683f"))
	_rec.draw_line(c + Vector2(0, -4), c + Vector2(0, -42), Color("#3a4a2c"), 4.0)
	for k in 6:
		_tree(r.position + Vector2(14 + (k % 2) * (r.size.x - 28), 22 + int(k / 2.0) * (r.size.y - 44) / 2.0), 10.0, Color("#3f5a34"))
	_tag(c + Vector2(0, 2.0 * T), "Т‑34 «Тамбовский колхозник»", "", 18)


## Вознесенский монастырь на Московской: ограда, два храма, колокольня.
func _monastery_vozn(r: Rect2) -> void:
	_rec.draw_rect(r, C_LAWN)
	_rec.draw_rect(r.grow(-4), Color("#efe7da"), false, 5.0)
	var a := Rect2(r.position + Vector2(18, 18), Vector2(r.size.x * 0.42, r.size.y * 0.5))
	_church(a, Color("#efe2d6"), Color("#5f8a72"), [[0.5, 14.0, Color("#3f78b0")], [0.2, 8.0, C_GOLD], [0.8, 8.0, C_GOLD]])
	var b := Rect2(Vector2(r.position.x + r.size.x * 0.55, r.position.y + r.size.y * 0.3), Vector2(r.size.x * 0.38, r.size.y * 0.45))
	_church(b, Color("#f2f0ea"), Color("#6e7f6a"), [[0.5, 11.0, C_GOLD]])
	_bell_tower(Vector2(r.position.x + r.size.x * 0.3, r.end.y - 20), 3.0 * T, 0.5)
	_tag(Vector2(r.get_center().x, r.end.y - 6), "Вознесенский монастырь", "", 20)


## Храм «три четверти»: стены, крыша, луковичные главы над крышей. domes: [[доля по ширине, радиус, цвет]].
func _church(r: Rect2, wall: Color, roof: Color, domes: Array) -> void:
	var rf := _building(r, roof, wall, 0, "")
	for d: Array in domes:
		var c := Vector2(rf.position.x + rf.size.x * float(d[0]), rf.get_center().y)
		_onion(c, float(d[1]), d[2] as Color, wall)


## Луковичная глава с барабаном и крестом (c — центр луковицы).
func _onion(c: Vector2, rr: float, col: Color, wall: Color) -> void:
	_rec.draw_rect(Rect2(c.x - rr * 0.7 + 4, c.y + rr * 0.4 + 6, rr * 1.4, rr * 1.4), C_SHADOW)
	_rec.draw_rect(Rect2(c.x - rr * 0.7, c.y + rr * 0.4, rr * 1.4, rr * 1.4), wall)
	_rec.draw_rect(Rect2(c.x + rr * 0.2, c.y + rr * 0.4, rr * 0.5, rr * 1.4), wall.darkened(0.15))
	_rec.draw_colored_polygon(PackedVector2Array([c + Vector2(-rr * 0.62, -rr * 0.55), c + Vector2(0, -rr * 1.9), c + Vector2(rr * 0.62, -rr * 0.55)]), col)
	_rec.draw_circle(c, rr, col)
	_rec.draw_circle(c + Vector2(-rr * 0.35, -rr * 0.3), rr * 0.36, col.lightened(0.35))
	_rec.draw_line(c + Vector2(0, -rr * 1.9), c + Vector2(0, -rr * 1.9 - 10), C_GOLD, 1.5)
	_rec.draw_line(c + Vector2(-4, -rr * 1.9 - 6), c + Vector2(4, -rr * 1.9 - 6), C_GOLD, 1.5)


## Многоярусная колокольня «три четверти»: белые ярусы с арками, золотая глава и шпиль; k — масштаб ширины.
func _bell_tower(b: Vector2, hgt: float, k: float) -> void:
	_long_shadow(b, hgt * 1.15, 34.0 * k, 3.0)
	var widths := [66.0, 56.0, 46.0, 36.0, 28.0]
	var hs := [0.25, 0.2, 0.16, 0.13, 0.1]
	_rec.draw_rect(Rect2(b.x - 40 * k, b.y - 10, 80 * k, 14), Color("#c9c3b4"))
	var y := b.y
	for i in 5:
		var wd: float = float(widths[i]) * k
		var th: float = float(hs[i]) * hgt
		var tr := Rect2(b.x - wd * 0.5, y - th, wd, th)
		_rec.draw_rect(tr, C_WHITE)
		_rec.draw_rect(Rect2(tr.position.x + wd * 0.62, tr.position.y, wd * 0.38, th), Color("#d6d0c2"))
		_rec.draw_rect(Rect2(tr.position.x - 3, tr.position.y - 2, wd + 6, 4), Color("#cfc8b8"))
		var nw := 2 if wd > 30 else 1
		for j in nw:
			var wx := tr.position.x + wd * (j + 0.5) / nw
			var ww := minf(10.0, wd * 0.22)
			var wh := th * 0.5
			_rec.draw_rect(Rect2(wx - ww * 0.5, tr.position.y + th * 0.3, ww, wh), Color("#3a4048"))
			_rec.draw_circle(Vector2(wx, tr.position.y + th * 0.3), ww * 0.5, Color("#3a4048"))
		y -= th
	var dr := 13.0 * maxf(0.6, k)
	_onion(Vector2(b.x, y - dr * 1.2), dr, C_GOLD, C_WHITE)
	var sp := y - dr * 1.2 - dr * 1.9
	_rec.draw_colored_polygon(PackedVector2Array([Vector2(b.x - 3, sp), Vector2(b.x + 3, sp), Vector2(b.x, sp - hgt * 0.1)]), C_GOLD)
	_rec.draw_line(Vector2(b.x, sp - hgt * 0.1), Vector2(b.x, sp - hgt * 0.1 - 12), C_GOLD, 2.0)
	_rec.draw_line(Vector2(b.x - 5, sp - hgt * 0.1 - 8), Vector2(b.x + 5, sp - hgt * 0.1 - 8), C_GOLD, 2.0)


## Спасо‑Преображенский собор на Соборной площади: пятиглавый, отдельная колокольня, Вечный огонь.
func _cathedral(r: Rect2) -> void:
	_rec.draw_rect(r, C_PAVE)
	var tiles := PackedVector2Array()
	var x := r.position.x
	while x < r.end.x:
		tiles.append(Vector2(x, r.position.y))
		tiles.append(Vector2(x, r.end.y))
		x += 24.0
	_rec.draw_multiline(tiles, Color(0.5, 0.48, 0.42, 0.3), 1.0)
	var c := r.get_center()
	# газоны с липами по краям площади, памятник Питириму у собора
	for side: float in [0.0, 1.0]:
		var lr := Rect2(r.position.x + 12 + side * (r.size.x * 0.72), r.position.y + 12, r.size.x * 0.28 - 24, r.size.y - 24)
		_rec.draw_rect(lr, C_LAWN)
		_rec.draw_rect(lr, Color("#8a8270"), false, 2.0)
		var ty := lr.position.y + 22
		while ty < lr.end.y - 14:
			var tx := lr.position.x + 22
			while tx < lr.end.x - 14:
				_tree(Vector2(tx + _rng.randf_range(-6, 6), ty + _rng.randf_range(-6, 6)), _rng.randf_range(11, 15), Color("#4a6a3a"))
				tx += 52.0
			ty += 50.0
	var body := Rect2(c.x - 4.6 * T, r.position.y + 2.6 * T, 9.2 * T, 5.6 * T)
	var rf := _building(body, Color("#4f7a5e"), Color("#f2ece0"), 0, "")
	_rec.draw_rect(Rect2(body.position.x + 8, body.end.y - 20, body.size.x - 16, 4), Color("#d9c48a"))
	var cc := rf.get_center()
	for o: Vector2 in [Vector2(-2.6, -0.4), Vector2(2.6, -0.4), Vector2(-2.6, 1.1), Vector2(2.6, 1.1)]:
		_onion(cc + o * T, 15.0, Color("#2f5f4a"), Color("#f2ece0"))
	_onion(cc + Vector2(0, 0.1 * T), 26.0, C_GOLD, Color("#f2ece0"))
	_bell_tower(Vector2(body.position.x - 2.0 * T, r.end.y - 0.8 * T), 4.2 * T, 0.6)
	# Вечный огонь
	var f := Vector2(body.end.x + 3.0 * T, r.end.y - 2.4 * T)
	_rec.draw_circle(f + Vector2(4, 5), 34.0, C_SHADOW)
	_rec.draw_circle(f, 34.0, Color("#6e6a66"))
	_rec.draw_circle(f, 26.0, Color("#56524e"))
	var star := PackedVector2Array()
	for i in 10:
		var a := -PI * 0.5 + i * PI / 5.0
		star.append(f + Vector2(cos(a), sin(a)) * (18.0 if i % 2 == 0 else 8.0))
	_rec.draw_colored_polygon(star, Color("#b8463a"))
	_rec.draw_colored_polygon(PackedVector2Array([f + Vector2(-6, 0), f + Vector2(0, -16), f + Vector2(6, 0), f + Vector2(0, 5)]), Color("#ffb03a"))
	_rec.draw_colored_polygon(PackedVector2Array([f + Vector2(-3, 0), f + Vector2(0, -9), f + Vector2(3, 0)]), Color("#fff0a0"))
	for k in 4:
		_tree(f + Vector2(-50 + k * 33, 46), 9.0, Color("#2f4a32"))
	_tag(Vector2(c.x, r.end.y - 0.7 * T), "Спасо‑Преображенский собор", "Соборная площадь · Вечный огонь", 30)


## Городской парк у Советской: аллеи, деревья, картинная галерея.
func _city_park(r: Rect2) -> void:
	_rec.draw_rect(r, Color("#5b7146"))
	_rec.draw_line(r.position + Vector2(0, r.size.y * 0.6), Vector2(r.end.x, r.position.y + r.size.y * 0.4), Color("#b8ad94"), 10.0)
	_rec.draw_line(Vector2(r.get_center().x, r.position.y), Vector2(r.get_center().x, r.end.y), Color("#b8ad94"), 8.0)
	_building(Rect2(r.position + Vector2(18, 16), Vector2(5 * T, 2.6 * T)), Color("#7d8285"), Color("#efe6d2"), 0, "")
	for k in 26:
		var p := r.position + Vector2(_rng.randf_range(16, r.size.x - 16), _rng.randf_range(16, r.size.y - 16))
		if p.x < r.position.x + 6 * T and p.y < r.position.y + 3.5 * T:
			continue
		_tree(p, _rng.randf_range(11, 17), Color("#45633a"))
	_tag(Vector2(r.position.x + 3.2 * T, r.position.y + 4.2 * T), "Картинная галерея", "", 15)


## Вокзал Тамбов‑1 в конце Интернациональной: здание с башенкой, перроны под навесами, пути.
func _station(r: Rect2) -> void:
	_rec.draw_rect(r, C_PAVE)
	var tx := r.position.x + 10
	for k in 3:
		var py := tx + k * 1.6 * T
		_rec.draw_rect(Rect2(py, r.position.y, T * 0.9, r.size.y), Color("#6e6a64"))
		_rec.draw_line(Vector2(py + 7, r.position.y), Vector2(py + 7, r.end.y), Color("#b9bcbe"), 2.0)
		_rec.draw_line(Vector2(py + T * 0.9 - 7, r.position.y), Vector2(py + T * 0.9 - 7, r.end.y), Color("#b9bcbe"), 2.0)
	_rec.draw_rect(Rect2(tx + 0.95 * T, r.position.y + 10, 0.6 * T, r.size.y - 20), Color("#7d8a96"))
	var body := Rect2(r.position.x + 5.6 * T, r.position.y + r.size.y * 0.3, r.size.x - 6.4 * T, r.size.y * 0.5)
	var rf := _building(body, Color("#5f7a68"), Color("#ecdcae"), 3, "")
	var tc := Vector2(rf.get_center().x, rf.position.y + 6)
	_long_shadow(tc, 90.0, 24.0, 4.0)
	_rec.draw_rect(Rect2(tc.x - 24, tc.y - 70, 48, rf.size.y + 70), Color("#ecdcae"))
	_rec.draw_rect(Rect2(tc.x + 6, tc.y - 70, 18, rf.size.y + 70), Color("#d4c495"))
	_rec.draw_rect(Rect2(tc.x - 26, tc.y - 72, 52, 4), C_WHITE)
	_rec.draw_circle(Vector2(tc.x, tc.y - 44), 13.0, C_WHITE)
	_rec.draw_arc(Vector2(tc.x, tc.y - 44), 13.0, 0, TAU, 24, Color("#5a4c3c"), 1.5)
	_rec.draw_line(Vector2(tc.x, tc.y - 44), Vector2(tc.x, tc.y - 53), Color("#222222"), 1.5)
	_rec.draw_line(Vector2(tc.x, tc.y - 44), Vector2(tc.x + 7, tc.y - 44), Color("#222222"), 1.5)
	_rec.draw_rect(Rect2(tc.x - 10, tc.y - 24, 20, 22), C_WIN)
	_rec.draw_colored_polygon(PackedVector2Array([Vector2(tc.x - 26, tc.y - 70), Vector2(tc.x, tc.y - 104), Vector2(tc.x + 26, tc.y - 70)]), Color("#5f7a68"))
	_rec.draw_line(Vector2(tc.x, tc.y - 104), Vector2(tc.x, tc.y - 120), C_GOLD, 2.0)
	_tag(Vector2(body.get_center().x, r.position.y + 0.9 * T), "Вокзал Тамбов‑1", "", 28)


## ТГУ им. Державина (корпус на Интернациональной).
func _university(r: Rect2) -> void:
	_rec.draw_rect(r, C_PAVE)
	_building(Rect2(r.position + Vector2(8, 10), Vector2(r.size.x - 16, r.size.y * 0.62)), Color("#7d8285"), Color("#e0d2b4"), 0, "")
	_tag(Vector2(r.get_center().x, r.end.y - 22), "ТГУ им. Державина", "", 16)


## Драмтеатр на Интернациональной: колоннада и фронтон.
func _theatre(r: Rect2) -> void:
	_rec.draw_rect(r, C_PAVE)
	var body := Rect2(r.position + Vector2(12, 8), Vector2(r.size.x - 24, r.size.y * 0.62))
	var face_h := 40.0
	var roof := Rect2(body.position, Vector2(body.size.x, body.size.y - face_h))
	_rec.draw_rect(Rect2(body.position + Vector2(8, 10), body.size), C_SHADOW)
	_rec.draw_rect(roof, Color("#6f7e86"))
	_rec.draw_rect(roof, Color("#4f5a60"), false, 2.0)
	var face := Rect2(Vector2(body.position.x, roof.end.y), Vector2(body.size.x, face_h))
	_rec.draw_rect(face, Color("#e8d7a8"))
	var pc := Vector2(face.get_center().x, face.position.y)
	_rec.draw_colored_polygon(PackedVector2Array([pc + Vector2(-70, 0), pc + Vector2(0, -26), pc + Vector2(70, 0)]), Color("#efe4c6"))
	_rec.draw_polyline(PackedVector2Array([pc + Vector2(-70, 0), pc + Vector2(0, -26), pc + Vector2(70, 0)]), Color("#b9a87a"), 2.0)
	_rec.draw_rect(Rect2(pc.x - 66, face.position.y + 2, 132, face_h - 4), Color("#5a4c3c"))
	for k in 8:
		var cx := pc.x - 60 + k * 17.0
		_rec.draw_rect(Rect2(cx, face.position.y + 1, 7, face_h - 2), C_WHITE)
		_rec.draw_rect(Rect2(cx + 4, face.position.y + 1, 3, face_h - 2), Color("#d6d0c2"))
	_rec.draw_rect(Rect2(face.position.x, face.end.y - 4, face.size.x, 4), Color("#c9b98f"))
	_tag(Vector2(r.get_center().x, r.end.y - 20), "Драмтеатр", "", 26)


## Площадь Ленина: плитка, ели, памятник на высоком постаменте, обладминистрация.
func _lenin_square(r: Rect2) -> void:
	_rec.draw_rect(r, Color("#a6a094"))
	var g := PackedVector2Array()
	var x := r.position.x
	while x < r.end.x:
		g.append(Vector2(x, r.position.y))
		g.append(Vector2(x, r.end.y))
		x += 32.0
	var y := r.position.y
	while y < r.end.y:
		g.append(Vector2(r.position.x, y))
		g.append(Vector2(r.end.x, y))
		y += 32.0
	_rec.draw_multiline(g, Color(0.45, 0.43, 0.38, 0.3), 1.0)
	var c := Vector2(r.get_center().x, r.position.y + 4.6 * T)
	for k in 8:
		var e := Vector2(r.position.x + 22 + (k % 4) * (r.size.x - 44) / 3.0, r.position.y + 20 + int(k / 4.0) * 7.0 * T)
		_tree(e, 12.0, Color("#2c4632"))
	_rec.draw_rect(Rect2(c.x - 40, c.y + 6, 80, 18), Color("#8a8580"))
	_rec.draw_rect(Rect2(c.x - 16 + 8, c.y - 70 + 12, 32, 96), C_SHADOW)
	_rec.draw_rect(Rect2(c.x - 16, c.y - 70, 32, 90), Color("#8f8a84"))
	_rec.draw_rect(Rect2(c.x + 4, c.y - 70, 12, 90), Color("#76716b"))
	_rec.draw_rect(Rect2(c.x - 6, c.y - 104, 12, 34), Color("#4b3d2e"))
	_rec.draw_circle(Vector2(c.x, c.y - 108), 6.0, Color("#4b3d2e"))
	_rec.draw_line(Vector2(c.x + 4, c.y - 98), Vector2(c.x + 20, c.y - 116), Color("#4b3d2e"), 4.0)
	var adm := Rect2(Vector2(r.position.x + 12, r.end.y - 3.6 * T), Vector2(r.size.x - 24, 3.2 * T))
	_building(adm, Color("#6e7476"), Color("#e2ddd0"), 0, "")
	_rec.draw_line(Vector2(adm.get_center().x, adm.position.y + 8), Vector2(adm.get_center().x, adm.position.y - 22), Color("#c8c8c0"), 2.0)
	_rec.draw_rect(Rect2(adm.get_center().x, adm.position.y - 22, 16, 4), C_WHITE)
	_rec.draw_rect(Rect2(adm.get_center().x, adm.position.y - 18, 16, 4), Color("#2f5fb0"))
	_rec.draw_rect(Rect2(adm.get_center().x, adm.position.y - 14, 16, 4), C_RED)
	_tag(c + Vector2(0, 1.6 * T), "Площадь Ленина", "", 26)


## Казанский монастырь: голубой Казанский храм, краснокирпичный пятиглавый храм, колокольня 107 м.
func _kazan(r: Rect2) -> void:
	_rec.draw_rect(r, C_LAWN)
	_rec.draw_rect(r.grow(-4), Color("#efe9dc"), false, 6.0)
	var a := Rect2(r.position + Vector2(20, 2.6 * T), Vector2(r.size.x * 0.36, 4.2 * T))
	_church(a, Color("#8fb6d6"), Color("#4a7aa8"), [[0.5, 15.0, Color("#3f78b0")], [0.18, 7.0, C_GOLD], [0.82, 7.0, C_GOLD]])
	var b := Rect2(Vector2(r.position.x + 20, r.end.y - 4.8 * T), Vector2(r.size.x * 0.4, 3.8 * T))
	_church(b, Color("#a5533f"), Color("#5f7a62"), [[0.5, 13.0, C_GOLD], [0.2, 8.0, Color("#3d6a54")], [0.8, 8.0, Color("#3d6a54")], [0.35, 7.0, Color("#3d6a54")], [0.65, 7.0, Color("#3d6a54")]])
	for k in 9:
		_tree(r.position + Vector2(_rng.randf_range(r.size.x * 0.5, r.size.x - 20), _rng.randf_range(20, r.size.y * 0.35)), _rng.randf_range(10, 14), Color("#45633a"))
	_bell_tower(Vector2(r.position.x + r.size.x * 0.68, r.end.y - 1.2 * T), 8.0 * T, 1.0)
	_tag(Vector2(r.position.x + r.size.x * 0.68, r.end.y + 0.6 * T), "Казанский монастырь", "колокольня 107 м", 32)


## Усадьба Асеевых: светлый дворец с башенками над рекой, парк.
func _aseev(r: Rect2) -> void:
	_rec.draw_rect(r, Color("#5b7146"))
	var body := Rect2(r.position + Vector2(r.size.x * 0.15, 2.2 * T), Vector2(r.size.x * 0.7, 3.6 * T))
	var rf := _building(body, Color("#6f8a7a"), Color("#f0e2cc"), 0, "")
	_rec.draw_rect(Rect2(body.position.x, body.end.y - 26, body.size.x, 3), C_WHITE)
	for o: float in [0.0, 1.0]:
		var tc := Vector2(body.position.x + body.size.x * o, rf.position.y + 10)
		_rec.draw_rect(Rect2(tc.x - 14, tc.y - 30, 28, body.size.y - 6), Color("#f4ead8"))
		_rec.draw_rect(Rect2(tc.x + 4, tc.y - 30, 10, body.size.y - 6), Color("#e0d2ba"))
		_rec.draw_colored_polygon(PackedVector2Array([Vector2(tc.x - 17, tc.y - 30), Vector2(tc.x, tc.y - 60), Vector2(tc.x + 17, tc.y - 30)]), Color("#6f8a7a"))
	_rec.draw_circle(Vector2(rf.get_center().x, rf.position.y + 6), 14.0, Color("#7f9a8a"))
	for k in 20:
		var p := r.position + Vector2(_rng.randf_range(14, r.size.x - 14), _rng.randf_range(r.size.y * 0.62, r.size.y - 14))
		_tree(p, _rng.randf_range(11, 16), Color("#45633a"))
	_tag(Vector2(r.get_center().x, body.end.y + 1.1 * T), "Усадьба Асеевых", "", 28)


## Набережная Цны в два яруса: верхняя аллея с фонарями, откос с лестницами, нижний променад у воды,
## памятники Рахманинову и «Русскому мужику», Мост влюблённых.
func _embankment(x0: float, x1: float, y0: float, y1: float) -> void:
	var up := _rc(x0, y0, x0 + 2, y1)
	var slope := _rc(x0 + 2, y0, x1 - 1.4, y1)
	var low := _rc(x1 - 1.4, y0, x1, y1)
	_rec.draw_rect(up, Color("#b0a690"))
	_rec.draw_rect(slope, Color("#5c7148"))
	_rec.draw_rect(low, Color("#9a9286"))
	_rec.draw_rect(Rect2(up.end.x - 4, up.position.y, 4, up.size.y), C_WHITE)
	_rec.draw_rect(Rect2(low.end.x - 5, low.position.y, 5, low.size.y), Color("#6e6a64"))
	var vis_end := minf(y1, sim.world.h + 56)
	var yy := y0 * T + 40
	var k := 0
	while yy < vis_end * T:
		# фонари на обоих ярусах
		for lx: float in [up.position.x + 10, low.position.x + 10]:
			_rec.draw_circle(Vector2(lx + 3, yy + 4), 4.0, C_SHADOW)
			_rec.draw_circle(Vector2(lx, yy), 4.0, Color("#2e3236"))
			_rec.draw_circle(Vector2(lx, yy), 2.2, Color("#f2e3a8"))
		if k % 3 == 1:
			# лестница через откос
			var st := Rect2(slope.position.x, yy - 14, slope.size.x, 28)
			_rec.draw_rect(st, Color("#c3baa6"))
			var sx := st.position.x + 4
			while sx < st.end.x:
				_rec.draw_line(Vector2(sx, st.position.y + 2), Vector2(sx, st.end.y - 2), Color("#8e8676"), 1.5)
				sx += 7.0
		elif k % 3 == 2:
			_tree(Vector2(slope.get_center().x, yy), 13.0, Color("#4f6a3c"))
		yy += 2.6 * T
		k += 1
	var H := sim.world.h
	_statue(_c(x0 + 1.0, H + 31.5), Color("#4b3d2e"))
	_tag(_c(x0 + 1.0, H + 33.2), "Рахманинов", "", 13)
	_statue(_c(x0 + 1.0, H + 39.5), Color("#3e3a36"))
	_tag(_c(x0 + 1.0, H + 41.2), "«Русский мужик»", "", 13)
	# Мост влюблённых — пешеходный, с замками
	var by := (H + 36.0) * T
	var br := Rect2(low.position.x, by - 10, (x1 + RIV_W) * T - low.position.x + 12, 20)
	_rec.draw_rect(Rect2(br.position + Vector2(0, 12), br.size), Color(0, 0, 0, 0.3))
	_rec.draw_rect(br, Color("#b8b2a6"))
	_rec.draw_line(br.position, Vector2(br.end.x, br.position.y), Color("#4a4c4e"), 2.0)
	_rec.draw_line(Vector2(br.position.x, br.end.y), br.end, Color("#4a4c4e"), 2.0)
	var lk := br.position.x + 6
	while lk < br.end.x:
		var lc: Color = [C_RED, C_GOLD, Color("#4f7ad0"), Color("#d070a0")][_rng.randi_range(0, 3)]
		_rec.draw_circle(Vector2(lk, br.position.y + 1), 1.8, lc)
		lk += 7.0
	_tag(Vector2(br.get_center().x + 1.2 * T, by + 1.1 * T), "Мост влюблённых", "", 14)
	_tag(_c(x0 + 2.6, H + 24), "Набережная Цны", "", 24)


func _statue(p: Vector2, col: Color) -> void:
	_rec.draw_rect(Rect2(p.x - 9 + 6, p.y - 6 + 7, 18, 14), C_SHADOW)
	_rec.draw_rect(Rect2(p.x - 9, p.y - 10, 18, 16), Color("#8d887c"))
	_rec.draw_rect(Rect2(p.x - 4, p.y - 30, 8, 20), col)
	_rec.draw_circle(Vector2(p.x, p.y - 33), 4.0, col)


## «Тамбовский волк»: деревянная скульптура на въезде по Рассказовскому шоссе, на опушке.
func _wolf(p: Vector2) -> void:
	var clr := Rect2(p - Vector2(2.4 * T, 1.6 * T), Vector2(4.8 * T, 3.4 * T))
	_rec.draw_rect(clr, Color("#7a8a5a"))
	_rec.draw_rect(Rect2(p.x - 30, p.y - 4, 60, 18), Color("#8d887c"))
	_rec.draw_rect(Rect2(p.x - 30, p.y + 10, 60, 4), Color("#6e6a62"))
	var body := PackedVector2Array([Vector2(-26, -20), Vector2(-30, -34), Vector2(-24, -30), Vector2(-14, -36), Vector2(10, -38), Vector2(20, -46), Vector2(24, -62), Vector2(30, -54), Vector2(34, -56), Vector2(32, -46), Vector2(40, -40), Vector2(30, -36), Vector2(24, -26), Vector2(22, -4), Vector2(16, -4), Vector2(14, -22), Vector2(-10, -22), Vector2(-14, -4), Vector2(-20, -4), Vector2(-20, -18)])
	var sh := PackedVector2Array()
	var pts := PackedVector2Array()
	for q in body:
		pts.append(p + q)
		sh.append(p + Vector2(q.x, 0) + SUN * (-q.y) * 0.8)
	_rec.draw_colored_polygon(sh, Color(0, 0, 0, 0.25))
	_rec.draw_colored_polygon(pts, Color("#7a5a3a"))
	_rec.draw_polyline(pts + PackedVector2Array([pts[0]]), Color("#4e3a26"), 1.5)
	_rec.draw_circle(p + Vector2(29, -52), 1.6, Color("#e8d070"))
	_tag(p + Vector2(0, 1.3 * T), "Тамбовский волк", "Рассказовское ш.", 26)


# ================================================================ общие части

## Залить рамку между внутренним и внешним прямоугольником.
func _frame(inner: Rect2, outer: Rect2, col: Color) -> void:
	_rec.draw_rect(Rect2(outer.position, Vector2(outer.size.x, inner.position.y - outer.position.y)), col)
	_rec.draw_rect(Rect2(Vector2(outer.position.x, inner.end.y), Vector2(outer.size.x, outer.end.y - inner.end.y)), col)
	_rec.draw_rect(Rect2(Vector2(outer.position.x, inner.position.y), Vector2(inner.position.x - outer.position.x, inner.size.y)), col)
	_rec.draw_rect(Rect2(Vector2(inner.end.x, inner.position.y), Vector2(outer.end.x - inner.end.x, inner.size.y)), col)


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
					_rec.draw_rect(Rect2(px - 1, yy * T + 8, 2, 14), Color(0.85, 0.85, 0.8, 0.22))
				if _rng.randf() < 0.35 and lanes.size() < 24:
					lanes.append([Vector2(px + 0.35 * T, y * T), Vector2(px + 0.35 * T, (y + bh) * T)])
			x += bw + 2
		# проезд под рядом кварталов
		var py := (y + bh + 1) * T
		if y + bh + 2 < r.end.y:
			for xx in range(r.position.x, r.end.x, 2):
				_rec.draw_rect(Rect2(xx * T + 8, py - 1, 14, 2), Color(0.85, 0.85, 0.8, 0.22))
			if _rng.randf() < 0.5 and lanes.size() < 24:
				lanes.append([Vector2(r.position.x * T, py + 0.35 * T), Vector2(r.end.x * T, py + 0.35 * T)])
		y += bh + 2


## Квартал: тротуар по краю, фонари на углах; возвращает прямоугольник квартала.
func _lot(b: Rect2i) -> Rect2:
	var r := Rect2(Vector2(b.position) * T, Vector2(b.size) * T)
	_rec.draw_rect(r, C_WALK)
	_rec.draw_rect(r.grow(-10), C_GROUND)
	_rec.draw_rect(r, C_KERB, false, 2.0)
	for c: Vector2 in [r.position + Vector2(5, 5), Vector2(r.end.x - 5, r.position.y + 5), Vector2(r.position.x + 5, r.end.y - 5), r.end - Vector2(5, 5)]:
		_rec.draw_circle(c + Vector2(2, 3), 3.0, C_SHADOW)
		_rec.draw_circle(c, 3.0, Color("#3b3f42"))
		_rec.draw_circle(c, 1.6, Color("#e8d9a0"))
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
## 1.30: адрес настоящий — табличка с улицей и номером на углу дома.
func _home_block(b: Rect2i, street: String = "ул. Московская", num: int = 41) -> void:
	var r := _lot(b)
	var inset := Rect2(r.position + Vector2(T * 0.8, T * 0.8), r.size - Vector2(T * 1.6, T * 1.6))
	if inset.size.x < T * 4 or inset.size.y < T * 4:
		_trees(r.grow(-10), 3)
		return
	var k := _rng.randi_range(2, 9)
	_rec.draw_rect(inset, Color("#6a6f58"))
	var house_h := T * 2.2
	var top := Rect2(inset.position, Vector2(inset.size.x, house_h))
	_panel_house(top)
	var bot := Rect2(Vector2(inset.position.x, inset.end.y - house_h), Vector2(inset.size.x * (0.55 if k % 2 == 0 else 1.0), house_h))
	_panel_house(bot)
	var yard := Rect2(Vector2(inset.position.x, top.end.y + 8), Vector2(inset.size.x, bot.position.y - top.end.y - 16))
	if yard.size.y > T * 1.2:
		_rec.draw_rect(Rect2(yard.position.x, yard.get_center().y - 4, yard.size.x, 8), C_WALK)
		var nd := maxi(1, int(top.size.x / (T * 2.4)))
		for di in nd:
			doors.append({"door": Vector2(top.position.x + top.size.x * (di + 0.5) / nd, top.end.y), "yard_y": yard.get_center().y,
				"lx": r.position.x + 5.0, "rx": r.end.x - 5.0, "top": r.position.y})
		_trees(Rect2(yard.position, Vector2(yard.size.x * 0.5, yard.size.y)), 4)
		var pg := Rect2(yard.position + Vector2(yard.size.x * 0.58, 6), Vector2(minf(yard.size.x * 0.24, T * 2.5), yard.size.y - 12))
		_rec.draw_rect(pg, Color("#b39a6a"))
		_rec.draw_rect(pg, Color("#7a6a4a"), false, 1.5)
		_rec.draw_line(pg.position + Vector2(6, 6), pg.position + Vector2(pg.size.x - 6, 6), Color("#c8463a"), 2.0)
		_rec.draw_circle(pg.get_center(), minf(pg.size.x, pg.size.y) * 0.16, Color("#d9c27a"))
		var cx := pg.end.x + 10
		while cx + 14 < yard.end.x:
			if _rng.randf() < 0.7:
				_car(Vector2(cx, yard.position.y + 8), true)
			cx += 20
	if bot.size.x < inset.size.x:
		_trees(Rect2(bot.end.x + 8, bot.position.y, inset.end.x - bot.end.x - 8, bot.size.y), 3)
	_house_plate(Vector2(top.position.x + 8, top.end.y - 16), street, num)
	_house_plate(Vector2(bot.position.x + 8, bot.end.y - 16), street, num + 2)


## Пятиэтажка: кровля с выходами на крышу, лицевая стена с рядами окон и подъездами.
func _panel_house(r: Rect2) -> void:
	var base := [Color("#b9b2a4"), Color("#a9b3b5"), Color("#c2a88f"), Color("#b5b09c")][_rng.randi_range(0, 3)] as Color
	var face_h := r.size.y * 0.42
	var roof := Rect2(r.position, Vector2(r.size.x, r.size.y - face_h))
	_rec.draw_rect(Rect2(r.position + Vector2(6, 8), r.size), C_SHADOW)
	_rec.draw_rect(roof, Color("#6d6f70"))
	_rec.draw_rect(roof, Color("#4e5052"), false, 2.0)
	var n := maxi(1, int(r.size.x / (T * 2.4)))
	for i in n:
		var hx := r.position.x + r.size.x * (i + 0.5) / n
		_rec.draw_rect(Rect2(hx - 6, roof.position.y + 6, 12, 10), Color("#8a8c8d"))
	var face := Rect2(Vector2(r.position.x, roof.end.y), Vector2(r.size.x, face_h))
	_rec.draw_rect(face, base)
	_rec.draw_line(face.position, Vector2(face.end.x, face.position.y), base.darkened(0.35), 1.5)
	var rows := 2
	var cols := int(r.size.x / 11.0)
	for ry in rows:
		for cx in cols:
			var p := Vector2(face.position.x + 4 + cx * 11.0, face.position.y + 3 + ry * (face_h - 4) / rows)
			var lit := _rng.randf() < 0.12
			_rec.draw_rect(Rect2(p, Vector2(6, (face_h - 4) / rows - 4)), Color("#e9d68a") if lit else C_WIN)
	for i2 in n:
		var dx := r.position.x + r.size.x * (i2 + 0.5) / n
		_rec.draw_rect(Rect2(dx - 5, face.end.y - 7, 10, 7), Color("#5a4636"))


func _school(r: Rect2) -> void:
	_rec.draw_rect(r, Color("#6a6f58"))
	var body := Rect2(r.position, Vector2(r.size.x, r.size.y * 0.45))
	_building(body, Color("#c9b98f"), Color("#d8c9a2"), 0, L.t("Школа №%d") % _rng.randi_range(3, 27))
	var field := Rect2(r.position + Vector2(r.size.x * 0.1, r.size.y * 0.55), Vector2(r.size.x * 0.8, r.size.y * 0.4))
	_rec.draw_rect(field, Color("#5f8a4a"))
	_rec.draw_rect(field.grow(-4), Color(1, 1, 1, 0.5), false, 1.5)
	_rec.draw_line(Vector2(field.get_center().x, field.position.y + 4), Vector2(field.get_center().x, field.end.y - 4), Color(1, 1, 1, 0.5), 1.5)
	_rec.draw_arc(field.get_center(), minf(field.size.y * 0.2, 20.0), 0, TAU, 24, Color(1, 1, 1, 0.5), 1.5)


## Здание «три четверти»: кровля сверху, снизу — лицевая стена (окна, ворота).
## gates: сколько ворот в лицевой стене. Возвращает прямоугольник кровли (для узора крыши).
func _building(r: Rect2, roof_col: Color, wall_col: Color, gates: int = 0, sign_text: String = "") -> Rect2:
	var face_h := clampf(r.size.y * 0.22, 14.0, 30.0)
	var roof := Rect2(r.position, Vector2(r.size.x, r.size.y - face_h))
	var face := Rect2(Vector2(r.position.x, roof.end.y), Vector2(r.size.x, face_h))
	_rec.draw_rect(Rect2(r.position + Vector2(8, 10), r.size), C_SHADOW)
	_rec.draw_rect(roof, roof_col)
	_rec.draw_rect(roof, roof_col.darkened(0.35), false, 2.0)
	_rec.draw_rect(face, wall_col)
	_rec.draw_line(face.position, Vector2(face.end.x, face.position.y), wall_col.darkened(0.45), 2.0)
	_rec.draw_line(Vector2(face.position.x, face.end.y), face.end, wall_col.darkened(0.5), 2.0)
	var wx := face.position.x + 6
	while wx + 10 < face.end.x - 4:
		_rec.draw_rect(Rect2(wx, face.position.y + 4, 9, face_h * 0.4), C_WIN if _rng.randf() < 0.85 else C_WIN_L)
		wx += 15
	for g in gates:
		var gx := face.position.x + face.size.x * (g + 0.5) / gates - 14
		var gr := Rect2(gx, face.position.y + face_h * 0.25, 28, face_h * 0.75)
		_rec.draw_rect(gr, Color("#9aa0a3"))
		for k in 4:
			_rec.draw_line(Vector2(gr.position.x + 2, gr.position.y + 3 + k * gr.size.y / 4.0), Vector2(gr.end.x - 2, gr.position.y + 3 + k * gr.size.y / 4.0), Color("#6f7578"), 1.0)
		_rec.draw_rect(Rect2(gx - 3, gr.position.y, 3, gr.size.y), Color("#d4b13a"))
		_rec.draw_rect(Rect2(gr.end.x, gr.position.y, 3, gr.size.y), Color("#d4b13a"))
	if sign_text != "":
		_label(Vector2(roof.get_center().x, roof.position.y + minf(roof.size.y * 0.5, 30.0)), sign_text, 1.0)
	return roof


## Вывеска на крыше: светлые буквы на тёмной табличке. k — масштаб.
func _label(c: Vector2, s0: String, k: float) -> void:
	var s := _tx(s0)
	var px := int(round(22 * k))
	var sz := _font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, px)
	var r := Rect2(c - Vector2(sz.x * 0.5 + 6, sz.y * 0.5 + 2), sz + Vector2(12, 4))
	_rec.draw_rect(r, Color(0.1, 0.12, 0.14, 0.78))
	_rec.draw_string(_font, Vector2(r.position.x + 6, r.position.y + sz.y * 0.78 + 2), s, HORIZONTAL_ALIGNMENT_LEFT, -1, px, Color("#e6e2d6"))


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
		_rec.draw_rect(Rect2(roof.position.x + o + 2, roof.position.y + 2, step * 0.62, roof.size.y - 4), base.lightened(0.12))
		_rec.draw_rect(Rect2(roof.position.x + o + step * 0.62 + 2, roof.position.y + 2, step * 0.3, roof.size.y - 4), Color("#5f7884"))
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
		_rec.draw_line(Vector2(roof.position.x + 3, roof.position.y + 3 + i * 7), Vector2(roof.end.x - 3, roof.position.y + 3 + i * 7), base.lightened(0.08), 1.0)
	for k in _rng.randi_range(2, 4):
		var p := roof.position + Vector2(_rng.randf_range(12, roof.size.x - 24), _rng.randf_range(8, maxf(9.0, roof.size.y - 20)))
		_rec.draw_rect(Rect2(p, Vector2(12, 12)), Color("#a3a7a8"))
		_rec.draw_circle(p + Vector2(6, 6), 4.0, Color("#4b4f52"))
	_rec.draw_rect(Rect2(Vector2(r.position.x, body.end.y), Vector2(r.size.x, 8)), Color("#8d8a82"))
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
	_rec.draw_rect(roof.grow(-5), Color("#75777a"))
	_rec.draw_rect(Rect2(r.get_center().x - 12, r.end.y - 4, 24, 8), Color("#9a9890"))
	_rec.draw_rect(Rect2(r.get_center().x - 16, roof.end.y + 2, 32, 4), Color("#4a4c4f"))
	if _rng.randf() < 0.5:
		var fp := Vector2(r.position.x + 14, r.end.y + 8)
		_rec.draw_line(fp, fp - Vector2(0, 26), Color("#c8c8c0"), 2.0)
		_rec.draw_rect(Rect2(fp - Vector2(0, 26), Vector2(14, 9)), Color("#b23a2e"))
	_label(Vector2(roof.get_center().x, roof.position.y + minf(roof.size.y * 0.5, 30.0)), _pick("office"), 0.95)


## Ёмкости: круглые баки с лесенками на бетонной площадке, трубы между ними.
func _tanks(r: Rect2) -> void:
	_rec.draw_rect(r, Color("#7c7a72"))
	_rec.draw_rect(r, Color("#9a9a92"), false, 2.0)
	var n := 2 if r.size.x < 6 * T else 3
	var rad := minf(r.size.y * 0.32, r.size.x / float(n) * 0.38)
	var cy := r.get_center().y
	var prev := Vector2.ZERO
	for i in n:
		var c := Vector2(r.position.x + r.size.x * (i + 0.5) / n, cy)
		_rec.draw_circle(c + Vector2(6, 8), rad, C_SHADOW)
		_rec.draw_circle(c, rad, Color("#c2c0b6"))
		_rec.draw_arc(c, rad, 0, TAU, 40, Color("#8c8a82"), 2.0)
		_rec.draw_arc(c, rad * 0.62, 0, TAU, 32, Color("#a9a79e"), 1.5)
		_rec.draw_circle(c, rad * 0.14, Color("#8c8a82"))
		_rec.draw_arc(c, rad * 0.98, -0.6, 0.2, 8, Color("#5b5f62"), 3.0)
		if i > 0:
			_rec.draw_line(prev + Vector2(rad, 0), c - Vector2(rad, 0), Color("#5d6a73"), 4.0)
		prev = c
	_label(Vector2(r.get_center().x, r.end.y - 14), _pick("tanks"), 0.85)


## Котельная: корпус и высокая труба с красно-белыми кольцами (дым — в CityLife), кучи угля.
func _boiler(r: Rect2) -> void:
	var body := Rect2(r.position, Vector2(r.size.x * 0.62, r.size.y))
	var roof := _building(body, Color("#7d7f80"), Color("#a4795e"), 1, "")
	_rec.draw_rect(roof.grow(-6), Color("#8a8c8d"))
	var c := Vector2(r.position.x + r.size.x * 0.82, r.get_center().y)
	_chimney(c, minf(r.size.x * 0.12, 22.0))
	_rec.draw_circle(Vector2(c.x, r.end.y - 18), 14.0, Color("#2e2f31"))
	_rec.draw_circle(Vector2(c.x - 10, r.end.y - 12), 10.0, Color("#3a3b3d"))
	_label(Vector2(roof.get_center().x, roof.position.y + minf(roof.size.y * 0.5, 28.0)), _pick("boiler"), 0.9)


func _chimney(c: Vector2, rad: float) -> void:
	_rec.draw_circle(c + Vector2(14, 18), rad, C_SHADOW)
	_rec.draw_circle(c, rad, Color("#e6e1d6"))
	_rec.draw_arc(c, rad * 0.78, 0, TAU, 32, Color("#b8463a"), rad * 0.22)
	_rec.draw_arc(c, rad * 0.4, 0, TAU, 24, Color("#b8463a"), rad * 0.16)
	_rec.draw_circle(c, rad * 0.22, Color("#2e2f31"))
	chimneys.append([c, rad])


## Автобаза: фуры в ряд, будка диспетчера.
func _truck_yard(r: Rect2) -> void:
	_rec.draw_rect(r, C_ASPH_L)
	for x in range(int(r.position.x) + 4, int(r.end.x) - 4, 30):
		_rec.draw_line(Vector2(x, r.position.y + 4), Vector2(x, r.position.y + 60), Color(0.9, 0.9, 0.85, 0.35), 1.0)
	var x2 := r.position.x + 8
	while x2 + 22 < r.end.x:
		if _rng.randf() < 0.7:
			_truck(Vector2(x2, r.position.y + 6), false)
		x2 += 30
	_rec.draw_rect(Rect2(r.end.x - 26, r.end.y - 22, 20, 16), Color("#c8c2b0"))
	_rec.draw_rect(Rect2(r.end.x - 22, r.end.y - 18, 8, 6), C_WIN)
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
	_rec.draw_rect(Rect2(p + Vector2(3, 4), Vector2(20, 61)), C_SHADOW)
	_rec.draw_rect(trailer, col)
	_rec.draw_rect(trailer, col.darkened(0.3), false, 1.0)
	_rec.draw_rect(cab, Color("#c23b2f") if _rng.randf() < 0.5 else Color("#2f5f8f"))
	_rec.draw_rect(Rect2(cab.position.x + 2, cab.position.y + (9 if to_dock else 2), 14, 3), C_WIN_L)


## Легковушка сверху.
func _car(p: Vector2, vertical: bool) -> void:
	var cols := [Color("#c8c8c0"), Color("#8a2f2a"), Color("#2f4f6f"), Color("#d6c27a"), Color("#4f6f4a"), Color("#e8e6e0"), Color("#222426")]
	var col: Color = cols[_rng.randi_range(0, cols.size() - 1)]
	var sz := Vector2(11, 20) if vertical else Vector2(20, 11)
	_rec.draw_rect(Rect2(p + Vector2(2, 3), sz), C_SHADOW)
	_rec.draw_rect(Rect2(p, sz), col)
	if vertical:
		_rec.draw_rect(Rect2(p + Vector2(1.5, 4), Vector2(8, 4)), C_WIN)
		_rec.draw_rect(Rect2(p + Vector2(1.5, 13), Vector2(8, 3)), C_WIN)
	else:
		_rec.draw_rect(Rect2(p + Vector2(4, 1.5), Vector2(4, 8)), C_WIN)
		_rec.draw_rect(Rect2(p + Vector2(13, 1.5), Vector2(3, 8)), C_WIN)


## Контейнерная площадка: штабели контейнеров и козловой кран.
func _containers(r: Rect2) -> void:
	_rec.draw_rect(r, C_ASPH_L)
	var cols := [Color("#3f6a8a"), Color("#a8462f"), Color("#5f7d4a"), Color("#c49a3a"), Color("#8b8f91")]
	var cw := 18.0
	var ch := 54.0
	var x := r.position.x + 6
	while x + cw < r.end.x - 4:
		var y := r.position.y + 6
		while y + ch < r.end.y - 4:
			if _rng.randf() < 0.75:
				var col: Color = cols[_rng.randi_range(0, cols.size() - 1)]
				_rec.draw_rect(Rect2(Vector2(x + 3, y + 4), Vector2(cw, ch)), C_SHADOW)
				_rec.draw_rect(Rect2(Vector2(x, y), Vector2(cw, ch)), col)
				for k in 5:
					_rec.draw_line(Vector2(x + 2, y + 6 + k * 10), Vector2(x + cw - 2, y + 6 + k * 10), col.darkened(0.25), 1.0)
			y += ch + 8
		x += cw + 8
	_rec.draw_line(Vector2(r.position.x + 2, r.position.y + r.size.y * 0.4), Vector2(r.end.x - 2, r.position.y + r.size.y * 0.4), Color("#d4b13a"), 5.0)
	_rec.draw_rect(Rect2(r.get_center().x - 8, r.position.y + r.size.y * 0.4 - 7, 16, 14), Color("#b8943a"))
	_label(Vector2(r.get_center().x, r.end.y - 14), _pick("cont"), 0.8)


## Гаражный кооператив: ряды боксов с разноцветными воротами.
func _garages(r: Rect2) -> void:
	_rec.draw_rect(r, C_ASPH_L)
	var doors := [Color("#6f7f5a"), Color("#8a4a3a"), Color("#4a6a8a"), Color("#9a9a90"), Color("#a8823a")]
	var rowh := 34.0
	var y := r.position.y + 4
	while y + rowh < r.end.y - 4:
		var row := Rect2(r.position.x + 4, y, r.size.x - 8, rowh - 10)
		_rec.draw_rect(Rect2(row.position + Vector2(4, 5), row.size), C_SHADOW)
		_rec.draw_rect(Rect2(row.position, Vector2(row.size.x, row.size.y - 8)), Color("#5f6163"))
		var x := row.position.x
		while x + 16 < row.end.x:
			_rec.draw_rect(Rect2(x, row.end.y - 8, 15, 8), doors[_rng.randi_range(0, doors.size() - 1)])
			_rec.draw_line(Vector2(x + 16, row.position.y), Vector2(x + 16, row.end.y), Color("#4a4c4e"), 1.0)
			x += 17
		y += rowh + 10
	_label(Vector2(r.get_center().x, r.end.y - 12), _pick("garage"), 0.8)


## Подстанция: трансформаторы и порталы за сетчатым забором.
func _substation(r: Rect2) -> void:
	_rec.draw_rect(r, Color("#7a776d"))
	for x in range(int(r.position.x) + 6, int(r.end.x) - 6, 6):
		_rec.draw_line(Vector2(x, r.position.y + 6), Vector2(x, r.end.y - 6), Color(0.6, 0.6, 0.55, 0.25), 1.0)
	_rec.draw_rect(r.grow(-4), Color("#a6a8a0"), false, 2.0)
	var n := clampi(int(r.size.x / (T * 2.2)), 2, 5)
	for i in n:
		var c := Vector2(r.position.x + r.size.x * (i + 0.5) / n, r.get_center().y)
		_rec.draw_rect(Rect2(c - Vector2(14, 12) + Vector2(4, 5), Vector2(28, 24)), C_SHADOW)
		_rec.draw_rect(Rect2(c - Vector2(14, 12), Vector2(28, 24)), Color("#5f7a6a"))
		for k in 3:
			_rec.draw_line(c + Vector2(-10 + k * 10, -12), c + Vector2(-10 + k * 10, -26), Color("#c8c8c0"), 2.0)
		_rec.draw_line(c + Vector2(-16, -26), c + Vector2(16, -26), Color("#9a9c96"), 3.0)
	_label(Vector2(r.get_center().x, r.end.y - 14), _pick("sub"), 0.8)


## Пункт приёма металлолома: кучи лома, весовая.
func _scrap(r: Rect2) -> void:
	_rec.draw_rect(r, Color("#6a6258"))
	for k in 7:
		var p := r.position + Vector2(_rng.randf_range(20, r.size.x - 20), _rng.randf_range(20, r.size.y - 30))
		var rad := _rng.randf_range(12, 26)
		_rec.draw_circle(p + Vector2(4, 5), rad, C_SHADOW)
		_rec.draw_circle(p, rad, Color("#6e5444"))
		_rec.draw_circle(p + Vector2(-rad * 0.2, -rad * 0.2), rad * 0.6, Color("#85705e"))
		for j in 4:
			var a := _rng.randf() * TAU
			_rec.draw_line(p, p + Vector2(cos(a), sin(a)) * rad * 0.8, Color("#4e4a46"), 1.5)
	_rec.draw_rect(Rect2(r.position.x + 6, r.end.y - 22, 40, 14), Color("#8a8c8d"))
	_label(Vector2(r.get_center().x, r.end.y - 14), _pick("scrap"), 0.8)


## Узкая полоса: пустырь с кустами и забором соседей.
func _strip(r: Rect2i) -> void:
	var rr := Rect2(Vector2(r.position) * T, Vector2(r.size) * T)
	_rec.draw_rect(rr, Color("#615f55"))
	var x := rr.position.x
	while x < rr.end.x:
		var seg := _rng.randf_range(4, 12) * T
		if _rng.randf() < 0.55:
			_trees(Rect2(x, rr.position.y + 6, minf(seg, rr.end.x - x), rr.size.y - 12), int(seg / T / 3.0) + 1)
		x += seg
	_rec.draw_line(Vector2(rr.position.x, rr.end.y - 4), Vector2(rr.end.x, rr.end.y - 4), Color("#8a8f92"), 2.0)
	var px := rr.position.x
	while px < rr.end.x:
		_rec.draw_line(Vector2(px, rr.end.y - 8), Vector2(px, rr.end.y), Color("#7a7f82"), 1.5)
		px += 24


## Пустырь с деревьями.
func _trees(r: Rect2, n: int) -> void:
	_rec.draw_rect(r.grow(-2), Color("#5f6a4a"))
	for k in n:
		var p := r.position + Vector2(_rng.randf_range(10, maxf(11.0, r.size.x - 10)), _rng.randf_range(10, maxf(11.0, r.size.y - 10)))
		var rad := _rng.randf_range(9, 17)
		_rec.draw_circle(p + Vector2(5, 6), rad, C_SHADOW)
		_rec.draw_circle(p, rad, Color("#4b5e3a"))
		_rec.draw_circle(p - Vector2(rad * 0.3, rad * 0.3), rad * 0.55, Color("#5c7146"))


## Железнодорожная ветка: щебень, шпалы, два рельса; через Цну (столбец rx) — ферменный мост.
func _rail(row: int, rx: int) -> void:
	var w := sim.world
	var y := row * T
	_rec.draw_rect(Rect2(-M * T, y - 6, (w.w + 2 * M) * T, T + 12), Color("#6e6a64"))
	var x := -M * T
	while x < (w.w + M) * T:
		_rec.draw_rect(Rect2(x, y, 6, T), Color("#5a4a3a"))
		x += 14.0
	_rec.draw_line(Vector2(-M * T, y + 8), Vector2((w.w + M) * T, y + 8), Color("#b9bcbe"), 2.5)
	_rec.draw_line(Vector2(-M * T, y + T - 8), Vector2((w.w + M) * T, y + T - 8), Color("#b9bcbe"), 2.5)
	var bx0 := (rx - 1) * T
	var bx1 := (rx + RIV_W + 1) * T
	_rec.draw_rect(Rect2(bx0, y + T + 6, bx1 - bx0, 14), Color(0, 0, 0, 0.3))
	for yy: float in [y - 8, y + T + 4]:
		_rec.draw_rect(Rect2(bx0, yy, bx1 - bx0, 4), Color("#5f6a72"))
		var tx := bx0
		while tx < bx1:
			_rec.draw_line(Vector2(tx, yy + 2), Vector2(tx + 16, yy + 2 + (6.0 if yy < y else -6.0)), Color("#7d8a92"), 2.0)
			tx += 16.0


## ЛЭП вдоль железной дороги: опоры и провода.
func _power_line(row: int) -> void:
	var w := sim.world
	var y := row * T
	var x := -M * T + 40.0
	var prev := Vector2.ZERO
	while x < (w.w + M) * T:
		var p := Vector2(x, y)
		_rec.draw_rect(Rect2(p - Vector2(7, 7) + Vector2(10, 12), Vector2(14, 14)), C_SHADOW)
		_rec.draw_rect(Rect2(p - Vector2(7, 7), Vector2(14, 14)), Color("#8a8f92"), false, 2.0)
		_rec.draw_line(p - Vector2(7, 7), p + Vector2(7, 7), Color("#8a8f92"), 1.0)
		_rec.draw_line(p + Vector2(-7, 7), p + Vector2(7, -7), Color("#8a8f92"), 1.0)
		_rec.draw_line(p - Vector2(16, 0), p + Vector2(16, 0), Color("#9a9fa2"), 2.0)
		if prev != Vector2.ZERO:
			for o: float in [-14.0, 0.0, 14.0]:
				_rec.draw_line(prev + Vector2(0, o * 0.3 - 1), p + Vector2(0, o * 0.3 - 1), Color(0.15, 0.15, 0.15, 0.5), 1.0)
		prev = p
		x += 9 * T
