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


# ================================================================ 1.56: грузчики машин

## Машину грузят и разгружают грузчики, приехавшие с водителем: наши в кузов не лезут.
## Кладут привезённое в зону разгрузки и берут готовое из зоны отгрузки — тарой, по несколько минут на ходку.
func crew_size(v: Vehicle) -> int:
	return int((Defs.tare.get("crew", {}) as Dictionary).get(v.body, 2))


## Разгружают ли эту машину грузчики (иначе — наши, как раньше: зоны нет или она не принимает).
func crew_unloads(v: Vehicle) -> bool:
	return v.kind == "delivery" and v.bmat_order < 0 and not v.crew_off and has_zone()


func tick_crews(dt: float) -> void:
	for v in sim.vehicles:
		if v.state != "parked" or v.hold:
			continue
		if v.kind == "pickup":
			var n := _batches(v, dt)
			if n > 0:
				_crew_load(v, n)
		elif crew_unloads(v):
			var n2 := _batches(v, dt)
			if n2 > 0:
				_crew_unload(v, n2, dt)


## Сколько ходок грузчики успели сделать за этот шаг (по ходке на человека за цикл).
func _batches(v: Vehicle, dt: float) -> int:
	v.crew_t += dt * float(crew_size(v))
	var cyc := maxf(0.5, float(Defs.tare.get("cycle", 2.0)))
	var n := int(v.crew_t / cyc)
	v.crew_t -= float(n) * cyc
	return n


func _crew_load(v: Vehicle, batches: int) -> void:
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
		# поддон заказа — раньше чужих деталей без бирки; по клеткам, чтобы брали поддон целиком
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


func _crew_unload(v: Vehicle, batches: int, dt: float) -> void:
	var acc := v.access_cell(sim.world.sidewalk_row)
	var did := 0
	for k in batches:
		var cargo: Array = (sim.veh_items.get(v.id, []) as Array).duplicate()
		var first: Item = null
		for iid in cargo:
			var c0: Item = sim.items.get(iid)
			if c0 and (c0.kind == "mat" or c0.kind == "crate") and c0.reserved_by < 0:
				first = c0
				break
		if first == null:
			return
		var cap := 2 if first.kind == "crate" else tare_of(first)
		var key := first.stack_key()
		var n := 0
		for iid2 in cargo:
			if n >= cap:
				break
			var it: Item = sim.items.get(iid2)
			if it == null or it.reserved_by >= 0 or it.kind != first.kind or it.stack_key() != key:
				continue
			if it.kind == "mat":
				var rp := raw_pallet(it, acc)
				if not rp.is_empty():
					sim.put_in_thing(it, rp[0], int(rp[1]))
					n += 1
					continue
			var zc := free_cell(zone_cells(), it, acc)
			if zc.x < 0:
				break
			sim.put_on_ground(it, zc)
			n += 1
		did += n
	if did > 0:
		v.crew_idle = 0.0
	else:
		v.crew_idle += dt
		if v.crew_idle > 45.0:
			v.crew_off = true   # зона разгрузки заставлена — пусть носят наши, как раньше
			sim.notify_once("unload_full", L.t("Грузчики водителя не могут разгрузиться: зона разгрузки заставлена. Освободите её или расширьте (Стройка → Зоны)."), Sim.LVL_WARN, acc, 720.0)


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
	cell_res.clear()
