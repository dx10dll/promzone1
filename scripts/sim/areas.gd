class_name Areas
extends RefCounted
## 1.40: свои места у людей и логистика быта.
## — Рабочие не гуляют по кабинетам, конторские (ИТР, директор) не болтаются в цеху: отдыхают, обедают и стоят
##   без дела в своей зоне. Зайти в чужую — только по делу (мастер обходит участок, директор — цех, туалет, курилка).
## — Какой цех к какой бытовке, душевой, туалету, столовой и комнате отдыха относится и куда ходят ИТР — выбирает
##   игрок (окно «Логистика быта»). Не выбрано — ближайшее, как раньше.
## — Столовая может быть «для ИТР»: рабочие туда не ходят.
## — Часть людей носит обед с собой и ест на рабочем месте (за своим столом, у станка или верстака).
## Помещение запоминается клеткой-якорем (его верхняя левая клетка): номер зоны меняется при каждой перестройке.

## Что назначается цеху.
const KINDS := ["locker", "shower", "wc", "canteen", "restroom"]
## Что назначается ИТР и конторе.
const ITR_KINDS := ["canteen", "wc", "restroom"]
## Производственные зоны: конторским сюда — только по делу.
const SHOP_ZONES := ["workshop", "storage", "toolroom", "compressor_room", "boiler_room", "tech_room"]
## Кто из конторских по работе ходит по цеху.
const SHOP_ITR := ["foreman", "chief", "technologist", "safety_engineer", "chief_engineer"]
## Сколько людей носит обед из дома (%).
const LUNCHBOX_WORKER := 22
const LUNCHBOX_ITR := 35

var sim: Sim
var links: Dictionary = {}          ## якорь цеха "x,y" -> {вид: якорь помещения}
var itr: Dictionary = {}            ## вид -> якорь помещения (для ИТР и конторы)
var itr_canteens: Dictionary = {}   ## якорь столовой -> true: столовая для ИТР
var rev := 0                        ## растёт при каждом изменении (для окна)
var _key_rev := -1
var _keys: Dictionary = {}          ## номер зоны -> якорь (сбрасывается при пересчёте помещений)
static var _office_z := PackedByteArray()


func _init(s: Sim) -> void:
	sim = s


# ================================================================ зоны

## Конторская зона (кабинеты, контора, кабинет директора) — по группе в rooms.json.
static func is_office_type(type: String) -> bool:
	return type != "" and str(Defs.rooms.get(type, {}).get("group", "")) == "office"


## Табличка «конторская ли зона» по номеру из world.zone (0 — нет).
static func office_table() -> PackedByteArray:
	if _office_z.size() != Rooms.TYPES.size() + 1:
		_office_z.resize(Rooms.TYPES.size() + 1)
		_office_z.fill(0)
		for i in Rooms.TYPES.size():
			if is_office_type(str(Rooms.TYPES[i])):
				_office_z[i + 1] = 1
	return _office_z


func _zone_type(c: Vector2i) -> String:
	var w := sim.world
	if not w.inb(c) or w.zone.size() != w.w * w.h:
		return ""
	var z := int(w.zone[w.idx(c)])
	return str(Rooms.TYPES[z - 1]) if z > 0 and z <= Rooms.TYPES.size() else ""


## Можно ли человеку стоять без дела, отдыхать или обедать в этой клетке.
func own_area_ok(w: Worker, c: Vector2i) -> bool:
	var t := _zone_type(c)
	if t == "":
		return true
	if w.is_itr():
		return not SHOP_ZONES.has(t) or SHOP_ITR.has(w.prof)
	return not is_office_type(t)


# ================================================================ якоря

static func key_of_cell(c: Vector2i) -> String:
	return "%d,%d" % [c.x, c.y]


static func cell_of_key(k: String) -> Vector2i:
	var p := k.split(",")
	if p.size() != 2:
		return Vector2i(-1, -1)
	return Vector2i(int(p[0]), int(p[1]))


## Якорь зоны: верхняя левая клетка (по строкам, потом по столбцам).
func key_of(r: Rooms.Room) -> String:
	if r == null or r.cells.is_empty():
		return ""
	if _key_rev != sim.rooms.rev:
		_key_rev = sim.rooms.rev
		_keys.clear()
	if _keys.has(r.id):
		return str(_keys[r.id])
	var best := r.cells[0]
	for c in r.cells:
		if c.y < best.y or (c.y == best.y and c.x < best.x):
			best = c
	var k := key_of_cell(best)
	_keys[r.id] = k
	return k


## Зона по якорю, если она всё ещё нужного типа.
func room_by_key(k: String, type: String) -> Rooms.Room:
	if k == "":
		return null
	var r := sim.rooms.room_at(cell_of_key(k))
	if r == null or r.type != type:
		return null
	return r


# ================================================================ назначения

## Цех человека: где его станок или верстак, иначе цех, где он сейчас.
func home_shop(w: Worker) -> Rooms.Room:
	var m: Thing = sim.things.get(w.workplace)
	if m:
		var r := sim.rooms.room_of_thing(m)
		if r and r.type == "workshop":
			return r
	var r2 := sim.rooms.room_at(w.cell())
	if r2 and r2.type == "workshop":
		return r2
	return null


