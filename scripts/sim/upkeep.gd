class_name Upkeep
extends RefCounted
## Оснащение и чистота: стружка и грязь на полу, уборка, контейнеры для стружки и сдача металлолома,
## заготовительный участок (ленточная пила режет пруток заранее), уровень обустройства помещений.

## Сколько «грязи» оставляет одна операция по переделу (стружка, окалина, брызги, пыль).
const CHIPS := {"turning": 26, "milling": 32, "drilling": 18, "welding": 14, "paint": 10, "assembly": 4, "heat": 8}
const BIN_CAP := 300.0          ## кг стружки в контейнере
const CHIP_PRICE := 12.0        ## ₽ за килограмм стружки
const SCRAP_K := 0.35           ## бракованные детали сдают в лом за 35% цены металла
const KG_PER_DIRT := 0.06       ## сколько кг стружки собирается с единицы грязи при уборке
const BLANKS_MAX := 24          ## запас нарезанных заготовок на каждый материал
const BLANK_K := 0.8            ## первая операция из готовой заготовки на 20% быстрее
const DIRTY := 90.0             ## средняя грязь в помещении, при которой людям неприятно
const VERY_DIRTY := 170.0
const LEVEL_MOOD := [-3, 0, 2, 4, 6]

var sim: Sim
var dirt := PackedByteArray()   ## грязь на клетке 0–255
var dirt_rev := 0
var bin_kg: Dictionary = {}     ## id контейнера -> кг стружки
var blanks: Dictionary = {}     ## материал -> нарезанных заготовок
var pickups := 0                ## сколько раз приезжал ломовоз
var scrap_earned := 0.0
var _hour := 0.0
var _mood_t := 0.0
var _last_pickup_day := -99
var _lvl_cache: Dictionary = {}
var _lvl_sig := ""


func _init(s: Sim) -> void:
	sim = s


func _ensure() -> void:
	var n := sim.world.w * sim.world.h
	if dirt.size() != n:
		dirt.resize(n)
		dirt.fill(0)


# ================================================================ грязь и стружка

func dirt_at(c: Vector2i) -> int:
	_ensure()
	return int(dirt[sim.world.idx(c)]) if sim.world.inb(c) else 0


func add_dirt(c: Vector2i, v: float) -> void:
	_ensure()
	if not sim.world.inb(c) or v <= 0.0:
		return
	var i := sim.world.idx(c)
	if sim.world.flr[i] <= 0 or sim.world.wall[i] != World.W_NONE:
		return
	if int(sim.world.flr[i]) == 4:
		v *= 0.67   # наливной пол: стружка и грязь не въедаются (1.12)
	dirt[i] = clampi(int(dirt[i]) + int(round(v)), 0, 255)
	dirt_rev += 1


## Станок закончил операцию: стружка у рабочего места.
func on_operation(m: Thing, w: Worker) -> void:
	var v := float(CHIPS.get(m.process(), 6))
	if sim.office.has_tech("five_s"):
		v *= 0.7
	if Mood.has_trait(w, "neat"):
		v *= 0.6
	var c := w.cell()
	add_dirt(c, v * 0.5)
	for d: Vector2i in Rooms.DIRS:
		add_dirt(c + d, v * 0.125)


## Средняя грязь в помещении (0–255).
func room_dirt(r: Rooms.Room) -> float:
	_ensure()
	if r == null or r.cells.is_empty():
		return 0.0
	var s := 0
	for c in r.cells:
		s += int(dirt[sim.world.idx(c)])
	return float(s) / float(r.cells.size())


## Чистота помещения в процентах — для карточки.
func cleanliness(r: Rooms.Room) -> int:
	return int(round(100.0 - room_dirt(r) / 2.55))


## Грязные клетки в помещениях (самые грязные первыми).
func dirty_cells(min_v: int = 50, limit: int = 40) -> Array[Vector2i]:
	_ensure()
	var cells: Array = []
	for r in sim.rooms.list:
		for c in r.cells:
			var v := int(dirt[sim.world.idx(c)])
			if v >= min_v and sim.world.passable(c):
				cells.append([v, c])
	cells.sort_custom(func(a: Array, b: Array) -> bool: return int(a[0]) > int(b[0]))
	var out: Array[Vector2i] = []
	for e: Array in cells.slice(0, limit):
		out.append(e[1])
	return out


