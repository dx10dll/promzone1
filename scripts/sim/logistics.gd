class_name Logistics
extends RefCounted
## Логистика оборудования и разгрузки.
## — Зона разгрузки (слой world.area): сюда разгружают фургоны — металл и ящики с оборудованием.
## — Оборудование не берётся из ниоткуда: купленный станок или шкафчик привозят фургоном.
##   Крупное — в нескольких ящиках (каждый несёт один человек), мелочь (цветок, стул, чайник) несут в руках.
##   Когда все ящики у места установки — рабочие собирают объект.
## — Склад оборудования: демонтированное и неустановленное лежит в ящиках в помещении «Склад»
##   (или в зоне разгрузки), пока не понадобится. Поставили такой же объект — возьмут со склада бесплатно.
## — 1.29: обе зоны обязательны (последнюю клетку не стереть). Металл из фургона кладут на «Поддоны
##   заготовок» в зоне разгрузки (нет места — на пол зоны), оттуда — к станкам и на стеллажи.
##   Готовые детали лежат на поддонах готовой продукции; заказ готов — их несут (или везут
##   погрузчиком) в зону отгрузки, и машина клиента грузит только оттуда.

const A_UNLOAD := 1
const A_SHIP := 2                ## зона отгрузки (1.12): готовые заказы ждут машину клиента
const MAT_PER_CELL := 24
const RAW_PALLET := "pallet_raw"   ## 1.29: поддон заготовок в зоне разгрузки
const NO_ORD := -9                 ## 1.56: «взять заказ из самой детали» (аргумент _cell_room / free_cell)

var sim: Sim
var equip: Array = []            ## заказанное оборудование в пути: [{id, thing, def, eta, spawned}]
var crews: Dictionary = {}       ## 1.57: id машины -> грузчики [{w, mode, st, ids, ...}]
var cell_res: Dictionary = {}    ## индекс клетки -> id рабочего, который несёт туда груз
var _zone_cache: Array[Vector2i] = []
var _zone_rev := -1
var _ship_cache: Array[Vector2i] = []
var _ship_rev := -1


func _init(s: Sim) -> void:
	sim = s


# ================================================================ справочник

static func is_hand(def_id: String) -> bool:
	return bool(Defs.objects.get(def_id, {}).get("hand", false))


## Сколько ящиков у объекта: мелочь — одна штука «в руках», крупное — по размеру.
static func crates_for(def_id: String) -> int:
	var d: Dictionary = Defs.objects.get(def_id, {})
	if d.has("crates"):
		return int(d["crates"])
	if bool(d.get("hand", false)):
		return 1
	var s: Array = d.get("size", [1, 1])
	var area := int(s[0]) * int(s[1])
	if str(d.get("kind", "")) == "machine" or str(d.get("kind", "")) == "power":
		return clampi(area, 1, 4)
	return clampi(int(ceil(area / 2.0)), 1, 3)


## 1.56: сколько штук в одной таре (поддон): деталь — по размеру, металл — по сорту. Данные в data/tare.json.
static func tare_of(it: Item) -> int:
	var t: Dictionary = Defs.tare
	if it.kind == "part":
		var sz := str(Defs.products.get(it.def_id, {}).get("size", "s"))
		return int((t.get("parts", {}) as Dictionary).get(sz, 30))
	if it.kind == "mat":
		return int((t.get("mats", {}) as Dictionary).get(it.def_id, t.get("mat", 30)))
	return 1


## Сколько штук за ходку: на тележке-рохле — целый поддон, на погрузчике — два, в руках — ящик (треть поддона,
## но не меньше обычной пачки). veh — def_id тележки/погрузчика или "". Тяжёлое и прочее — как было (base).
static func cap_for(it: Item, veh: String, base: int) -> int:
	if (it.kind != "part" and it.kind != "mat") or Production.is_heavy(it):
		return base
	var tare := tare_of(it)
	if veh == "forklift":
		return tare * 2
	if veh == "cart":
		return tare
	return maxi(base, int(ceil(float(tare) / maxf(1.0, float(Defs.tare.get("crate_div", 3))))))


static func crate_name(it: Item) -> String:
	var nm := Defs.obj_name(it.def_id)
	if it.q == "loose":
		return nm
	var n := crates_for(it.def_id)
	return L.t("Ящик: %s") % nm + (L.t(" (%d из %d)") % [it.step + 1, n] if n > 1 else "")


# ================================================================ зоны

func zone_cells() -> Array[Vector2i]:
	var w := sim.world
	if _zone_rev == w.area_rev:
		return _zone_cache
	_zone_rev = w.area_rev
	_zone_cache.clear()
	for i in w.w * w.h:
		if w.area[i] == A_UNLOAD:
			_zone_cache.append(w.cell_of(i))
	return _zone_cache


func ship_cells() -> Array[Vector2i]:
	var w := sim.world
	if _ship_rev == w.area_rev:
		return _ship_cache
	_ship_rev = w.area_rev
	_ship_cache.clear()
	for i in w.w * w.h:
		if w.area[i] == A_SHIP:
			_ship_cache.append(w.cell_of(i))
	return _ship_cache


func has_ship() -> bool:
	return not ship_cells().is_empty()


func in_ship(c: Vector2i) -> bool:
	var w := sim.world
	return w.inb(c) and w.area[w.idx(c)] == A_SHIP


## Сколько деталей изделия уже лежит в зоне отгрузки или несут туда.
func staged(p: String) -> int:
	var n := 0
	for it: Item in sim.items.values():
		if it.kind != "part" or it.def_id != p or it.q != "ok":
			continue
		if it.loc == Item.Loc.GROUND and in_ship(it.cell):
			n += 1
		elif it.reserved_by >= 0 and bool(it.get_meta("to_ship", false)):
			n += 1
	return n


## 1.56: сколько деталей заказа уже на его поддоне в зоне отгрузки (или несут туда). Детали без бирки
## (старые сохранения, ручная выкладка) считаются любому заказу этого изделия.
func staged_for(o: Dictionary) -> int:
	var p := str(o["product"])
	var oid := int(o["id"])
	var n := 0
	for it: Item in sim.items.values():
		if it.kind != "part" or it.def_id != p or it.q != "ok":
			continue
		if it.loc == Item.Loc.GROUND and in_ship(it.cell):
			if it.ord_id == oid or it.ord_id < 0:
				n += 1
		elif it.reserved_by >= 0 and it.ord_id == oid and bool(it.get_meta("to_ship", false)):
			n += 1
	return n


