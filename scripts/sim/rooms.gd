class_name Rooms
extends RefCounted
## Помещения: замкнутые области пола, ограниченные стенами, окнами и дверями.
## Назначение помещения выбирает игрок (слой world.zone), требования проверяются
## по объектам внутри. Пересчёт — только когда меняются стены, полы, объекты или назначения.

## Порядок важен: в сохранении помещение хранится номером в этом списке. Новые типы — только в конец.
const TYPES := ["workshop", "storage", "locker", "canteen", "wc", "restroom", "toolroom",
	"office", "foreman_office", "chief_office", "accounting", "supply_office", "pdo", "hr_office", "tech_office",
	"classroom", "compressor_room", "boiler_room", "union_office", "dorm", "medbay",
	"sales_office", "safety_office", "engineer_office", "legal_office", "director_office", "tech_room", "shower"]
## Порядок в каталоге помещений (для глаза, не для сохранений).
const UI_ORDER := ["workshop", "storage", "locker", "shower", "canteen", "wc", "restroom", "toolroom",
	"office", "director_office", "foreman_office", "chief_office", "accounting", "supply_office", "pdo", "hr_office", "tech_office",
	"sales_office", "safety_office", "engineer_office", "legal_office",
	"classroom", "compressor_room", "boiler_room", "tech_room", "union_office", "dorm", "medbay"]
const OFFICE_TYPES := ["office", "foreman_office", "chief_office", "accounting", "supply_office", "pdo", "hr_office", "tech_office",
	"sales_office", "safety_office", "engineer_office", "legal_office"]
const DIRS := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]


## Помещение как постройка: пол, обнесённый стенами. Внутри — одна или несколько зон (Room).
class Space:
	var id := 0
	var cells: Array[Vector2i] = []
	var windows := 0
	var doors := 0
	var rect := Rect2i()
	var rooms: Array[int] = []     ## зоны внутри (и неразмеченный остаток)
	var things: Array[int] = []


## Зона (1.12): связные клетки одного назначения внутри помещения. Неразмеченный остаток помещения —
## тоже Room, без типа. Окна, двери и свет — общие для всего помещения (space).
class Room:
	var id := 0
	var space := -1                ## номер помещения-постройки в Rooms.spaces
	var srect := Rect2i()          ## прямоугольник всего помещения (для кран-балки)
	var cells: Array[Vector2i] = []
	var type := ""                 ## "" — назначение не выбрано
	var valid := false             ## все требования выполнены
	var missing: Array[String] = []
	var things: Array[int] = []
	var windows := 0
	var doors := 0
	var rect := Rect2i()
	var center := Vector2.ZERO
	var tile_share := 0.0          ## доля кафельного пола
	var plants := 0
	var powered := false           ## есть подключённый кабель под напряжением
	var lit := false               ## светло: электричество или дневной свет из окон
	var lights_on := false         ## горят лампы (для расчёта нагрузки и картинки)

	func area() -> int:
		return cells.size()

	func title() -> String:
		if type == "":
			return "Помещение без назначения"
		return str(Defs.rooms.get(type, {}).get("name", type))

	## Оценка уюта 0–5: окна, растения, кафель, свет.
	func quality() -> int:
		var q := 0
		if windows > 0:
			q += 1
		if windows > 2:
			q += 1
		q += mini(plants, 2)
		if tile_share > 0.7:
			q += 1
		return clampi(q, 0, 5)


var sim: Sim
var room_of := PackedInt32Array()   ## индекс зоны в list для каждой клетки (-1 — не помещение)
var space_of := PackedInt32Array()  ## индекс помещения-постройки в spaces (-1 — улица)
var list: Array[Room] = []
var spaces: Array[Space] = []
var open_zones: Array = []          ## зоны, нарисованные не в помещении: [{type, cells, rect}] — только для предупреждений
var rev := 0                        ## растёт при каждом пересчёте (для отображения)
var _sig := ""


func _init(s: Sim) -> void:
	sim = s


func update() -> void:
	var w := sim.world
	sim.water.update()
	var sig := "%d|%d|%d|%d|%d" % [w.rev, sim.thing_rev, w.zone_rev, w.pipe_rev, sim.water.rev]
	if sig == _sig:
		return
	_sig = sig
	rebuild()