var _hot_rev := -1
var _hot := false


## Есть ли в помещениях «горячие точки» — кучи стружки у станков, о которые режутся.
func has_hotspot() -> bool:
	if _hot_rev == dirt_rev / 16:
		return _hot
	_hot_rev = dirt_rev / 16
	_hot = false
	_ensure()
	for r in sim.rooms.list:
		for c in r.cells:
			if int(dirt[sim.world.idx(c)]) >= 140:
				_hot = true
				return true
	return false


func avg_room_dirt() -> float:
	var s := 0.0
	var n := 0
	for r in sim.rooms.list:
		s += room_dirt(r) * r.cells.size()
		n += r.cells.size()
	return s / float(n) if n > 0 else 0.0


## Подмели клетку: грязь убрана, стружка — в ближайший контейнер с местом.
func clean_cell(c: Vector2i, power: float = 1.0) -> void:
	_ensure()
	if not sim.world.inb(c):
		return
	var got := 0
	for cc in [c, c + Vector2i(1, 0), c + Vector2i(-1, 0), c + Vector2i(0, 1), c + Vector2i(0, -1)]:
		if not sim.world.inb(cc):
			continue
		var i := sim.world.idx(cc)
		var take := int(dirt[i]) if cc == c else int(int(dirt[i]) * 0.5 * minf(1.0, power))
		dirt[i] = int(dirt[i]) - take
		got += take
	dirt_rev += 1
	_store(float(got) * KG_PER_DIRT, c)


func bins() -> Array[Thing]:
	return sim.things_of("chip_bin").filter(func(t: Thing) -> bool: return not t.demolish)


func bin_total() -> float:
	var s := 0.0
	for b in bins():
		s += float(bin_kg.get(b.id, 0.0))
	return s


func bin_cap() -> float:
	return BIN_CAP * bins().size()


func _store(kg: float, near: Vector2i) -> void:
	if kg <= 0.0:
		return
	var best: Thing = null
	var bd := INF
	for b in bins():
		if float(bin_kg.get(b.id, 0.0)) >= BIN_CAP:
			continue
		var d := Vector2(b.cell).distance_to(Vector2(near))
		if d < bd:
			bd = d
			best = b
	if best == null:
		if bins().is_empty():
			sim.notify_once("no_chip_bin", "Стружку сметают в кучу в углу. Поставьте контейнер для стружки (Объекты → Склад): её будут сдавать в металлолом за деньги.", Sim.LVL_INFO, near, 2880.0)
		else:
			sim.notify_once("chip_full", "Контейнеры для стружки полны — ломовоз приедет в пятницу. Поставьте ещё контейнер.", Sim.LVL_WARN, near, 1440.0)
		return
	bin_kg[best.id] = minf(BIN_CAP, float(bin_kg.get(best.id, 0.0)) + kg)


# ================================================================ металлолом

func _scrap_parts() -> Array[Item]:
	var out: Array[Item] = []
	for b in sim.things_of("storage"):
		if b.def_id != "scrap_bin":
			continue
		for iid in sim.slot_ids(b, 0):
			var it: Item = sim.items.get(iid)
			if it and it.kind == "part" and it.q == "scrap" and it.reserved_by < 0:
				out.append(it)
	return out


## Сколько заплатят за брак: доля цены металла (у узлов — сумма металла деталей).
func scrap_value(product: String) -> float:
	var p: Dictionary = Defs.products.get(product, {})
	if p.has("material"):
		return float(Defs.materials.get(str(p["material"]), {}).get("price", 200)) * SCRAP_K
	var s := 0.0
	for c in Defs.components(product).keys():
		s += scrap_value(str(c)) * int(Defs.components(product)[c])
	return s