## 1.56: на скольких поддонах (клетках) лежит заказ в зоне отгрузки: [поддонов, деталей на них].
func pallets_of(o: Dictionary) -> Array:
	var cells := {}
	var n := 0
	var p := str(o["product"])
	var oid := int(o["id"])
	for gid in sim.ground_items:
		var it: Item = sim.items.get(gid)
		if it and it.kind == "part" and it.def_id == p and in_ship(it.cell) and (it.ord_id == oid or it.ord_id < 0):
			cells[it.cell] = true
			n += 1
	return [cells.size(), n]


## Детали этого изделия нужны машине клиента (заказ готов или уже грузят).
func ship_wanted(p: String) -> bool:
	for o: Dictionary in sim.orders.by_status(["active", "ready", "shipping"]):
		if str(o["product"]) == p:
			return true
	return false


## 1.29: машина клиента грузит только из зоны отгрузки. Запасной путь — прямо со склада, если зоны нет,
## в ней не нашлось места или за полтора часа ожидания туда так ничего и не принесли (заказ не застрянет).
func ship_only(v: Vehicle, p: String) -> bool:
	if not has_ship():
		return false
	var ord_o := sim.orders.get_order(v.order_id)
	if (staged_for(ord_o) if not ord_o.is_empty() else staged(p)) > 0:
		return true
	var probe := Item.new()
	probe.kind = "part"
	probe.def_id = p
	probe.q = "ok"
	if free_cell(ship_cells(), probe, ship_cells()[0], int(ord_o.get("id", -1))).x < 0 or v.parked_time > 90.0:
		sim.notify_once("ship_fallback", L.t("Готовый заказ не донесли до зоны отгрузки — грузим в машину прямо со склада. Проверьте, свободна ли зона отгрузки и есть ли к ней проход."), Sim.LVL_INFO, Vector2i(-1, -1), 1440.0)
		return false
	return true


func has_zone() -> bool:
	return not zone_cells().is_empty()


func in_zone(c: Vector2i) -> bool:
	var w := sim.world
	return w.inb(c) and w.area[w.idx(c)] == A_UNLOAD


## Сколько клеток в зоне (для запрета стереть последнюю).
func area_count(v: int) -> int:
	return zone_cells().size() if v == A_UNLOAD else (ship_cells().size() if v == A_SHIP else 0)


## 1.29: поддон заготовок, куда поместится металл: [Thing, слот] или []. В зоне разгрузки — в первую очередь.
func raw_pallet(it: Item, near: Vector2i) -> Array:
	if it.kind != "mat":
		return []
	var best: Array = []
	var bd := INF
	for t: Thing in sim.things.values():
		if t.def_id != RAW_PALLET or not t.built or t.demolish:
			continue
		if sim.free_space(t, 0, it.stack_key()) <= 0:
			continue
		var d := Vector2(t.cell - near).length() - (30.0 if in_zone(t.cell) else 0.0)
		if sim.slot_key(t, 0) == it.stack_key():
			d -= 3.0
		if d < bd:
			bd = d
			best = [t, 0]
	return best


## 1.56: грузы на полу вне зон разгрузки и отгрузки — «захламлённость» для проверок (в зонах им и место).
func clutter_count() -> int:
	var n := 0
	for gid in sim.ground_items:
		var it: Item = sim.items.get(gid)
		if it and not in_zone(it.cell) and not in_ship(it.cell):
			n += 1
	return n


func first_clutter() -> int:
	for gid in sim.ground_items:
		var it: Item = sim.items.get(gid)
		if it and not in_zone(it.cell) and not in_ship(it.cell):
			return int(gid)
	return -1


## Клетки склада оборудования: свободный пол в помещениях «Склад».
func stash_cells() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for r in sim.rooms.of_type("storage"):
		for c in r.cells:
			var i := sim.world.idx(c)
			if sim.world.occ[i] < 0 and sim.world.passable(c):
				out.append(c)
	return out


## Ящик уже лежит на месте хранения (склад оборудования или зона разгрузки).
func is_stored(it: Item) -> bool:
	if it.loc != Item.Loc.GROUND:
		return false
	if in_zone(it.cell):
		return true
	var r := sim.rooms.room_at(it.cell)
	return r != null and r.type == "storage"


func ground_on(c: Vector2i) -> Array[Item]:
	return _ground_on(c)


func _ground_on(c: Vector2i) -> Array[Item]:
	var out: Array[Item] = []
	for gid in sim.ground_items:
		var it: Item = sim.items.get(gid)
		if it and it.cell == c:
			out.append(it)
	return out


## Сколько ещё таких грузов поместится в клетку: ящик — один на клетку, металл — пачкой.
func _cell_room(c: Vector2i, it: Item, ordv: int = NO_ORD) -> int:
	if cell_res.has(sim.world.idx(c)):
		return 0
	if not sim.world.passable(c) or sim.world.occ[sim.world.idx(c)] >= 0:
		return 0   # 1.29: на клетке стоит поддон или другой объект — на пол не положить
	var here := _ground_on(c)
	if it.kind == "crate":
		return 1 if here.is_empty() else 0
	for o in here:
		if o.kind == "crate" or o.stack_key() != it.stack_key():
			return 0
	if it.kind == "bmat":
		return BuildMats.pallet(it.def_id) - here.size()
	if it.kind == "part" and in_ship(c):
		# 1.56: клетка зоны отгрузки — поддон одного заказа: вмещает целую тару, чужие детали не кладут
		var ov := it.ord_id if ordv == NO_ORD else ordv
		for o2 in here:
			if o2.ord_id != ov:
				return 0
		return tare_of(it) - here.size()
	return MAT_PER_CELL - here.size()


func cell_space(c: Vector2i, it: Item) -> int:
	return _cell_room(c, it)


## Ближайшая к near клетка из списка, куда поместится груз. ordv >= 0 — в зоне отгрузки сначала достраивают
## поддон этого заказа, и только потом ставят новый.
func free_cell(cells: Array[Vector2i], it: Item, near: Vector2i, ordv: int = NO_ORD) -> Vector2i:
	var best := Vector2i(-1, -1)
	var bd := INF
	for c in cells:
		if _cell_room(c, it, ordv) <= 0:
			continue
		var d := Vector2(c - near).length_squared()
		if ordv >= 0 and it.kind == "part" and in_ship(c) and not _ground_on(c).is_empty():
			d -= 100000.0
		if d < bd:
			bd = d
			best = c
	return best


## Куда положить ящик без назначения: склад оборудования → зона разгрузки → у ворот.
func stash_cell(it: Item, near: Vector2i) -> Vector2i:
	var c := free_cell(stash_cells(), it, near)
	if c.x >= 0:
		return c
	c = free_cell(zone_cells(), it, near)
	return c


# ================================================================ склад оборудования

