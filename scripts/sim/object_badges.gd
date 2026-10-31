class_name ObjectBadges
extends RefCounted
## 1.50c: значки проблем над остальными объектами (не станками — у них StallBadges): батарея без котла,
## туалет без воды, светильник без питания, зонт без короба, объект не в своей зоне, склад полон.
## Считается не чаще раза в REFRESH_S реальных секунд и только когда сдвинулись минуты или объекты.
## Причина должна продержаться HOLD_MIN игровых минут, чтобы значок не мигал.

const REFRESH_S := 0.5
const HOLD_MIN := 3.0
const KINDS := ["water", "power", "heat", "vent", "room", "full"]
const SKIP_KINDS := ["machine", "decor", "table", "chair", "rug", "cart", "forklift", "crane"]

var shown: Dictionary = {}     ## id объекта -> {"k", "why", "hint", "m": Thing}
var _since: Dictionary = {}    ## id объекта -> [вид, минута начала]
var _last_min := -1e9
var _last_rev := -1
var _real := 0.0


func tick(sim: Sim, delta: float) -> bool:
	_real -= delta
	if _real > 0.0:
		return false
	_real = REFRESH_S
	if sim.minute == _last_min and sim.thing_rev == _last_rev:
		return false
	return refresh(sim)


func refresh(sim: Sim) -> bool:
	_last_min = sim.minute
	_last_rev = sim.thing_rev
	var old := _sig()
	var seen := {}
	for t: Thing in sim.things.values():
		if not t.built or t.demolish or t.kind() in SKIP_KINDS:
			continue
		var r := reason(sim, t)
		if r.is_empty():
			continue
		var k := str(r["k"])
		seen[t.id] = true
		var cur: Array = _since.get(t.id, [])
		if cur.is_empty() or str(cur[0]) != k:
			cur = [k, sim.minute]
			_since[t.id] = cur
		if sim.minute - float(cur[1]) >= HOLD_MIN:
			r["m"] = t
			shown[t.id] = r
		else:
			shown.erase(t.id)
	for id in _since.keys():
		if not seen.has(id):
			_since.erase(id)
			shown.erase(id)
	return _sig() != old


func _sig() -> String:
	var ids := shown.keys()
	ids.sort()
	var s := ""
	for id in ids:
		s += "%d%s," % [int(id), str((shown[id] as Dictionary)["k"])]
	return s


func visible_list() -> Array:
	return shown.values()


static func _r(k: String, why: String, hint: String) -> Dictionary:
	return {"k": k, "why": why, "hint": hint}


