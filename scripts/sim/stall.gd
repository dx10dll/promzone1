class_name Stall
extends RefCounted
## 1.24: «Простой» — все станки, которые сейчас не работают, и почему.
## Причины идут от самой серьёзной (сломан, нет тока) к обычным (ждёт заготовок, станочник занят).

const BAD := 0     ## нужно вмешаться
const WARN := 1    ## скоро само не пройдёт
const INFO := 2    ## обычное ожидание


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


static func _r(why: String, hint: String, lvl: int) -> Dictionary:
	return {"why": why, "hint": hint, "lvl": lvl}


static func _iname(k: String) -> String:
	return Defs.material_name(k) if Defs.materials.has(k) else Defs.product_name(k)


## Почему станок не работает. Пусто — если работает.
static func reason(sim: Sim, m: Thing) -> Dictionary:
	if m.working:
		return {}
	if m.broken:
		return _r("Сломан", "Ждёт ремонта: нужен слесарь или наладчик и %s." % Defs.money_str(Defs.b("repair_cost")), BAD)
	if not m.enabled:
		return _r("Выключен", "Включите его в карточке станка или в списке станков.", INFO)
	if not sim.power.connected(m):
		return _r("Нет кабеля", "Заведите кабель от подстанции в клетку его розетки (меню «Сети»).", BAD)
	if not sim.power.powered(m):
		return _r("Нет тока", "Не хватает мощности или отключена подстанция: проверьте «Сети».", BAD)
	if sim.inspect.is_suspended(m):
		return _r("Опечатан проверкой", "Устраните нарушение — после повторной проверки снимут пломбу.", BAD)
	if m.condition < 15.0:
		return _r("Изношен", "Состояние %d%%: ждёт обслуживания слесарем." % int(m.condition), WARN)
	if not sim.rooms.zone_ok(m):
		return _r("Стоит вне цеха", "Разметьте зону «Цех» там, где стоит станок (Зоны → Производство).", BAD)
	if not sim.water.has_water(m):
		return _r("Нет воды", "Протяните трубу от ввода воды или насоса (меню «Сети»).", BAD)
	if m.product == "":
		return _r("Нет задания", "Нет заказов на этот передел. Возьмите заказ или откройте рынок.", INFO)
	if not sim.prod.has_cons(m):
		var cn := str(sim.prod.cons_need(m)[0])
		return _r("Нет расходника", "Закончился %s — закажите в «Металл и расходники»." % str(Defs.consumables.get(cn, {}).get("short", cn)), WARN)
	var pr := m.process()
	var ops := 0
	var here := 0
	for w in sim.workers:
		if sim.prod.is_operator_for(w, pr):
			ops += 1
			if w.present:
				here += 1
	if ops == 0:
		var pn := str(Worker.PROF_NAMES.get(str(Defs.processes.get(pr, {}).get("prof", "")), "станочник"))
		return _r("Некому работать", "Нет ни одного человека на этот передел: наймите (%s)." % pn.to_lower(), WARN)
	if here == 0:
		return _r("Станочник не на смене", "Все, кто умеет, сейчас дома или в другую смену.", INFO)
	if m.is_batch():
		if sim.count_slot(m, 0) == 0:
			return _r("Ждёт загрузки", "Печь ждёт деталей с предыдущей операции.", INFO)
		return _r("Ждёт рабочего", "Загрузка есть — термист скоро запустит печь.", INFO)
	if sim.count_slot(m, 1) >= m.slot_cap(1):
		return _r("Выход забит", "Готовые детали некому унести: нужен разнорабочий или место на стеллаже.", WARN)
	var miss := sim.prod.missing_inputs(m)
	if not miss.is_empty():
		var k := str(miss.keys()[0])
		if Defs.materials.has(k) and sim.free_material(k) <= 0:
			return _r("Нет металла", "%s нет на складе — закажите в «Металл и расходники»." % _iname(k), WARN)
		return _r("Ждёт заготовок", "Не хватает: %s ×%d — несут или ждут предыдущей операции." % [_iname(k), int(miss[k])], INFO)
	return _r("Ждёт станочника", "Заготовки есть, станочник занят на другой работе.", INFO)