## Запасные ящики по типам объектов: {def_id: [Item...]} (без назначения, не заняты).
func spare_sets() -> Dictionary:
	var out := {}
	for it: Item in sim.items.values():
		if it.kind != "crate" or it.dest >= 0 or it.reserved_by >= 0:
			continue
		if it.loc != Item.Loc.GROUND and it.loc != Item.Loc.VEHICLE:
			continue
		if not out.has(it.def_id):
			out[it.def_id] = []
		(out[it.def_id] as Array).append(it)
	return out


## Сколько полных комплектов объекта лежит на складе.
func spare_count(def_id: String) -> int:
	var sets := spare_sets()
	var n := (sets.get(def_id, []) as Array).size()
	return int(n / maxi(1, crates_for(def_id)))


## Взять комплект со склада под новый объект. true — нашёлся.
func take_spare(def_id: String, t: Thing) -> bool:
	var pool: Array = spare_sets().get(def_id, [])
	var need := crates_for(def_id)
	if pool.size() < need:
		return false
	pool.sort_custom(func(a: Item, b: Item) -> bool: return Vector2(sim.item_cell(a) - t.cell).length() < Vector2(sim.item_cell(b) - t.cell).length())
	for k in need:
		var it: Item = pool[k]
		it.dest = t.id
	t.crates_need = need
	t.crates_in = 0
	return true


## Демонтаж: объект разбирают в ящики, их уносят на склад оборудования.
func on_demolished(t: Thing) -> void:
	var n := crates_for(t.def_id)
	var cells := t.cells()
	for k in n:
		var it := sim.new_item("crate", t.def_id, "loose" if is_hand(t.def_id) else "crate")
		it.step = k
		it.dest = -1
		var c: Vector2i = cells[k % cells.size()]
		if not sim.world.passable(c):
			c = sim.world.nearest_passable(c)
		sim.put_on_ground(it, c)


## Отмена неустановленного объекта: ящики остаются на складе, ещё не отправленный заказ — отменяется.
## Возвращает true, если заказ отменён до отправки (деньги можно вернуть).
func on_cancelled(t: Thing) -> bool:
	for it: Item in sim.items.values():
		if it.kind == "crate" and it.dest == t.id:
			it.dest = -1
	for i in range(equip.size() - 1, -1, -1):
		var e: Dictionary = equip[i]
		if int(e["thing"]) == t.id:
			if not bool(e["spawned"]):
				equip.remove_at(i)
				return true
			e["thing"] = -1
	return t.crates_in == 0 and t.crates_need == 0


## Продать комплект со склада за половину цены.
func sell_spare(def_id: String) -> String:
	var pool: Array = spare_sets().get(def_id, [])
	var need := crates_for(def_id)
	if pool.size() < need:
		return L.t("На складе нет полного комплекта")
	for k in need:
		var it: Item = pool[k]
		sim.delete_item(it)
	var price: float = round(float(Defs.objects.get(def_id, {}).get("cost", 0)) * Defs.b("refund_rate"))
	sim.earn(price, "Продажа со склада: " + str(Defs.objects.get(def_id, {}).get("name", def_id)))
	return ""


# ================================================================ доставка

## Купленный объект заказан у поставщика: привезут фургоном через час-два рабочего времени.
func order(t: Thing) -> void:
	t.crates_need = crates_for(t.def_id)
	t.crates_in = 0
	var big := str(t.def().get("kind", "")) == "machine" or str(t.def().get("kind", "")) == "power"
	var delay := sim.rng.randf_range(25.0, 55.0) if not big else sim.rng.randf_range(60.0, 150.0)
	# мелочь, заказанная почти одновременно, едет одной машиной
	for e: Dictionary in equip:
		if not bool(e["spawned"]) and float(e["eta"]) > sim.minute and float(e["eta"]) - sim.minute < delay + 30.0:
			delay = maxf(0.0, float(e["eta"]) - sim.minute)
			break
	var eta := sim.to_work_time(sim.minute + delay)
	equip.append({"id": sim.new_id(), "thing": t.id, "def": t.def_id, "eta": eta, "spawned": false})
	t.order_eta = eta


func tick() -> void:
	var due: Array = []
	for e: Dictionary in equip:
		if not bool(e["spawned"]) and sim.minute >= float(e["eta"]):
			due.append(e)
	if due.is_empty():
		return
	var v := sim.spawn_vehicle("delivery")
	v.body = "flatbed"   # 1.30: ящики с оборудованием видно на платформе; станки — в фуре
	var names: Array[String] = []
	for e3: Dictionary in due:
		var dk := str(Defs.objects.get(str(e3["def"]), {}).get("kind", ""))
		if dk == "machine" or dk == "power":
			v.body = "semi"   # станки и подстанцию везёт фура
	for e2: Dictionary in due:
		e2["spawned"] = true
		v.equip.append(int(e2["id"]))
		var nm := Defs.obj_name(str(e2["def"]))
		if not names.has(nm):
			names.append(nm)
	v.cargo_desc = L.t("оборудование: ") + ", ".join(names.slice(0, 3)) + (L.t(" и др.") if names.size() > 3 else "")


## Фургон с оборудованием встал у ворот: в кузове — ящики под каждый заказ.
func on_park(v: Vehicle) -> void:
	if v.equip.is_empty():
		return
	for oid in v.equip:
		for i in range(equip.size() - 1, -1, -1):
			var e: Dictionary = equip[i]
			if int(e["id"]) != int(oid):
				continue
			var def_id := str(e["def"])
			var tid := int(e["thing"])
			var t: Thing = sim.things.get(tid)
			if t == null or t.built:
				tid = -1
			for k in crates_for(def_id):
				var it := sim.new_item("crate", def_id, "loose" if is_hand(def_id) else "crate")
				it.step = k
				it.dest = tid
				sim.put_in_vehicle(it, v)
			if t:
				t.order_eta = -1.0
			equip.remove_at(i)
	v.equip.clear()
	var where := L.t("в зону разгрузки") if has_zone() else L.t("сразу к местам установки (зоны разгрузки нет)")
	sim.notify(L.t("Привезли %s. Разгружаем %s.") % [v.cargo_desc, where], Sim.LVL_INFO, v.access_cell(sim.world.sidewalk_row))


# ================================================================ работа для людей