## Что не так с объектом сейчас: {} — всё в порядке (или значок тут не нужен).
static func reason(sim: Sim, t: Thing) -> Dictionary:
	var kind := t.kind()
	if kind in SKIP_KINDS or not t.built or t.demolish or not t.enabled:
		return {}
	var d := t.def()
	# вода
	if t.needs_water() and not sim.water.has_water(t):
		if sim.water.weak(t):
			return _r("water", L.t("Воды не хватает"), L.t("Прибор подключён, но напор слабый: добавьте насос или уберите лишние приборы с этой трубы (меню «Сети»)."))
		return _r("water", L.t("Нет воды"), L.t("Протяните трубу от ввода воды или насоса к клетке подключения (меню «Сети»)."))
	# питание
	if kind == "battery":
		if sim.power.battery_host(t) == null:
			return _r("power", L.t("Не подключён"), L.t("Поставьте шкаф вплотную к подстанции (в пределах одной клетки)."))
	elif str(d.get("power_source", "")) == "" and (float(d.get("power_kw", 0.0)) > 0.0 or kind in ["light", "camera", "speaker"]):
		if not sim.power.connected(t):
			if kind in ["light", "camera", "speaker"]:
				return _r("power", L.t("Нет питания"), L.t("Проложите кабель рядом (меню «Сети»): прибор берёт ток с ближайшего кабеля."))
			return _r("power", L.t("Нет кабеля"), L.t("Заведите кабель от подстанции в клетку его розетки (меню «Сети»)."))
		if not sim.power.powered(t):
			return _r("power", L.t("Нет тока"), L.t("Не хватает мощности или отключена подстанция: проверьте «Сети»."))
	# зона
	if not sim.rooms.zone_ok(t):
		return _r("room", L.t("Не в своей зоне"), L.t("Нужна зона %s: разметьте её там, где стоит объект (меню «Зоны»).") % Rooms.zone_names(t.def_id))
	# особые условия
	match kind:
		"radiator":
			if sim.season.heating_season() and not sim.eng.radiator_on(t):
				return _heat_why(sim)
		"heater":
			var hp := sim.eng.heater_problem(t)
			if hp != "":
				return _r("heat", L.t("Не греет"), hp.substr(0, 1).to_upper() + hp.substr(1) + ".")
		"boiler":
			var bp := sim.eng.boiler_problem(t)
			if bp != "":
				return _r("heat", L.t("Не греет"), bp.substr(0, 1).to_upper() + bp.substr(1) + ".")
		"vent_hood":
			if sim.eng.thing_vnet.is_empty() or not sim.eng.thing_vnet.has(t.id):
				return _r("vent", L.t("Нет короба"), L.t("Зонт не подключён к воздуховоду: проведите короб до вентилятора (меню «Сети»)."))
			if not sim.eng.hood_ok(t):
				return _r("vent", L.t("Нет вытяжки"), L.t("В этой сети нет работающего вентилятора: поставьте его и подведите ток."))
		"storage":
			if t.is_storage():
				if t.slot_count() > 0 and _all_full(sim, t):
					return _r("full", L.t("Полно"), L.t("Освободите место или поставьте ещё стеллаж: сюда больше ничего не влезет."))
	return {}


## 1.58: «Полно» — только если забит весь склад этого типа (металл, заготовки, готовое, брак): новый стеллаж или поддон,
## даже достраиваемый, значок снимает; снова покажем, когда и он заполнится.
static func _all_full(sim: Sim, t: Thing) -> bool:
	var acc0: Array = (t.def().get("storage", {}) as Dictionary).get("accept", [])
	for o: Thing in sim.things_of("storage", false):
		if o.demolish or o.slot_count() == 0:
			continue
		if o != t and (o.def().get("storage", {}) as Dictionary).get("accept", []) != acc0:
			continue
		if not o.built:
			return false
		for s in o.slot_count():
			if sim.count_slot(o, s) < o.slot_cap(s):
				return false
	return true


static func _heat_why(sim: Sim) -> Dictionary:
	if sim.story.has_mod("heat_off"):
		return _r("heat", L.t("Нет тепла"), L.t("Авария на теплотрассе: ждите, пока город починит."))
	var bl := sim.things_of("boiler")
	if not bl.is_empty():
		for b in bl:
			var bp := sim.eng.boiler_problem(b)
			if bp != "":
				return _r("heat", L.t("Нет тепла"), L.t("Котёл не работает: ") + bp + ".")
		return _r("heat", L.t("Не подключена"), L.t("Батарея не на трубе котла или котёл перегружен: протяните трубу от котла (меню «Сети»)."))
	var hl := sim.things_of("heater")
	if not hl.is_empty():
		var hp := sim.eng.heater_problem(hl[0])
		return _r("heat", L.t("Нет тепла"), L.t("Электрокотёл не греет: ") + hp + ".")
	return _r("heat", L.t("Нет котла"), L.t("Поставьте котёл в котельной или электрокотёл у насосной и подведите трубы."))


static func title(k: String) -> String:
	match k:
		"water":
			return L.t("Нет воды")
		"power":
			return L.t("Нет питания")
		"heat":
			return L.t("Нет тепла")
		"vent":
			return L.t("Нет вытяжки")
		"room":
			return L.t("Не та зона")
		"full":
			return L.t("Полно")
	return ""
