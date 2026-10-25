class_name World
extends RefCounted
## Сетка участка: грунт, полы, стены, чертежи, проходимость и поиск пути.

const T := 32.0 ## размер тайла в мировых единицах

enum Ground { DIRT, ASPHALT, ROAD, SIDEWALK, GRASS }
const W_NONE := 0
const W_BRICK := 1
const W_WINDOW := 2
const W_DOOR := 3
const W_GATE := 4
const W_FENCE := 5
const W_FENCE_GATE := 6
const W_CONCRETE := 7         ## 1.12: бетонная стена
const W_SANDWICH := 8         ## сэндвич-панель
const W_PARTITION := 9        ## перегородка из гипсокартона
const W_METAL_DOOR := 10      ## металлическая дверь
const W_SILICATE := 11        ## 1.21: белый силикатный кирпич
const W_GASBLOCK := 12        ## 1.21: газобетонные блоки
const W_GLASS_DOOR := 13      ## 1.21: остеклённая дверь (контора, кабинеты)
const W_GATE_WARM := 14       ## 1.21: утеплённые ворота (синие сэндвич-секции)
const W_DOOR_BROWN := 15      ## 1.40: простая коричневая дверь (цеха, склады)
const W_DOOR_GREEN := 16      ## 1.40: зелёная филёнчатая дверь (хорошие кабинеты)
const BP_NONE := 255

var w := 0
var h := 0
var ground := PackedByteArray()
var flr := PackedByteArray()
var wall := PackedByteArray()
var bp_floor := PackedByteArray()
var bp_wall := PackedByteArray()
var block := PackedInt32Array() ## id объекта, перекрывающего клетку (-1 нет)
var occ := PackedInt32Array()   ## id любого объекта в клетке (-1 нет)
var cable := PackedByteArray()  ## 1 — проложен кабель, 2 — чертёж (1.13: сети прокладывают рабочие)
var zone := PackedByteArray()   ## назначение помещения: 0 нет, иначе индекс в Rooms.TYPES + 1
var area := PackedByteArray()   ## зоны на земле: 0 нет, 1 — разгрузка
var pipe := PackedByteArray()   ## 1 — проложена труба водопровода
var duct := PackedByteArray()   ## 1 — воздуховод вентиляции
var air := PackedByteArray()    ## 1 — пневмомагистраль (сжатый воздух)
var flora := PackedByteArray()  ## 1.13: 0 нет, 1–3 — деревья (тополь, берёза, клён), 4–5 — кусты
var flora_rev := 0
## 1.13: соседние участки справа от своего: [{x0, w, price, bought}]. Купленный участок
## прибавляется к plot, забор между участками можно снести.
var lots: Array = []
var owned := PackedByteArray()  ## 1.13: своя земля (1); пусто — свой весь plot
var area_rev := 0
var pipe_rev := 0
var duct_rev := 0
var air_rev := 0
var cable_rev := 0
var zone_rev := 0
var astar := AStarGrid2D.new()
var rev := 0
var plot := Rect2i(1, 1, 46, 28) ## где можно строить
var sidewalk_row := 30
var road_row := 32


func setup(width: int, height: int) -> void:
	w = width
	h = height
	var n := w * h
	# Packed-массивы копируются по значению, поэтому каждый настраиваем отдельно.
	ground.resize(n)
	ground.fill(0)
	flr.resize(n)
	flr.fill(0)
	wall.resize(n)
	wall.fill(0)
	bp_floor.resize(n)
	bp_floor.fill(BP_NONE)
	bp_wall.resize(n)
	bp_wall.fill(BP_NONE)
	block.resize(n)
	block.fill(-1)
	occ.resize(n)
	occ.fill(-1)
	cable.resize(n)
	cable.fill(0)
	zone.resize(n)
	zone.fill(0)
	area.resize(n)
	area.fill(0)
	pipe.resize(n)
	pipe.fill(0)
	duct.resize(n)
	duct.fill(0)
	air.resize(n)
	air.fill(0)
	flora.resize(n)
	flora.fill(0)
	_setup_astar()


func _setup_astar() -> void:
	astar = AStarGrid2D.new()
	astar.region = Rect2i(0, 0, w, h)
	astar.cell_size = Vector2(1, 1)
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.update()


func idx(c: Vector2i) -> int:
	return c.y * w + c.x


func cell_of(i: int) -> Vector2i:
	return Vector2i(i % w, int(i / w))