## Добавить кандидатов работы: разгрузка фургона, доставка ящиков к месту, уборка ящиков на склад.
func add_jobs(b: Brain, w: Worker, cands: Array, haul_bonus: float) -> void:
	var wc := w.cell()
	# 1. разгрузка фургона: металл и оборудование
	for v in sim.vehicles:
		if v.state != "parked" or v.kind != "delivery":
			continue
		if crew_unloads(v):
			continue   # 1.56: машину разгружают грузчики водителя — наши носят уже из зоны разгрузки
		var acc := v.access_cell(sim.world.sidewalk_row)
		for iid in (sim.veh_items.get(v.id, []) as Array):
			var it: Item = sim.items.get(iid)
			if it == null or it.reserved_by >= 0 or b._coolf(w, "item%d", it.id):
				continue
			var sc := 75.0 + haul_bonus - b._dist(wc, acc) * 0.2
			if it.kind == "crate":
				if has_zone():
					var zc := free_cell(zone_cells(), it, acc)
					if zc.x >= 0:
						cands.append({"s": sc, "k": "haul_cell", "item": it, "cell": zc})
						break
				var t: Thing = sim.things.get(it.dest)
				if t and not t.built:
					cands.append({"s": sc, "k": "deliver", "item": it, "t": t})
					break
				var sc2 := stash_cell(it, acc)
				if sc2.x < 0:
					sc2 = sim.world.nearest_passable(Vector2i(sim.gate_x + 1, sim.world.plot.end.y - 2))
				cands.append({"s": sc, "k": "haul_cell", "item": it, "cell": sc2})
				break
			# стройматериалы (1.13): поддоны — в зону разгрузки, а без неё — на землю у ворот
			if it.kind == "bmat":
				var bc := free_cell(zone_cells(), it, acc) if has_zone() else Vector2i(-1, -1)
				if bc.x < 0:
					bc = sim.bmats.yard_cell(it, acc)
				if bc.x >= 0:
					cands.append({"s": sc, "k": "haul_cell", "item": it, "cell": bc})
				break
			# металл (1.29): на поддон заготовок в зоне разгрузки, нет места — на пол зоны, оттуда — на стеллажи
			var rp := raw_pallet(it, acc)
			if not rp.is_empty():
				cands.append({"s": sc, "k": "haul", "item": it, "dest": rp[0], "slot": rp[1]})
				break
			if has_zone():
				var zc2 := free_cell(zone_cells(), it, acc)
				if zc2.x >= 0:
					cands.append({"s": sc, "k": "haul_cell", "item": it, "cell": zc2})
					break
			var dest := sim.find_storage(it, acc)
			if dest.is_empty():
				sim.notify_once("nostore_mat", L.t("Металл некуда разгружать! Расширьте зону разгрузки (Стройка → Зоны) и поставьте в неё поддоны заготовок."), Sim.LVL_WARN)
				break
			cands.append({"s": sc, "k": "haul", "item": it, "dest": dest[0], "slot": dest[1]})
			break
	# 2. ящики на земле: к месту установки, а лишние — на склад оборудования
	for gid in sim.ground_items:
		var it2: Item = sim.items.get(gid)
		if it2 == null or it2.kind != "crate" or it2.reserved_by >= 0 or b._coolf(w, "item%d", it2.id):
			continue
		var t2: Thing = sim.things.get(it2.dest)
		if t2 and not t2.built:
			if t2.crates_in + _incoming(t2) >= t2.crates_need:
				continue
			cands.append({"s": 70.0 + haul_bonus - b._dist(wc, it2.cell) * 0.3, "k": "deliver", "item": it2, "t": t2})
			continue
		if it2.dest >= 0:
			it2.dest = -1   # объект отменили или уже собрали
		if not is_stored(it2):
			var sc3 := stash_cell(it2, it2.cell)
			if sc3.x >= 0:
				cands.append({"s": 52.0 + haul_bonus - b._dist(wc, it2.cell) * 0.3, "k": "haul_cell", "item": it2, "cell": sc3})
		elif in_zone(it2.cell) and not stash_cells().is_empty():
			# из зоны разгрузки — на склад оборудования, чтобы не занимать место
			var sc4 := free_cell(stash_cells(), it2, it2.cell)
			if sc4.x >= 0:
				cands.append({"s": 40.0 + haul_bonus - b._dist(wc, it2.cell) * 0.3, "k": "haul_cell", "item": it2, "cell": sc4})
	# 3. 1.29: металл с поддонов заготовок в зоне разгрузки — на стеллажи, чтобы освободить поддоны к следующему фургону
	for t3: Thing in sim.things.values():
		if t3.def_id != RAW_PALLET or not t3.built or not in_zone(t3.cell):
			continue
		for iid3 in sim.slot_ids(t3, 0):
			var it3: Item = sim.items.get(iid3)
			if it3 == null or it3.reserved_by >= 0 or b._coolf(w, "item%d", it3.id):
				continue
			var dst3 := sim.find_storage(it3, t3.cell, RAW_PALLET)
			if not dst3.is_empty():
				cands.append({"s": 42.0 + haul_bonus - b._dist(wc, t3.cell) * 0.3, "k": "haul", "item": it3, "dest": dst3[0], "slot": dst3[1]})
			break


## Готовые заказы — на поддон в зоне отгрузки (1.12). 1.56: у каждого заказа свой поддон с биркой, тару несут целиком.
func add_ship_jobs(b: Brain, w: Worker, cands: Array, haul_bonus: float) -> void:
	if not has_ship():
		return
	var wc := w.cell()
	# 1.20: готовые детали несут в зону отгрузки сразу, не дожидаясь всей партии
	for o: Dictionary in sim.orders.by_status(["ready", "shipping", "active"]):
		var p := str(o["product"])
		var oid := int(o["id"])
		if staged_for(o) >= sim.orders.remaining(o):
			continue
		var early := str(o["status"]) == "active"
		var pred := func(i: Item) -> bool: return i.kind == "part" and i.def_id == p and i.q == "ok" and b._in_general_storage(i) and not (i.loc == Item.Loc.GROUND and in_ship(i.cell))
		var it := b._nearest_item(pred, wc, w)
		if it == null:
			continue
		var c := free_cell(ship_cells(), it, sim.item_cell(it), oid)
		if c.x < 0:
			sim.notify_once("ship_full", L.t("Зона отгрузки заполнена: расширьте её (Стройка → Зоны), чтобы готовые заказы ждали машину у ворот."), Sim.LVL_INFO, Vector2i(-1, -1), 1440.0)
			return
		cands.append({"s": (50.0 if early else 66.0) + haul_bonus - b._dist(wc, sim.item_cell(it)) * 0.25, "k": "haul_cell", "item": it, "cell": c, "ord": oid, "need": sim.orders.remaining(o) - staged_for(o)})
		return


# ================================================================ 1.56–1.57: грузчики машин

## Машину грузят и разгружают грузчики, приехавшие с водителем: наши в кузов не лезут.
## 1.57: грузчики — настоящие люди (гости завода, не персонал): идут пешком от машины у ворот до зоны и обратно,
## неся поддон (на рохле) или ящики в руках, так что чем дальше зона от дороги, тем дольше разгрузка и погрузка.
func crew_size(v: Vehicle) -> int:
	return int((Defs.tare.get("crew", {}) as Dictionary).get(v.body, 2))