func _inner(c: Vector2i) -> bool:
	var w := sim.world
	return w.inb(c) and w.flr[w.idx(c)] > 0 and w.wall[w.idx(c)] == World.W_NONE


func rebuild() -> void:
	var w := sim.world
	var n := w.w * w.h
	room_of.resize(n)
	room_of.fill(-1)
	space_of.resize(n)
	space_of.fill(-1)
	list.clear()
	spaces.clear()
	open_zones.clear()
	var seen := PackedByteArray()
	seen.resize(n)
	seen.fill(0)
	# 1. помещения-постройки: пол, обнесённый стенами
	for i in n:
		if seen[i] != 0:
			continue
		var c0 := w.cell_of(i)
		if not _inner(c0):
			continue
		var cells: Array[Vector2i] = []
		var openings := {}
		var enclosed := true
		var queue: Array[Vector2i] = [c0]
		seen[i] = 1
		while not queue.is_empty():
			var c: Vector2i = queue.pop_back()
			cells.append(c)
			for d: Vector2i in DIRS:
				var nb := c + d
				if not w.inb(nb):
					enclosed = false
					continue
				var ni := w.idx(nb)
				if _inner(nb):
					if seen[ni] == 0:
						seen[ni] = 1
						queue.append(nb)
				elif w.wall[ni] == World.W_NONE:
					enclosed = false   # выход на улицу без стены
				else:
					openings[ni] = w.wall[ni]
		if not enclosed:
			_open_zones(cells)
			continue
		var sp := Space.new()
		sp.id = spaces.size()
		sp.cells = cells
		for v in openings.values():
			if v == World.W_WINDOW:
				sp.windows += 1
			elif WallKinds.is_door(v) or WallKinds.is_gate(v):
				sp.doors += 1
		var mn := cells[0]
		var mx := cells[0]
		for c in cells:
			mn = Vector2i(mini(mn.x, c.x), mini(mn.y, c.y))
			mx = Vector2i(maxi(mx.x, c.x), maxi(mx.y, c.y))
			space_of[w.idx(c)] = sp.id
		sp.rect = Rect2i(mn, mx - mn + Vector2i.ONE)
		spaces.append(sp)
	# 2. зоны внутри помещений: связные клетки одного назначения
	for sp2 in spaces:
		for c1 in sp2.cells:
			var i1 := w.idx(c1)
			if room_of[i1] >= 0:
				continue
			var z := int(w.zone[i1])
			var r := Room.new()
			r.id = list.size()
			r.space = sp2.id
			r.srect = sp2.rect
			r.windows = sp2.windows
			r.doors = sp2.doors
			if z > 0 and z <= TYPES.size():
				r.type = TYPES[z - 1]
			var q2: Array[Vector2i] = [c1]
			room_of[i1] = r.id
			var mn2 := c1
			var mx2 := c1
			var sum := Vector2.ZERO
			var tiles := 0
			while not q2.is_empty():
				var cc: Vector2i = q2.pop_back()
				r.cells.append(cc)
				mn2 = Vector2i(mini(mn2.x, cc.x), mini(mn2.y, cc.y))
				mx2 = Vector2i(maxi(mx2.x, cc.x), maxi(mx2.y, cc.y))
				sum += Vector2(cc) + Vector2(0.5, 0.5)
				if int(w.flr[w.idx(cc)]) in [2, 5, 6]:   # кафель и паркет — уютнее
					tiles += 1
				for d2: Vector2i in DIRS:
					var nb2: Vector2i = cc + d2
					if not w.inb(nb2):
						continue
					var ni2 := w.idx(nb2)
					if room_of[ni2] < 0 and space_of[ni2] == sp2.id and int(w.zone[ni2]) == z:
						room_of[ni2] = r.id
						q2.append(nb2)
			r.rect = Rect2i(mn2, mx2 - mn2 + Vector2i.ONE)
			r.center = sum / float(r.cells.size())
			r.tile_share = float(tiles) / float(r.cells.size())
			sp2.rooms.append(r.id)
			list.append(r)
	# объекты по зонам и помещениям
	for t: Thing in sim.things.values():
		if not t.built:
			continue
		for c in t.cells():
			if not w.inb(c):
				continue
			var ri := room_of[w.idx(c)]
			if ri >= 0:
				list[ri].things.append(t.id)
				spaces[list[ri].space].things.append(t.id)
				if t.def_id == "plant":
					list[ri].plants += 1
				break
	for r in list:
		_check(r)
	rev += 1