## Ломовоз: забирает стружку из контейнеров и брак из тары, платит сразу.
func pickup(forced: bool = false) -> float:
	var kg := bin_total()
	var parts := _scrap_parts()
	if kg < 20.0 and parts.size() < 3 and not forced:
		return 0.0
	var money := kg * CHIP_PRICE
	for it in parts:
		money += scrap_value(it.def_id)
		sim.delete_item(it)
	bin_kg.clear()
	money = round(money / 10.0) * 10.0
	if money <= 0.0:
		return 0.0
	sim.earn(money, "Оплата за металлолом")
	scrap_earned += money
	pickups += 1
	_last_pickup_day = sim.day()
	sim.stats["scrap_kg"] = int(sim.stats.get("scrap_kg", 0)) + int(kg)
	var lv := sim.spawn_vehicle("visit")
	lv.body = "truck"
	lv.cargo_desc = "ломовоз"
	sim.notify("Приезжал ломовоз: %d кг стружки и %d %s брака сданы в металлолом за %s." % [int(kg), parts.size(), Defs.plural(parts.size(), "деталь", "детали", "деталей"), Defs.money_str(money)], Sim.LVL_GOOD)
	sim.sfx.emit("cash", Vector2i(-1, -1))
	return money


# ================================================================ заготовительный участок

func saws() -> Array[Thing]:
	return sim.things_of("saw").filter(func(t: Thing) -> bool: return not t.demolish and t.enabled and sim.power.powered(t))


## Материал, под который пиле стоит нарезать заготовки (больше всего на складе, меньше всего нарезано).
func saw_material() -> String:
	var best := ""
	var bs := -INF
	for m in Defs.materials.keys():
		var have := sim.free_material(str(m))
		var cut := int(blanks.get(m, 0))
		if have <= cut or cut >= BLANKS_MAX:
			continue
		var sc := float(have - cut) - cut * 0.5
		if sc > bs:
			bs = sc
			best = str(m)
	return best


func add_blanks(mat: String, n: int) -> void:
	blanks[mat] = mini(BLANKS_MAX, int(blanks.get(mat, 0)) + n)
	sim.stats["blanks"] = int(sim.stats.get("blanks", 0)) + n


## Станок начинает первую операцию из этого материала: есть готовая заготовка — берёт её.
func take_blank(mat: String) -> bool:
	if int(blanks.get(mat, 0)) <= 0:
		return false
	blanks[mat] = int(blanks[mat]) - 1
	return true


func blanks_total() -> int:
	var s := 0
	for k in blanks.keys():
		s += int(blanks[k])
	return s


# ================================================================ обустройство помещений

## Слагаемые уровня обустройства: [[подпись, очки], ...].
func level_parts(r: Rooms.Room) -> Array:
	var out: Array = []
	var area := r.area()
	if r.windows > 0:
		out.append(["окна", 1.0])
		if r.windows * 12 >= area:
			out.append(["много света из окон", 1.0])
	var d: Dictionary = Defs.rooms.get(r.type, {})
	var floors: Array = d.get("floors", [])
	var good := 0
	for c in r.cells:
		var f := int(sim.world.flr[sim.world.idx(c)])
		if (not floors.is_empty() and floors.has(f)) or (floors.is_empty() and (f == 2 or f == 3)):
			good += 1
	if area > 0 and float(good) / float(area) >= 0.8:
		out.append(["хороший пол", 1.0])
	if r.powered and r.lit:
		out.append(["электрический свет", 1.0])
	var decor := 0.0
	for tid in r.things:
		var t: Thing = sim.things.get(tid)
		if t:
			decor += float(t.def().get("prestige", 0))
	if decor > 0.0:
		out.append(["обстановка", snappedf(minf(6.0, decor * 30.0 / maxf(30.0, float(area))), 0.1)])
	var rd := room_dirt(r)
	if rd > VERY_DIRTY:
		out.append(["грязища", -2.0])
	elif rd > DIRTY * 0.7:
		out.append(["грязно", -1.0])
	return out