## Разгружают ли эту машину грузчики (иначе — наши, как раньше: зоны нет или она не принимает).
func crew_unloads(v: Vehicle) -> bool:
	return v.kind == "delivery" and v.bmat_order < 0 and not v.crew_off and has_zone()


## Грузчики машины ещё в деле: несут груз или идут обратно — машине пока рано уезжать.
func crew_busy(v: Vehicle) -> bool:
	for c: Dictionary in (crews.get(v.id, []) as Array):
		if str(c["st"]) != "wait":
			return true
	return false


## Грузчики этой машины (для тестов и экрана).
func crew_of(v: Vehicle) -> Array:
	return crews.get(v.id, [])


func _carrier_of(wid: int) -> Dictionary:
	for arr: Array in crews.values():
		for c: Dictionary in arr:
			if (c["w"] as Worker).id == wid:
				return c
	return {}


## Для сохранения: груз в руках грузчика записываем туда, откуда он взят (в кузов или на пол зоны отгрузки).
func item_dict(it: Item) -> Dictionary:
	var d := it.to_dict()
	if it.loc != Item.Loc.WORKER:
		return d
	var c := _carrier_of(it.holder)
	if c.is_empty():
		return d
	if str(c["mode"]) == "unload":
		d["loc"] = Item.Loc.VEHICLE
		d["holder"] = int(c["vid"])
	else:
		var sc: Vector2i = c["src"]
		d["loc"] = Item.Loc.GROUND
		d["holder"] = -1
		d["cx"] = sc.x
		d["cy"] = sc.y
	return d


func tick_crews(dt: float) -> void:
	for vid in crews.keys().duplicate():
		var v0 := sim.get_vehicle(int(vid))
		if v0 == null or v0.state != "parked" or v0.hold:
			_crew_clear(int(vid))
	for v in sim.vehicles:
		if v.state != "parked" or v.hold:
			continue
		var mode := ""
		if v.kind == "pickup":
			mode = "load"
		elif crew_unloads(v) or crews.has(v.id):
			mode = "unload"
		if mode == "":
			continue
		if mode == "load" and v.has_meta("blind"):
			var n := _batches(v, dt)   # к зоне отгрузки нет прохода: грузят, не сходя с места, как в 1.56
			if n > 0:
				_crew_load_instant(v, n)
			continue
		if not crews.has(v.id):
			if v.crew_n == 0:
				continue
			_spawn_crew(v, mode)
		var arr: Array = crews[v.id]
		for k in range(arr.size() - 1, -1, -1):
			if k < arr.size():
				_carrier_step(v, arr, arr[k], k, dt)


func _spawn_crew(v: Vehicle, mode: String) -> void:
	var n := v.crew_n if v.crew_n >= 0 else crew_size(v)
	v.crew_n = n
	var acc := v.access_cell(sim.world.sidewalk_row)
	var arr: Array = []
	for k in n:
		var w := FireBrigade.make_guest(sim, L.t("Грузчик водителя"), "overall", "#d9772b", "cap", "#3a3a40", "")
		w.pos = Vector2(acc) + Vector2(0.25 + 0.5 * float(k % 2), 0.4 + 0.2 * float(k / 2 % 3))
		w.exit_cell = acc
		sim.visitors.append(w)
		arr.append({"w": w, "vid": v.id, "mode": mode, "st": "wait", "t": 0.0, "ids": [], "a": acc, "b": acc, "src": acc})
	crews[v.id] = arr


## Грузчики садятся в машину: людей на экране больше нет, неотданный груз возвращается на место.
func _crew_clear(vid: int) -> void:
	var v := sim.get_vehicle(vid)
	for c: Dictionary in (crews.get(vid, []) as Array):
		var w: Worker = c["w"]
		if not (c["ids"] as Array).is_empty():
			_give_back(v, c)
		sim.visitors.erase(w)
	crews.erase(vid)


## Груз из рук — обратно: в кузов (разгрузка) или на пол у зоны (погрузка); бронь снимается.
func _give_back(v: Vehicle, c: Dictionary) -> void:
	for iid in (c["ids"] as Array):
		var it: Item = sim.items.get(iid)
		if it == null:
			continue
		it.reserved_by = -1
		if it.has_meta("to_ship"):
			it.remove_meta("to_ship")
		if it.loc == Item.Loc.WORKER:
			if str(c["mode"]) == "unload" and v:
				sim.put_in_vehicle(it, v)
			else:
				sim.put_on_ground(it, c["src"])
	if str(c["mode"]) == "load" and v:
		v.reserved_load = maxi(0, v.reserved_load - (c["ids"] as Array).size())
	(c["ids"] as Array).clear()
	_unmount(c)


func _unmount(c: Dictionary) -> void:
	var w: Worker = c["w"]
	w.task = null
	w.carrying = -1
	w.carry_extra.clear()


func _carrier_step(v: Vehicle, arr: Array, c: Dictionary, k: int, dt: float) -> void:
	var w: Worker = c["w"]
	var acc := v.access_cell(sim.world.sidewalk_row)
	var half := maxf(0.25, float(Defs.tare.get("cycle", 2.0))) * 0.5   # возня с грузом на каждом конце ходки
	match str(c["st"]):
		"wait":
			w.anim = "idle"
			var r := _trip_start(v, c, k, dt)
			if r < 0:
				_board(v, arr, c)   # делать больше нечего — грузчик садится в машину
		"to_a":
			var r2 := sim.brain.move_to(w, c["a"], dt)
			if r2 == 1:
				_take_at_zone(v, c)
			elif r2 < 0:
				_trip_blocked(v, c)
		"grab":
			w.anim = "work"
			c["t"] = float(c["t"]) - dt
			if float(c["t"]) <= 0.0:
				c["st"] = "to_b"
		"to_b":
			var r3 := sim.brain.move_to(w, c["b"], dt)
			if r3 == 1:
				c["st"] = "drop"
				c["t"] = half
			elif r3 < 0:
				_trip_blocked(v, c)
		"drop":
			w.anim = "work"
			c["t"] = float(c["t"]) - dt
			if float(c["t"]) <= 0.0:
				_drop(v, c)
		"to_home":
			var r4 := sim.brain.move_to(w, acc, dt)
			if r4 != 0:
				if not (c["ids"] as Array).is_empty():
					_give_back(v, c)   # на месте не нашлось места — несёт обратно
				c["st"] = "wait"


func _board(v: Vehicle, arr: Array, c: Dictionary) -> void:
	sim.visitors.erase(c["w"])
	arr.erase(c)
	v.crew_n = arr.size()


## Начать ходку. 1 — пошёл, 0 — пока нечего (ждёт), −1 — делать больше нечего.
func _trip_start(v: Vehicle, c: Dictionary, k: int, dt: float) -> int:
	if str(c["mode"]) == "unload":
		return _unload_start(v, c, k, dt)
	return _load_start(v, c)


