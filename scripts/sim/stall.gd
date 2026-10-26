class_name Stall
extends RefCounted
## 1.24: «Простой» — все станки, которые сейчас не работают, и почему.
## Причины идут от самой серьёзной (сломан, нет тока) к обычным (ждёт заготовок, станочник занят).

const BAD := 0     ## нужно вмешаться
const WARN := 1    ## скоро само не пройдёт
const INFO := 2    ## обычное ожидание


## Поле "k" — вид значка над станком (1.49): power | operator | full | input | idle, пусто — значка нет.
## Список: [{"m": Thing, "why": String, "hint": String, "lvl": int}], сначала серьёзные.
static func list(sim: Sim) -> Array:
	var out: Array = []
	for m in sim.things_of("machine"):
		if m.demolish or m.working:
			continue
		var r := reason(sim, m)
		if r.is_empty():
			continue
		r["m"] = m
		out.append(r)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["lvl"]) < int(b["lvl"]) if int(a["lvl"]) != int(b["lvl"]) else (a["m"] as Thing).id < (b["m"] as Thing).id)
	return out


## Сколько станков стоит по серьёзным причинам (для значка на разделе).
static func bad_count(sim: Sim) -> int:
	var n := 0
	for r: Dictionary in list(sim):
		if int(r["lvl"]) <= WARN:
			n += 1
	return n


static func _r(why: String, hint: String, lvl: int, k: String = "") -> Dictionary:
	return {"why": why, "hint": hint, "lvl": lvl, "k": k}


static func _iname(k: String) -> String:
	return Defs.material_name(k) if Defs.materials.has(k) else Defs.product_name(k)


## 1.53: пневмостанок (покраска) без сжатого воздуха: нет компрессора, он выключен или без тока. Пусто — воздух есть или не нужен.
static func air_reason(sim: Sim, m: Thing) -> Dictionary:
	if sim.eng.air_mode(m) != "need" or not m.enabled or m.broken:
		return {}
	if sim.eng.pressure(m) > 0.0:
		return {}
	var net := sim.eng.anet_of_thing(m)
	if net == null:
		return _r(L.t("Нет воздуха"), L.t("Станку нужен сжатый воздух: поставьте компрессор и протяните воздушную сеть до клетки подключения (меню «Сети»)."), WARN, "air")
	return _r(L.t("Нет воздуха"), L.t("Компрессор в этой сети не качает: проверьте, что он включён, есть ток и стоит в компрессорной."), WARN, "air")


## Почему станок не работает. Пусто — если работает.
static func reason(sim: Sim, m: Thing) -> Dictionary:
	if m.working:
		return {}
	if m.broken:
		return _r(L.t("Сломан"), L.t("Ждёт ремонта: нужен слесарь или наладчик и %s.") % Defs.money_str(Defs.b("repair_cost")), BAD)
	if not m.enabled:
		return _r(L.t("Выключен"), L.t("Включите его в карточке станка или в списке станков."), INFO)
	if not sim.power.connected(m):
		return _r(L.t("Нет кабеля"), L.t("Заведите кабель от подстанции в клетку его розетки (меню «Сети»)."), BAD, "power")
	if not sim.power.powered(m):
		return _r(L.t("Нет тока"), L.t("Не хватает мощности или отключена подстанция: проверьте «Сети»."), BAD, "power")
	if sim.inspect.is_suspended(m):
		return _r(L.t("Опечатан проверкой"), L.t("Устраните нарушение — после повторной проверки снимут пломбу."), BAD)
	if m.condition < 15.0:
		return _r(L.t("Изношен"), L.t("Состояние %d%%: ждёт обслуживания слесарем.") % int(m.condition), WARN)
	if not sim.rooms.zone_ok(m):
		return _r(L.t("Стоит вне цеха"), L.t("Разметьте зону «Цех» там, где стоит станок (Зоны → Производство)."), BAD)
	if not sim.water.has_water(m):
		return _r(L.t("Нет воды"), L.t("Протяните трубу от ввода воды или насоса (меню «Сети»)."), BAD)
	var ar := air_reason(sim, m)
	if not ar.is_empty():
		return ar
	if m.product == "":
		return _r(L.t("Нет задания"), L.t("Нет заказов на этот передел. Возьмите заказ или откройте рынок."), INFO, "idle")
	if not sim.prod.has_cons(m):
		var cn := str(sim.prod.cons_need(m)[0])
		return _r(L.t("Нет расходника"), L.t("Закончился %s — закажите в «Металл и расходники».") % L.dt("consumable.%s.short" % cn, str(Defs.consumables.get(cn, {}).get("short", cn))), WARN)
	var pr := m.process()
	var ops := 0
	var here := 0
	for w in sim.workers:
		if sim.prod.is_operator_for(w, pr):
			ops += 1
			if w.present:
				here += 1
	if ops == 0:
		var pn := L.t(str(Worker.PROF_NAMES.get(str(Defs.processes.get(pr, {}).get("prof", "")), "станочник")))
		return _r(L.t("Некому работать"), L.t("Нет ни одного человека на этот передел: наймите (%s).") % pn.to_lower(), WARN, "operator")
	if here == 0:
		return _r(L.t("Станочник не на смене"), L.t("Все, кто умеет, сейчас дома или в другую смену."), INFO)
	if m.is_batch():
		if sim.count_slot(m, 0) == 0:
			return _r(L.t("Ждёт загрузки"), L.t("Печь ждёт деталей с предыдущей операции."), INFO, "input")
		return _r(L.t("Ждёт рабочего"), L.t("Загрузка есть — термист скоро запустит печь."), INFO, "operator")
	if sim.count_slot(m, 1) >= m.slot_cap(1):
		return _r(L.t("Выход забит"), L.t("Готовые детали некому унести: нужен разнорабочий или место на стеллаже."), WARN, "full")
	var miss := sim.prod.missing_inputs(m)
	if not miss.is_empty():
		var k := str(miss.keys()[0])
		if Defs.materials.has(k) and sim.free_material(k) <= 0:
			return _r(L.t("Нет металла"), L.t("%s нет на складе — закажите в «Металл и расходники».") % _iname(k), WARN, "input")
		return _r(L.t("Ждёт заготовок"), L.t("Не хватает: %s ×%d — несут или ждут предыдущей операции.") % [_iname(k), int(miss[k])], INFO, "input")
	return _r(L.t("Ждёт станочника"), L.t("Заготовки есть, станочник занят на другой работе."), INFO)