## Размеченные клетки вне помещения — показать предупреждение «нужны стены».
func _open_zones(cells: Array[Vector2i]) -> void:
	var w := sim.world
	var by := {}
	for c in cells:
		var z := int(w.zone[w.idx(c)])
		if z > 0 and z <= TYPES.size():
			if not by.has(z):
				by[z] = []
			(by[z] as Array).append(c)
	for z2 in by.keys():
		var cs: Array = by[z2]
		var mn: Vector2i = cs[0]
		var mx: Vector2i = cs[0]
		for c2: Vector2i in cs:
			mn = Vector2i(mini(mn.x, c2.x), mini(mn.y, c2.y))
			mx = Vector2i(maxi(mx.x, c2.x), maxi(mx.y, c2.y))
		open_zones.append({"type": TYPES[int(z2) - 1], "cells": cs, "rect": Rect2i(mn, mx - mn + Vector2i.ONE)})


func _check(r: Room) -> void:
	r.missing.clear()
	if r.type == "":
		r.valid = false
		return
	var def: Dictionary = Defs.rooms.get(r.type, {})
	var min_area := int(def.get("min_area", 1))
	if r.area() < min_area:
		var md := Rooms.min_dims(r.type)
		r.missing.append("помещение не меньше %d×%d клеток внутри (сейчас %d×%d)" % [md.x, md.y, r.rect.size.x, r.rect.size.y])
	var floors: Array[int] = []
	for f in def.get("floors", []):
		floors.append(int(f))
	if not floors.is_empty():
		var ok := 0
		for c in r.cells:
			if floors.has(int(sim.world.flr[sim.world.idx(c)])):
				ok += 1
		if float(ok) / float(r.area()) < 0.8:
			var names: Array[String] = []
			for f in floors:
				names.append(str(Defs.floor_by_id.get(int(f), {}).get("name", "пол")).to_lower())
			r.missing.append(" или ".join(names))
	var dry := false
	for need: Dictionary in def.get("needs", []):
		var n_req := int(need.get("n", 1))
		var ids: Array = need.get("ids", [])
		var kinds: Array = need.get("kinds", [])   # 1.16: «любой станок» — по виду объекта
		var cnt := 0
		for tid in r.things:
			var t: Thing = sim.things.get(tid)
			if t and (ids.has(t.def_id) or (not kinds.is_empty() and kinds.has(t.kind()))):
				if t.built and t.kind() != "pump" and t.kind() != "water_source" and not sim.water.has_water(t):
					dry = true
					continue
				cnt += maxi(1, int(t.def().get("seats", 1)))   # шкафчик на двоих — за два
		if cnt < n_req:
			r.missing.append(str(need.get("text", "")))
	if dry:
		r.missing.append("вода (протяните трубу от насоса)")
	r.valid = r.missing.is_empty()


func room_at(c: Vector2i) -> Room:
	var w := sim.world
	if not w.inb(c) or room_of.size() != w.w * w.h:
		return null
	var ri := room_of[w.idx(c)]
	return list[ri] if ri >= 0 and ri < list.size() else null


## Номер помещения-постройки в клетке (-1 — улица или незамкнутое).
func space_id_at(c: Vector2i) -> int:
	var w := sim.world
	if not w.inb(c) or space_of.size() != w.w * w.h:
		return -1
	return space_of[w.idx(c)]


func space_of_thing(t: Thing) -> int:
	for c in t.cells():
		var si := space_id_at(c)
		if si >= 0:
			return si
	return -1


## Все зоны помещения-постройки.
func space_rooms(si: int) -> Array[Room]:
	var out: Array[Room] = []
	if si < 0 or si >= spaces.size():
		return out
	for rid in spaces[si].rooms:
		out.append(list[rid])
	return out