func _unload_start(v: Vehicle, c: Dictionary, k: int, dt: float) -> int:
	var cargo: Array = sim.veh_items.get(v.id, [])
	if cargo.is_empty() or not crew_unloads(v):
		return -1
	var acc := v.access_cell(sim.world.sidewalk_row)
	var first: Item = null
	for iid in cargo:
		var c0: Item = sim.items.get(iid)
		if c0 and (c0.kind == "mat" or c0.kind == "crate") and c0.reserved_by < 0:
			first = c0
			break
	if first == null:
		return 0
	var dest := _drop_cell(first, acc)
	if dest.x < 0:
		if k == 0:
			v.crew_idle += dt
			if v.crew_idle > 45.0:
				v.crew_off = true   # зона разгрузки заставлена — пусть носят наши, как раньше
				sim.notify_once("unload_full", L.t("Грузчики водителя не могут разгрузиться: зона разгрузки заставлена. Освободите её или расширьте (Стройка → Зоны)."), Sim.LVL_WARN, acc, 720.0)
		return 0
	var walk := _walk_cell(dest)
	if walk.x < 0 or not sim.world.reachable(acc, walk):
		v.crew_off = true
		sim.notify_once("unload_noway", L.t("Грузчики водителя не могут дойти до зоны разгрузки: нет прохода от ворот. Разгружают наши."), Sim.LVL_WARN, acc, 720.0)
		return 0
	var cap := 2 if first.kind == "crate" else tare_of(first)
	var key := first.stack_key()
	var ids: Array = []
	for iid2 in cargo.duplicate():
		if ids.size() >= cap:
			break
		var it: Item = sim.items.get(iid2)
		if it == null or it.reserved_by >= 0 or it.kind != first.kind or it.stack_key() != key:
			continue
		ids.append(it.id)
	var w: Worker = c["w"]
	for j in ids.size():
		sim.give_worker(sim.items[ids[j]], w, j > 0)
	c["ids"] = ids
	c["b"] = walk
	c["src"] = acc
	_mount(c, ids.size())
	v.crew_idle = 0.0
	c["st"] = "grab"
	c["t"] = maxf(0.25, float(Defs.tare.get("cycle", 2.0))) * 0.5
	return 1


## Куда нести: поддон заготовок для металла или свободная клетка зоны. (−1, −1) — места нет.
func _drop_cell(it: Item, near: Vector2i) -> Vector2i:
	if it.kind == "mat":
		var rp := raw_pallet(it, near)
		if not rp.is_empty():
			return (rp[0] as Thing).cell
	return free_cell(zone_cells(), it, near)


func _walk_cell(c: Vector2i) -> Vector2i:
	var wd := sim.world
	return c if wd.passable(c) else wd.nearest_passable(c)


## Поддон — на рохле, пара ящиков — в руках.
func _mount(c: Dictionary, n: int) -> void:
	var w: Worker = c["w"]
	if n > 6:
		var t := Task.new()
		t.kind = "crew_haul"
		t.data["veh"] = "cart"
		w.task = t
	else:
		w.task = null
	w.activity = L.t("Несёт груз") if n <= 6 else L.t("Везёт поддон на тележке")


func _drop(v: Vehicle, c: Dictionary) -> void:
	var w: Worker = c["w"]
	if str(c["mode"]) == "load":
		# у машины: поддон в кузов
		for iid in (c["ids"] as Array):
			var it: Item = sim.items.get(iid)
			if it == null:
				continue
			sim.put_in_vehicle(it, v)
			it.reserved_by = -1
			if it.has_meta("to_ship"):
				it.remove_meta("to_ship")
			v.loaded += 1
			sim.orders.on_loaded(v, it)
		v.reserved_load = maxi(0, v.reserved_load - (c["ids"] as Array).size())
		(c["ids"] as Array).clear()
		_unmount(c)
		w.activity = L.t("Грузчик водителя")
		c["st"] = "wait"
		return
	# в зоне: на поддон заготовок, а нет места — на пол зоны
	var here := w.cell()
	var rest: Array = []
	for iid2 in (c["ids"] as Array):
		var it2: Item = sim.items.get(iid2)
		if it2 == null:
			continue
		var done := false
		if it2.kind == "mat":
			var rp := raw_pallet(it2, here)
			if not rp.is_empty():
				sim.put_in_thing(it2, rp[0], int(rp[1]))
				done = true
		if not done:
			var zc := free_cell(zone_cells(), it2, here)
			if zc.x >= 0:
				sim.put_on_ground(it2, zc)
				done = true
		if not done:
			rest.append(iid2)
	c["ids"] = rest
	if rest.is_empty():
		v.crew_idle = 0.0
		_unmount(c)
	else:
		v.crew_idle += 15.0   # место кончилось: несёт остаток обратно в машину
	w.activity = L.t("Грузчик водителя")
	c["st"] = "to_home"


func _trip_blocked(v: Vehicle, c: Dictionary) -> void:
	var acc := v.access_cell(sim.world.sidewalk_row)
	if str(c["mode"]) == "load":
		_give_back(v, c)
		v.set_meta("blind", true)
		c["st"] = "wait"
	else:
		v.crew_off = true
		sim.notify_once("unload_noway", L.t("Грузчики водителя не могут дойти до зоны разгрузки: нет прохода от ворот. Разгружают наши."), Sim.LVL_WARN, acc, 720.0)
		c["st"] = "to_home"


## Погрузка: идут за поддоном заказа (раньше — чужих деталей без бирки) в зону отгрузки, откуда грузит машина.
func _load_start(v: Vehicle, c: Dictionary) -> int:
	var o := sim.orders.get_order(v.order_id)
	if o.is_empty():
		return -1
	var left := v.need - v.loaded - v.reserved_load
	if left <= 0:
		return -1
	var p := str(o["product"])
	var oid := int(o["id"])
	var only_ship := ship_only(v, p)
	var probe := Item.new()
	probe.kind = "part"
	probe.def_id = p
	var cap := mini(left, tare_of(probe))
	var onship: Array[Item] = []
	var store: Array[Item] = []
	for it: Item in sim.items.values():
		if it.kind != "part" or it.def_id != p or it.q != "ok" or it.reserved_by >= 0:
			continue
		if it.loc == Item.Loc.GROUND and in_ship(it.cell):
			if it.ord_id == oid or it.ord_id < 0:
				onship.append(it)
		elif not only_ship and sim.brain._in_general_storage(it):
			store.append(it)
	onship.sort_custom(func(a: Item, b: Item) -> bool:
		if (a.ord_id == oid) != (b.ord_id == oid):
			return a.ord_id == oid
		return a.cell.y * 4096 + a.cell.x < b.cell.y * 4096 + b.cell.x)
	var pool: Array[Item] = onship if not onship.is_empty() else store
	if pool.is_empty():
		return 0
	var src := sim.item_cell(pool[0])
	var take: Array[Item] = []
	for it2: Item in pool:
		if take.size() >= cap:
			break
		if sim.item_cell(it2) == src:
			take.append(it2)
	var acc := v.access_cell(sim.world.sidewalk_row)
	var walk := _walk_cell(src)
	if walk.x < 0 or not sim.world.reachable(acc, walk):
		v.set_meta("blind", true)
		return 0
	var w: Worker = c["w"]
	var ids: Array = []
	for it3: Item in take:
		it3.reserved_by = w.id
		if it3.ord_id == oid:
			it3.set_meta("to_ship", true)   # несут к машине — заказу они всё ещё «собраны»
		ids.append(it3.id)
	v.reserved_load += ids.size()
	c["ids"] = ids
	c["a"] = walk
	c["b"] = acc
	c["src"] = src
	w.activity = L.t("Идёт за поддоном")
	c["st"] = "to_a"
	return 1