func inb(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < w and c.y < h


func in_plot(c: Vector2i) -> bool:
	if not plot.has_point(c):
		return false
	if owned.size() == w * h:
		return owned[c.y * w + c.x] != 0
	return true


func get_wall(c: Vector2i) -> int:
	return wall[idx(c)] if inb(c) else W_NONE


func get_floor(c: Vector2i) -> int:
	return flr[idx(c)] if inb(c) else 0


func passable(c: Vector2i) -> bool:
	if not inb(c):
		return false
	var i := idx(c)
	return not Defs.wall_solid(wall[i]) and block[i] < 0 and flora[i] == 0


## Дерево или куст в клетке (1.13).
func flora_at(c: Vector2i) -> int:
	return flora[idx(c)] if inb(c) else 0


static func flora_name(v: int) -> String:
	return ["", L.t("тополь"), L.t("берёза"), L.t("клён"), L.t("куст сирени"), L.t("куст шиповника")][clampi(v, 0, 5)]


## Свой забор: внутри участка (остался от границы до покупки соседнего) или по краю своей земли.
## 1.23: начальный забор вокруг участка тоже можно снести (кроме края карты).
func inner_fence(c: Vector2i) -> bool:
	var v := get_wall(c)
	if v != W_FENCE and v != W_FENCE_GATE:
		return false
	if in_plot(c):
		return true
	if c.x <= 0 or c.y <= 0 or c.x >= w - 1 or c.y >= h - 1:
		return false
	for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		if in_plot(c + d):
			return true
	return false


func is_door(c: Vector2i) -> bool:
	var v := get_wall(c)
	return v == W_DOOR or v == W_METAL_DOOR or v == W_GLASS_DOOR or v == W_DOOR_BROWN or v == W_DOOR_GREEN or v == W_GATE or v == W_GATE_WARM or v == W_FENCE_GATE


func is_indoor(c: Vector2i) -> bool:
	return get_floor(c) > 0


func has_cable(c: Vector2i) -> bool:
	return inb(c) and cable[idx(c)] == 1


func has_pipe(c: Vector2i) -> bool:
	return inb(c) and pipe[idx(c)] == 1


func has_duct(c: Vector2i) -> bool:
	return inb(c) and duct[idx(c)] == 1


func has_air(c: Vector2i) -> bool:
	return inb(c) and air[idx(c)] == 1


## Слой сети по имени: cable, pipe, duct, air.
func net_layer(layer: String) -> PackedByteArray:
	match layer:
		"pipe":
			return pipe
		"duct":
			return duct
		"air":
			return air
	return cable


func net_set(layer: String, i: int, v: int) -> void:
	match layer:
		"pipe":
			pipe[i] = v
			pipe_rev += 1
		"duct":
			duct[i] = v
			duct_rev += 1
		"air":
			air[i] = v
			air_rev += 1
		_:
			cable[i] = v
			cable_rev += 1


## Сеть в клетке: 0 — нет, 1 — проложена, 2 — чертёж.
func net_at(layer: String, c: Vector2i) -> int:
	if not inb(c):
		return 0
	return net_layer(layer)[idx(c)]


func lot_bought(k: int) -> bool:
	return k >= 0 and k < lots.size() and bool(lots[k].get("bought", false))


func lot_rect(k: int) -> Rect2i:
	var a: Array = lots[k].get("rect", [0, 0, 0, 0])
	return Rect2i(int(a[0]), int(a[1]), int(a[2]), int(a[3]))


## Сторона участка: «справа», «слева», «сзади».
func lot_side(k: int) -> String:
	var r := lot_rect(k)
	if r.position.y < plot.position.y - 1 or (r.end.y < plot.position.y):
		return L.t("сзади")
	return L.t("слева") if r.end.x <= plot.position.x else L.t("справа")


## Купить участок: его земля и общий с ним забор становятся своими.
func own_lot(k: int) -> void:
	var n := w * h
	if owned.size() != n:
		owned.resize(n)
		owned.fill(0)
		for y in range(plot.position.y, plot.end.y):
			for x in range(plot.position.x, plot.end.x):
				owned[y * w + x] = 1
	var r := lot_rect(k)
	var before := owned.duplicate()
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			owned[y * w + x] = 1
	# забор между участком и своей землёй — тоже свой (его можно снести)
	for y2 in range(r.position.y - 1, r.end.y + 1):
		for x2 in range(r.position.x - 1, r.end.x + 1):
			var c := Vector2i(x2, y2)
			if not inb(c) or r.has_point(c):
				continue
			var v := wall[idx(c)]
			if v != W_FENCE:
				continue
			for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var nb := c + d
				if inb(nb) and before[idx(nb)] != 0 and not r.has_point(nb):
					owned[idx(c)] = 1
					break
	# углы, где сходятся заборы: если вокруг всё своё — тоже своё
	for y3 in range(r.position.y - 1, r.end.y + 1):
		for x3 in range(r.position.x - 1, r.end.x + 1):
			var c3 := Vector2i(x3, y3)
			if not inb(c3) or owned[idx(c3)] != 0:
				continue
			var mine := 0
			for d2: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var nb2 := c3 + d2
				if inb(nb2) and owned[idx(nb2)] != 0:
					mine += 1
			if mine >= 3:
				owned[idx(c3)] = 1
	# plot — рамка вокруг всей своей земли
	var mn := Vector2i(w, h)
	var mx := Vector2i(-1, -1)
	for i in n:
		if owned[i] != 0:
			var cc := cell_of(i)
			mn = Vector2i(mini(mn.x, cc.x), mini(mn.y, cc.y))
			mx = Vector2i(maxi(mx.x, cc.x), maxi(mx.y, cc.y))
	plot = Rect2i(mn, mx - mn + Vector2i.ONE)
	lots[k]["bought"] = true
	rev += 1


## Перенести карту в середину большей (1.13): всё сдвигается на (ox, oy).
func embed(ox: int, oy: int, nw: int, nh: int) -> void:
	var ow := w
	var oh := h
	# packed-массивы в словаре и в переменных — ссылки: setup() их обнулит, поэтому копии
	var old := {"ground": ground.duplicate(), "flr": flr.duplicate(), "wall": wall.duplicate(), "bp_floor": bp_floor.duplicate(),
		"bp_wall": bp_wall.duplicate(), "cable": cable.duplicate(), "zone": zone.duplicate(), "area": area.duplicate(),
		"pipe": pipe.duplicate(), "duct": duct.duplicate(), "air": air.duplicate(), "flora": flora.duplicate()}
	var oblock := block.duplicate()
	var oocc := occ.duplicate()
	var oclimb := climb.duplicate()
	setup(nw, nh)
	climb.clear()
	for ci in oclimb.keys():
		var cc0 := Vector2i(int(ci) % ow, int(ci) / ow)
		climb[(cc0.y + oy) * nw + cc0.x + ox] = oclimb[ci]
	for k: String in old.keys():
		var src: PackedByteArray = old[k]
		var dst := PackedByteArray()
		dst.resize(nw * nh)
		dst.fill(BP_NONE if k == "bp_floor" or k == "bp_wall" else 0)
		for y in oh:
			for x in ow:
				dst[(y + oy) * nw + x + ox] = src[y * ow + x]
		set(k, dst)
	for y2 in oh:
		for x2 in ow:
			block[(y2 + oy) * nw + x2 + ox] = oblock[y2 * ow + x2]
			occ[(y2 + oy) * nw + x2 + ox] = oocc[y2 * ow + x2]
	plot = Rect2i(plot.position + Vector2i(ox, oy), plot.size)
	sidewalk_row += oy
	road_row += oy
	owned.resize(nw * nh)
	owned.fill(0)
	for y3 in range(plot.position.y, plot.end.y):
		for x3 in range(plot.position.x, plot.end.x):
			owned[y3 * nw + x3] = 1
	rev += 1
	cable_rev += 1
	pipe_rev += 1
	duct_rev += 1
	air_rev += 1
	area_rev += 1
	zone_rev += 1
	flora_rev += 1


func refresh_cell(c: Vector2i) -> void:
	if not inb(c):
		return
	astar.set_point_solid(c, not passable(c))
	astar.set_point_weight_scale(c, _weight(c))
	rev += 1


## 1.40: дверь чуть «дороже» прохода; кабинеты и контора — заметно: через чужой кабинет не срезают, если есть коридор.
const OFFICE_W := 3.0
const CLIMB_W := 6.0          ## 1.47: цена клетки с низким объектом (поддон) в поиске пути: перелезают, только если иначе не пройти
const CLIMB_SPEED := 0.45     ## 1.47: скорость шага по такой клетке
var climb := {}               ## 1.47: индекс клетки -> id низкого объекта на ней (не сохраняется: собирается при загрузке)
var _zw_rev := -1


func _weight(c: Vector2i) -> float:
	if climb.has(idx(c)):
		return CLIMB_W
	if is_door(c):
		return 1.6
	if zone.size() == w * h:
		var z := int(zone[idx(c)])
		var tb := Areas.office_table()
		if z > 0 and z < tb.size() and tb[z] == 1:
			return OFFICE_W
	return 1.0


## Пересчитать «цену» клеток после смены разметки зон (зовёт Rooms при пересчёте).
func zone_weights() -> void:
	if _zw_rev == zone_rev:
		return
	_zw_rev = zone_rev
	for y in h:
		for x in w:
			var c := Vector2i(x, y)
			astar.set_point_weight_scale(c, _weight(c))


func refresh_all() -> void:
	_setup_astar()
	for y in h:
		for x in w:
			refresh_cell(Vector2i(x, y))


## Путь от a до b (включая обе клетки). Пустой массив — пути нет.
func find_path(a: Vector2i, b: Vector2i) -> Array[Vector2i]:
	var empty: Array[Vector2i] = []
	if not inb(a) or not inb(b):
		return empty
	if a == b:
		return [a]
	if not passable(b):
		return empty
	var start_solid := astar.is_point_solid(a)
	if start_solid:
		astar.set_point_solid(a, false)
	var p: Array[Vector2i] = astar.get_id_path(a, b)
	if start_solid:
		astar.set_point_solid(a, true)
	return p


func reachable(a: Vector2i, b: Vector2i) -> bool:
	return a == b or not find_path(a, b).is_empty()


## Ближайшая проходимая клетка (поиск по спирали).
func nearest_passable(c: Vector2i, max_r: int = 6) -> Vector2i:
	if passable(c):
		return c
	for r in range(1, max_r + 1):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if absi(dx) != r and absi(dy) != r:
					continue
				var n := c + Vector2i(dx, dy)
				if passable(n):
					return n
	return Vector2i(-1, -1)


func to_dict() -> Dictionary:
	return {
		"w": w, "h": h,
		"ground": Marshalls.raw_to_base64(ground),
		"floor": Marshalls.raw_to_base64(flr),
		"wall": Marshalls.raw_to_base64(wall),
		"bp_floor": Marshalls.raw_to_base64(bp_floor),
		"bp_wall": Marshalls.raw_to_base64(bp_wall),
		"cable": Marshalls.raw_to_base64(cable),
		"zone": Marshalls.raw_to_base64(zone),
		"area": Marshalls.raw_to_base64(area),
		"pipe": Marshalls.raw_to_base64(pipe),
		"duct": Marshalls.raw_to_base64(duct),
		"air": Marshalls.raw_to_base64(air),
		"flora": Marshalls.raw_to_base64(flora), "lots": lots, "owned": Marshalls.raw_to_base64(owned) if owned.size() > 0 else "",
		"plot": [plot.position.x, plot.position.y, plot.size.x, plot.size.y], "sw": sidewalk_row, "road": road_row,
	}


func from_dict(d: Dictionary) -> void:
	setup(int(d["w"]), int(d["h"]))
	ground = Marshalls.base64_to_raw(str(d["ground"]))
	flr = Marshalls.base64_to_raw(str(d["floor"]))
	wall = Marshalls.base64_to_raw(str(d["wall"]))
	bp_floor = Marshalls.base64_to_raw(str(d["bp_floor"]))
	bp_wall = Marshalls.base64_to_raw(str(d["bp_wall"]))
	if d.has("cable"):
		cable = Marshalls.base64_to_raw(str(d["cable"]))
	if d.has("zone"):
		zone = Marshalls.base64_to_raw(str(d["zone"]))
	if d.has("area"):
		area = Marshalls.base64_to_raw(str(d["area"]))
	if d.has("pipe"):
		pipe = Marshalls.base64_to_raw(str(d["pipe"]))
	if d.has("duct"):
		duct = Marshalls.base64_to_raw(str(d["duct"]))
	if d.has("air"):
		air = Marshalls.base64_to_raw(str(d["air"]))
	if d.has("flora"):
		flora = Marshalls.base64_to_raw(str(d["flora"]))
	if flora.size() != w * h:
		flora.resize(w * h)
		flora.fill(0)
	lots = d.get("lots", [])
	var ows := str(d.get("owned", ""))
	owned = Marshalls.base64_to_raw(ows) if ows != "" else PackedByteArray()
	if owned.size() != w * h:
		owned = PackedByteArray()
	if d.has("plot"):
		var pl: Array = d["plot"]
		plot = Rect2i(int(pl[0]), int(pl[1]), int(pl[2]), int(pl[3]))
		sidewalk_row = int(d.get("sw", 30))
		road_row = int(d.get("road", 32))