## Главная зона помещения-постройки: самая большая с назначением (или просто самая большая).
func space_main(si: int) -> Room:
	var best: Room = null
	for r in space_rooms(si):
		if best == null or (r.type != "" and best.type == "") or (( r.type != "") == (best.type != "") and r.area() > best.area()):
			best = r
	return best


## Сколько объектов этого вида стоит во всём помещении-постройке.
func space_count(si: int, def_id: String) -> int:
	if si < 0 or si >= spaces.size():
		return 0
	var n := 0
	for tid in spaces[si].things:
		var t: Thing = sim.things.get(tid)
		if t and t.built and t.def_id == def_id:
			n += 1
	return n


func room_of_thing(t: Thing) -> Room:
	for c in t.cells():
		var r := room_at(c)
		if r:
			return r
	return null


## Объект стоит в правильно оборудованном помещении нужного типа?
## 1.13: в каких зонах объектом пользуются (пусто — где угодно). Станки — только в цехе,
## туалет — в туалете, шкафчик — в бытовке и т. д. (objects.json "zones").
static func zone_req(def_id: String) -> Array:
	var d: Dictionary = Defs.objects.get(def_id, {})
	if d.has("zones"):
		return d["zones"]
	if str(d.get("kind", "")) == "machine":
		return ["workshop"]
	return []


## Стоит ли объект в своей зоне (сама зона может быть ещё не до конца оборудована).
var legacy: Dictionary = {}    ## старые сохранения: id объектов, которым зона прощена (КТП на улице)


func zone_ok(t: Thing) -> bool:
	var req := zone_req(t.def_id)
	if req.is_empty() or legacy.has(t.id):
		return true
	var r := room_of_thing(t)
	return r != null and req.has(r.type)


## «Цех» или «Туалет или Медпункт» — для подсказок.
static func zone_names(def_id: String) -> String:
	var parts: Array[String] = []
	for z in zone_req(def_id):
		parts.append("«%s»" % str(Defs.rooms.get(str(z), {}).get("name", z)))
	return " или ".join(parts)


func thing_in(t: Thing, type: String) -> bool:
	var r := room_of_thing(t)
	return r != null and r.type == type and r.valid


func of_type(type: String, only_valid: bool = true) -> Array[Room]:
	var out: Array[Room] = []
	for r in list:
		if r.type == type and (r.valid or not only_valid):
			out.append(r)
	return out


## 1.18: наименьший размер помещения «Ш×Г» внутри стен (площадь — не меньше Ш·Г).
static func min_dims(type: String) -> Vector2i:
	var d: Dictionary = Defs.rooms.get(type, {})
	var ms: Array = d.get("min_size", [])
	if ms.size() == 2:
		return Vector2i(int(ms[0]), int(ms[1]))
	var a := maxi(1, int(d.get("min_area", 1)))
	var wv := int(ceil(sqrt(float(a))))
	return Vector2i(wv, int(ceil(float(a) / float(wv))))


## Назначить тип помещению (пустая строка — снять назначение).
## Требования типа помещения одной строкой: площадь, пол, обязательные объекты.
static func req_text(type: String) -> String:
	var d: Dictionary = Defs.rooms.get(type, {})
	var md := Rooms.min_dims(type)
	var parts: Array[String] = ["помещение от %d×%d клеток внутри" % [md.x, md.y]]
	var floors: Array = d.get("floors", [])
	if not floors.is_empty():
		parts.append("пол: " + str(Defs.floor_by_id.get(int(floors[0]), {}).get("name", "пол")).to_lower())
	for n: Dictionary in d.get("needs", []):
		parts.append(str(n.get("text", "")))
	return ", ".join(parts)


## Сохранение 1.10: четыре новых кабинета стояли в середине списка типов — переставить номера.
static func migrate_zones_v8(sim: Sim) -> void:
	var w := sim.world
	var is110 := false
	for i in w.zone.size():
		if w.zone[i] > 21:
			is110 = true
			break
	if not is110:
		for t: Thing in sim.things.values():
			if t.def_id in ["phone_stand", "safety_stand", "law_shelf"]:
				is110 = true
				break
	if not is110:
		return
	var remap := {16: 22, 17: 23, 18: 24, 19: 25, 20: 16, 21: 17, 22: 18, 23: 19, 24: 20, 25: 21}
	for i2 in w.zone.size():
		var z := int(w.zone[i2])
		if remap.has(z):
			w.zone[i2] = int(remap[z])
	w.zone_rev += 1