## Дошёл до зоны отгрузки: берёт поддон (то, что успели забрать наши, — не берёт).
func _take_at_zone(v: Vehicle, c: Dictionary) -> void:
	var w: Worker = c["w"]
	var got: Array = []
	for iid in (c["ids"] as Array):
		var it: Item = sim.items.get(iid)
		if it == null or it.reserved_by != w.id or it.loc == Item.Loc.WORKER or it.loc == Item.Loc.VEHICLE:
			continue
		got.append(iid)
	v.reserved_load = maxi(0, v.reserved_load - ((c["ids"] as Array).size() - got.size()))
	if got.is_empty():
		c["ids"] = []
		c["st"] = "wait"
		return
	for j in got.size():
		sim.give_worker(sim.items[got[j]], w, j > 0)
	c["ids"] = got
	_mount(c, got.size())
	c["st"] = "grab"
	c["t"] = maxf(0.25, float(Defs.tare.get("cycle", 2.0))) * 0.5


## Сколько ходок грузчики успели сделать за этот шаг (по ходке на человека за цикл) — запасной путь без ходьбы.
func _batches(v: Vehicle, dt: float) -> int:
	v.crew_t += dt * float(crew_size(v))
	var cyc := maxf(0.5, float(Defs.tare.get("cycle", 2.0)))
	var n := int(v.crew_t / cyc)
	v.crew_t -= float(n) * cyc
	return n


## Запасной путь: к зоне отгрузки нет прохода — грузчики кладут в кузов, не сходя с места.
func _crew_load_instant(v: Vehicle, batches: int) -> void:
	var o := sim.orders.get_order(v.order_id)
	if o.is_empty():
		return
	var p := str(o["product"])
	var oid := int(o["id"])
	var only_ship := ship_only(v, p)
	var probe := Item.new()
	probe.kind = "part"
	probe.def_id = p
	for k in batches:
		var left := v.need - v.loaded
		if left <= 0:
			return
		var cap := mini(left, tare_of(probe))
		var onship: Array[Item] = []
		var store: Array[Item] = []
		for it: Item in sim.items.values():
			if it.kind != "part" or it.def_id != p or it.q != "ok" or it.reserved_by >= 0:
				continue
			if it.loc == Item.Loc.GROUND and in_ship(it.cell):
				if it.ord_id == oid or it.ord_id < 0:
					onship.append(it)
			elif not only_ship and sim.brain._in_general_storage(it):
				store.append(it)
		onship.sort_custom(func(a: Item, b: Item) -> bool:
			if (a.ord_id == oid) != (b.ord_id == oid):
				return a.ord_id == oid
			return a.cell.y * 4096 + a.cell.x < b.cell.y * 4096 + b.cell.x)
		var take: Array[Item] = []
		for it2: Item in onship + store:
			if take.size() >= cap:
				break
			take.append(it2)
		if take.is_empty():
			return
		for it3: Item in take:
			sim.put_in_vehicle(it3, v)
			it3.reserved_by = -1
			v.loaded += 1
			sim.orders.on_loaded(v, it3)


# ---------------------------------------------------------------- 1.57: далеко ли зона от дороги

const NEAR_STEPS := 3.0     ## «зона у дороги»: столько клеток от места стоянки машины до зоны
const FAR_WARN := 3.5       ## с какого замедления показывать предупреждение

var _far: Dictionary = {}   ## зона -> [клеток пути от машины или −1, во сколько раз дольше, чем у дороги]
var _far_rev := -1
var _far_t := -1e9


## Путь грузчика от места стоянки машины (у ворот) до ближайшей клетки зоны, в клетках. −1 — зоны нет или не дойти.
func road_steps(area: int) -> float:
	_far_scan()
	return float((_far.get(area, [-1.0, 0.0]) as Array)[0])


## Во сколько раз погрузка и разгрузка этой зоны идут дольше, чем у зоны рядом с дорогой (1.0 — не медленнее).
func slowdown(area: int) -> float:
	_far_scan()
	return float((_far.get(area, [-1.0, 0.0]) as Array)[1])


func _trip_min(steps: float) -> float:
	var spd := maxf(0.2, Defs.b("walk_speed") * Defs.b("carry_speed"))
	return maxf(0.5, float(Defs.tare.get("cycle", 2.0))) + 2.0 * steps / spd


## Подпись «Далеко от дороги: погрузка ×N» — пустая, если зона не дальше порога.
func far_text(area: int) -> String:
	var k := slowdown(area)
	if k < FAR_WARN:
		return ""
	return L.t("Далеко от дороги: погрузка ×%s") % ("%.1f" % snappedf(k, 0.1))


## Пояснение для подсказки: сколько грузчикам идти.
func far_hint(area: int) -> String:
	if far_text(area) == "":
		return ""
	return L.t("Грузчики водителя идут пешком от ворот, около %d клеток в один конец. Зону лучше поставить ближе к дороге.") % int(roundf(road_steps(area)))


func _far_scan() -> void:
	var w := sim.world
	if _far_rev == w.area_rev and sim.minute - _far_t < 5.0 and sim.minute >= _far_t:
		return
	_far_rev = w.area_rev
	_far_t = sim.minute
	_far.clear()
	var acc := Vector2i(sim.gate_x, w.sidewalk_row)
	for area: int in [A_UNLOAD, A_SHIP]:
		var cells: Array[Vector2i] = zone_cells() if area == A_UNLOAD else ship_cells()
		if cells.is_empty():
			continue
		var sorted := cells.duplicate()
		sorted.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
			return absi(a.x - acc.x) + absi(a.y - acc.y) < absi(b.x - acc.x) + absi(b.y - acc.y))
		var best := -1.0
		for c: Vector2i in sorted.slice(0, 6):
			var p := w.find_path(acc, _walk_cell(c))
			if p.is_empty():
				continue
			var ln := 0.0
			for i in range(1, p.size()):
				ln += Vector2(p[i]).distance_to(Vector2(p[i - 1]))
			if best < 0.0 or ln < best:
				best = ln
		if best < 0.0:
			_far[area] = [-1.0, 0.0]
			continue
		var k := maxf(1.0, _trip_min(best) / _trip_min(NEAR_STEPS))
		_far[area] = [best, k]