## Назначенное человеку помещение этого вида (null — не назначено, идёт в ближайшее).
func linked(w: Worker, kind: String) -> Rooms.Room:
	if links.is_empty() and itr.is_empty():
		return null
	var k := ""
	if w.is_itr():
		k = str(itr.get(kind, ""))
	else:
		var shop := home_shop(w)
		if shop == null:
			return null
		k = str((links.get(key_of(shop), {}) as Dictionary).get(kind, ""))
	return room_by_key(k, kind)


## Поправка к расстоянию: объект в назначенном помещении — сильно ближе.
func pref(w: Worker, t: Thing, kind: String) -> float:
	var r := linked(w, kind)
	if r == null:
		return 0.0
	var tr := sim.rooms.room_of_thing(t)
	return -500.0 if tr != null and tr.id == r.id else 0.0


func set_link(shop: Rooms.Room, kind: String, target: Rooms.Room) -> void:
	var sk := key_of(shop)
	if sk == "":
		return
	var d: Dictionary = links.get(sk, {})
	if target == null:
		d.erase(kind)
	else:
		d[kind] = key_of(target)
	if d.is_empty():
		links.erase(sk)
	else:
		links[sk] = d
	rev += 1


func link_of(shop: Rooms.Room, kind: String) -> Rooms.Room:
	return room_by_key(str((links.get(key_of(shop), {}) as Dictionary).get(kind, "")), kind)


func set_itr(kind: String, target: Rooms.Room) -> void:
	if target == null:
		itr.erase(kind)
	else:
		itr[kind] = key_of(target)
	rev += 1


func itr_of(kind: String) -> Rooms.Room:
	return room_by_key(str(itr.get(kind, "")), kind)


## Столовая только для ИТР.
func is_itr_canteen(r: Rooms.Room) -> bool:
	return r != null and r.type == "canteen" and itr_canteens.has(key_of(r))


func set_itr_canteen(r: Rooms.Room, on: bool) -> void:
	if r == null:
		return
	if on:
		itr_canteens[key_of(r)] = true
	else:
		itr_canteens.erase(key_of(r))
	rev += 1


## Может ли человек обедать в этой столовой (null — не столовая: можно).
func canteen_ok(w: Worker, r: Rooms.Room) -> bool:
	if r == null or r.type != "canteen" or itr_canteens.is_empty():
		return true
	return w.is_itr() or not is_itr_canteen(r)


## Поправка к расстоянию до стула в столовой: своя столовая ближе, ИТР — к своей.
func canteen_pref(w: Worker, r: Rooms.Room) -> float:
	if r == null or r.type != "canteen":
		return 0.0
	var lk := linked(w, "canteen")
	if lk != null:
		return -500.0 if lk.id == r.id else 0.0
	if w.is_itr() and is_itr_canteen(r):
		return -60.0
	return 0.0


## Носит обед из дома (по номеру человека — без кубика, сим не меняется).
static func brings_lunch(w: Worker) -> bool:
	var h := absi(w.id * 2654435 + 977) % 100
	return h < (LUNCHBOX_ITR if w.is_itr() else LUNCHBOX_WORKER)


## 1.40: оверлей «Логистика» — список связей для рисования: {src, dst, kind, itr}. Порядок детерминирован.
func link_list() -> Array:
	var out: Array = []
	var offices: Array[Rooms.Room] = []
	for r in sim.rooms.list:
		if r.type == "workshop":
			for kind: String in KINDS:
				var t := link_of(r, kind)
				if t != null:
					out.append({"src": r, "dst": t, "kind": kind, "itr": false})
		elif is_office_type(r.type):
			offices.append(r)
	for kind2: String in ITR_KINDS:
		var t2 := itr_of(kind2)
		if t2 == null:
			continue
		for o in offices:
			out.append({"src": o, "dst": t2, "kind": kind2, "itr": true})
	return out


## Протянули линию от цеха/конторы к помещению. Вид — по типу цели. Возвращает вид или "" (нельзя).
func drag_link(src: Rooms.Room, dst: Rooms.Room) -> String:
	if src == null or dst == null or src.id == dst.id:
		return ""
	var kind := dst.type
	if not KINDS.has(kind):
		return ""
	if src.type == "workshop":
		set_link(src, kind, dst)
		return kind
	if is_office_type(src.type) and ITR_KINDS.has(kind):
		set_itr(kind, dst)
		return kind
	return ""


## Убрать связь цеха (или группы ИТР) по виду.
func unlink(src: Rooms.Room, kind: String, is_itr: bool) -> void:
	if is_itr:
		set_itr(kind, null)
	else:
		set_link(src, kind, null)


## Все зоны этого типа (оборудованные) — для выбора в окне.
func rooms_of(type: String) -> Array[Rooms.Room]:
	return sim.rooms.of_type(type, false)


# ================================================================ сохранение

func to_dict() -> Dictionary:
	return {"links": links, "itr": itr, "itr_canteens": itr_canteens.keys()}


func from_dict(d: Dictionary) -> void:
	links.clear()
	itr.clear()
	itr_canteens.clear()
	var ld: Variant = d.get("links", {})
	if ld is Dictionary:
		for k in (ld as Dictionary).keys():
			var v: Variant = ld[k]
			if v is Dictionary:
				links[str(k)] = (v as Dictionary).duplicate()
	var id: Variant = d.get("itr", {})
	if id is Dictionary:
		for k2 in (id as Dictionary).keys():
			itr[str(k2)] = str(id[k2])
	for k3 in d.get("itr_canteens", []):
		itr_canteens[str(k3)] = true
	rev += 1