## Уровень обустройства 1–5.
func level(r: Rooms.Room) -> int:
	if r == null:
		return 1
	var key := "%d|%d|%d" % [r.id, sim.rooms.rev, int(room_dirt(r) / 20.0)]
	if _lvl_cache.has(key):
		return int(_lvl_cache[key])
	var s := 0.0
	for p: Array in level_parts(r):
		s += float(p[1])
	var lv := clampi(1 + int(s / 2.0), 1, 5)
	if _lvl_cache.size() > 400:
		_lvl_cache.clear()
	_lvl_cache[key] = lv
	return lv


## Раз в полчаса: люди в помещениях замечают обустройство и грязь.
func _thoughts() -> void:
	for w in sim.workers:
		if not w.present or w.hidden:
			continue
		var r := sim.rooms.room_at(w.cell())
		if r == null or r.type == "" or not r.valid:
			continue
		var lv := level(r)
		if lv >= 5:
			sim.stats["room5"] = 1
		var id := "room_l%d" % lv
		for k in 5:
			var other := "room_l%d" % (k + 1)
			if other != id:
				for i in range(w.thoughts.size() - 1, -1, -1):
					if str(w.thoughts[i]["id"]) == other:
						w.thoughts.remove_at(i)
		if lv != 2:
			Mood.add(sim, w, id)
		var rd := room_dirt(r)
		if rd > VERY_DIRTY:
			Mood.add(sim, w, "very_dirty")
		elif rd > DIRTY:
			Mood.add(sim, w, "dirty")


## Множитель травм: на стружке легко поскользнуться и порезаться.
## Стенд «Охрана труда» в том же помещении — травм на 10% меньше.
func injury_k(w: Worker) -> float:
	var k := 1.4 if dirt_at(w.cell()) >= 150 else 1.0
	var r := sim.rooms.room_at(w.cell())
	if r:
		for tid in r.things:
			var t: Thing = sim.things.get(tid)
			if t and t.def_id == "safety_stand" and not t.demolish:
				k *= 0.9
				break
	return k


# ================================================================ ход времени

func tick(dt: float) -> void:
	_ensure()
	_hour += dt
	if _hour >= 60.0:
		_hour = 0.0
		_traffic_dust()
	_mood_t += dt
	if _mood_t >= 30.0:
		_mood_t = 0.0
		_thoughts()
	# ломовоз: по пятницам в 15:00 или когда контейнеры почти полны
	var tod := sim.tod()
	if sim.is_workday() and tod >= 900.0 and tod < 900.0 + dt + 0.01:
		if sim.weekday() == 4 or (bin_cap() > 0.0 and bin_total() >= bin_cap() * 0.8 and sim.day() - _last_pickup_day >= 2):
			pickup()


## Люди разносят пыль: где много ходят, там понемногу грязнеет.
func _traffic_dust() -> void:
	if sim.traffic.size() != dirt.size():
		return
	for r in sim.rooms.list:
		for c in r.cells:
			var i := sim.world.idx(c)
			var t := float(sim.traffic[i])
			if t > 3.0 and int(dirt[i]) < 120:
				dirt[i] = mini(120, int(dirt[i]) + (2 if t > 12.0 else 1))
	dirt_rev += 1


func to_dict() -> Dictionary:
	var bk := {}
	for k in bin_kg.keys():
		bk[str(k)] = bin_kg[k]
	return {"dirt": Marshalls.raw_to_base64(dirt) if not dirt.is_empty() else "", "bins": bk, "blanks": blanks, "pickups": pickups, "earned": scrap_earned, "last": _last_pickup_day}


func from_dict(d: Dictionary) -> void:
	if d.has("dirt") and str(d["dirt"]) != "":
		dirt = Marshalls.base64_to_raw(str(d["dirt"]))
	bin_kg.clear()
	var bk: Dictionary = d.get("bins", {})
	for k in bk.keys():
		bin_kg[int(k)] = float(bk[k])
	blanks = {}
	var bl: Dictionary = d.get("blanks", {})
	for k2 in bl.keys():
		blanks[str(k2)] = int(bl[k2])
	pickups = int(d.get("pickups", 0))
	scrap_earned = float(d.get("earned", 0.0))
	_last_pickup_day = int(d.get("last", -99))