## Сколько ящиков к объекту уже несут.
func _incoming(t: Thing) -> int:
	var n := 0
	for w in sim.workers:
		if w.task and int(w.task.data.get("site", -1)) == t.id:
			n += 1
	return n


func make_task(b: Brain, w: Worker, cd: Dictionary) -> Task:
	var wc := w.cell()
	var t := Task.new()
	t.kind = str(cd["k"])
	var it: Item = cd["item"]
	var src := b._src_cell(it, wc)
	if src.x < 0 or not sim.world.reachable(wc, src):
		b._set_cool(w, "item%d" % it.id)
		return null
	match t.kind:
		"haul_cell":
			var c: Vector2i = cd["cell"]
			if not sim.world.reachable(src, c):
				b._set_cool(w, "item%d" % it.id)
				return null
			var extra: Array[int] = []
			var ordv := int(cd.get("ord", -1))
			if in_ship(c) and it.kind == "part" and ordv >= 0:
				it.ord_id = ordv   # 1.56: деталь едет на поддон этого заказа
			if it.kind != "crate":
				var base := b.carry_cap(it)
				var cap := cap_for(it, "", base)
				# 1.56: партию (поддон) везут на тележке-рохле или погрузчике, иначе — ящиками, медленнее
				if (it.kind == "part" or it.kind == "mat") and not Production.is_heavy(it) and b._stack_mates(it, 100).size() >= 6:
					var veh := b._haul_vehicle(w)
					if veh:
						veh.user = w.id
						t.res_users.append(veh.id)
						t.data["veh"] = veh.def_id
						cap = cap_for(it, veh.def_id, base)
				var lim := mini(cap - 1, maxi(0, _cell_room(c, it, ordv) - 1))
				if cd.has("need"):
					lim = mini(lim, maxi(0, int(cd["need"]) - 1))   # лишнего на поддон заказа не несут
				extra = b._stack_mates(it, lim)
				if not t.data.has("veh") and extra.size() + 1 > base:
					t.data["crate"] = true
			for iid in [it.id] + extra:
				var ri: Item = sim.items[iid]
				ri.reserved_by = w.id
				if in_ship(c) and ri.kind == "part" and ordv >= 0:
					ri.ord_id = ordv
				t.res_items.append(iid)
			cell_res[sim.world.idx(c)] = w.id
			t.data["zres"] = sim.world.idx(c)
			var n := 1 + extra.size()
			var what := crate_name(it) if it.kind == "crate" else it.display_name()
			var to := L.t("в зону разгрузки") if in_zone(c) else (L.t("в зону отгрузки") if in_ship(c) else (L.t("к воротам") if it.kind == "bmat" else L.t("на склад")))
			if in_ship(c):
				for iid2 in t.res_items:
					(sim.items[iid2] as Item).set_meta("to_ship", true)
			var verb := L.t("Везёт на погрузчике") if t.data.get("veh", "") == "forklift" else (L.t("Везёт поддон на тележке") if t.data.has("veh") else (L.t("Несёт ящик") if t.data.has("crate") else L.t("Несёт")))
			t.label = ("%s %s: " % [verb, to]) + what + (" ×%d" % n if n > 1 else "")
			t.data["cool"] = "item%d" % it.id
			t.add({"t": "goto", "cell": src})
			t.add({"t": "pickup", "item": it.id, "extra": extra})
			t.add({"t": "goto", "cell": c})
			t.add({"t": "drop", "cell": c})
			return t
		"deliver":
			var th: Thing = cd["t"]
			var acc := b.best_access(th, src)
			if acc.x < 0 and not th.blocks():
				acc = th.cell
			if acc.x < 0 or not sim.world.reachable(src, acc):
				b._set_cool(w, "item%d" % it.id)
				return null
			it.reserved_by = w.id
			t.res_items.append(it.id)
			t.data["site"] = th.id
			t.data["cool"] = "item%d" % it.id
			t.label = (L.t("Несёт к месту установки: ") if it.q != "loose" else L.t("Несёт в руках: ")) + crate_name(it)
			t.add({"t": "goto", "cell": src})
			t.add({"t": "pickup", "item": it.id, "extra": []})
			t.add({"t": "goto", "cell": acc, "face": b._face_to_rect(acc, th.rect())})
			t.add({"t": "put_site", "thing": th.id})
			return t
	return null


## Шаги задач: положить на клетку, отдать ящик на место установки.
func run_step(b: Brain, w: Worker, tl: Dictionary) -> void:
	match str(tl["t"]):
		"drop":
			var c: Vector2i = tl["cell"]
			release(w)
			var carried: Array = [w.carrying] + w.carry_extra.duplicate()
			for iid in carried:
				var it: Item = sim.items.get(int(iid))
				if it == null:
					continue
				sim.put_on_ground(it, c if sim.world.passable(c) else w.cell())
				it.reserved_by = -1
				if it.has_meta("to_ship"):
					it.remove_meta("to_ship")
				w.task.res_items.erase(it.id)
			w.week_score += 1
			w.task.next()
		"put_site":
			var th: Thing = sim.things.get(int(tl["thing"]))
			var it2: Item = sim.items.get(w.carrying)
			if it2 == null:
				b._fail(w)
				return
			if th == null or th.built or it2.dest != th.id:
				# объект отменили, пока несли: ящик кладём рядом, его уберут на склад
				it2.dest = -1
				it2.reserved_by = -1
				w.task.res_items.erase(it2.id)
				sim.put_on_ground(it2, w.cell())
				w.task.next()
				return
			w.task.res_items.erase(it2.id)
			sim.delete_item(it2)
			th.crates_in += 1
			sim.thing_rev += 1
			w.week_score += 1
			w.task.next()


## Снять бронь клетки (при завершении или прерывании задачи).
func release(w: Worker) -> void:
	if w.task == null or not w.task.data.has("zres"):
		return
	var i := int(w.task.data["zres"])
	if int(cell_res.get(i, -1)) == w.id:
		cell_res.erase(i)
	w.task.data.erase("zres")


func to_dict() -> Dictionary:
	return {"equip": equip}


func from_dict(d: Dictionary) -> void:
	equip = d.get("equip", [])
	crews.clear()
	cell_res.clear()