## Сохранение до 1.13: зоны стали обязательными. Объект вне своей зоны получает маленькую
## зону по себе (и по месту, где у него стоят), чтобы старый завод не встал.
static func migrate_zones_v9(sim: Sim) -> int:
	sim.rooms.update()
	var n := 0
	for t: Thing in sim.things.values():
		if not t.built or sim.rooms.zone_ok(t):
			continue
		var req := zone_req(t.def_id)
		if req.is_empty():
			continue
		if sim.rooms.room_of_thing(t) == null:
			sim.rooms.legacy[t.id] = true   # стоит на улице (подстанция) — пусть работает как раньше
			continue
		var cells: Array[Vector2i] = t.cells()
		for sp: Dictionary in t.spots():
			cells.append(sp["cell"])
		var z := TYPES.find(str(req[0])) + 1
		for c in cells:
			if sim.rooms._inner(c):
				sim.world.zone[sim.world.idx(c)] = z
		n += 1
	# напор воды: если приборов уже больше, чем тянет городской ввод, — запас, чтобы не пересохло
	sim.water.update()
	var most := 0
	for f in sim.water.net_fix:
		most = maxi(most, f)
	if most > Water.CITY_FIXTURES:
		sim.water.bonus = most - Water.CITY_FIXTURES
		sim.water._sig = ""
	if n > 0:
		sim.world.zone_rev += 1
		sim.rooms.update()
		sim.notify("Зоны стали обязательными: станком работают только в цехе, туалетом пользуются в зоне «Туалет» и т. д. Для %d объектов вне своих зон разметили маленькие зоны — поправьте их (меню «Зоны»)." % n, Sim.LVL_INFO)
	return n


func assign(r: Room, type: String) -> void:
	var w := sim.world
	var z := 0
	if type != "":
		z = TYPES.find(type) + 1
	for c in r.cells:
		w.zone[w.idx(c)] = z
	w.zone_rev += 1
	update()


## Разметить зону прямоугольником (1.12): только клетки пола внутри стен; "" — стереть разметку.
func paint(rect: Rect2i, type: String) -> int:
	var w := sim.world
	var z := 0 if type == "" else TYPES.find(type) + 1
	var n := 0
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var c := Vector2i(x, y)
			if not _inner(c):
				continue
			var i := w.idx(c)
			if int(w.zone[i]) != z:
				w.zone[i] = z
				n += 1
	if n > 0:
		w.zone_rev += 1
		update()
	return n


## 1.17: разметить отдельные клетки (план) — одно обновление на все.
func paint_cells(cells: Array, type: String) -> int:
	var w := sim.world
	var z := 0 if type == "" else TYPES.find(type) + 1
	var n := 0
	for c: Vector2i in cells:
		if not _inner(c):
			continue
		var i := w.idx(c)
		if int(w.zone[i]) != z:
			w.zone[i] = z
			n += 1
	if n > 0:
		w.zone_rev += 1
		update()
	return n


## Залить зону, как ведром: связные клетки помещения с той же разметкой, что под курсором.
func fill(c: Vector2i, type: String) -> int:
	var w := sim.world
	if not _inner(c):
		return 0
	var z := 0 if type == "" else TYPES.find(type) + 1
	var from := int(w.zone[w.idx(c)])
	if from == z:
		return 0
	var n := 0
	var q: Array[Vector2i] = [c]
	var seen := {w.idx(c): true}
	while not q.is_empty():
		var cc: Vector2i = q.pop_back()
		w.zone[w.idx(cc)] = z
		n += 1
		for d: Vector2i in DIRS:
			var nb: Vector2i = cc + d
			if not _inner(nb):
				continue
			var ni := w.idx(nb)
			if seen.has(ni) or int(w.zone[ni]) != from:
				continue
			seen[ni] = true
			q.append(nb)
	w.zone_rev += 1
	update()
	return n


## Светло ли в клетке: помещение со светом, или улица днём.
func is_lit(c: Vector2i) -> bool:
	return sim.power.cell_lit(c)
