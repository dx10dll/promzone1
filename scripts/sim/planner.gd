class_name Planner
extends RefCounted
## Планировщик производства (ПДО в миниатюре): решает, какую операцию какого изделия
## выполняет каждый станок, сколько ещё запускать, хватает ли металла и расходников.
## Изделия идут по маршруту операций; детали между операциями — незавершённое производство (НЗП).

var sim: Sim
var _t := 0.0
var _check_t := 0.0
var _need_cache: Dictionary = {}
static var debug := false


func _init(s: Sim) -> void:
	sim = s


func tick(dt: float) -> void:
	_check_t -= dt
	if _check_t <= 0.0:
		_check_t = 30.0
		_need_cache.clear()
		_scan_ok = false
		_check_materials()
		_check_cons()
		_check_construction()
	_t -= dt
	if _t > 0.0:
		return
	_t = 2.0
	_need_cache.clear()
	_scan_ok = false
	for m in sim.things_of("machine"):
		_assign(m)


# ---------------------------------------------------------------- спрос и задел

func material_of(p: String) -> String:
	return str(Defs.products.get(p, {}).get("material", ""))


## Сколько изделий нужно: заказы + детали для сборки узлов, которые ещё не собраны.
func demand(p: String) -> int:
	var d := sim.orders.demand(p)
	for q in Defs.products.keys():
		var comps := Defs.components(str(q))
		if comps.has(p):
			var q_left := maxi(0, sim.orders.demand(str(q)) - pipeline(str(q)))
			d += q_left * int(comps[p])
	return d


## 1.22: один проход по предметам на весь пересчёт — сколько деталей каждого изделия в работе
## и сколько свободного НЗП на каждом шаге (раньше — проход по всем предметам на каждое изделие).
var _scan_ok := false
var _pipe_c := {}
var _wip_c := {}


func _scan() -> void:
	if _scan_ok:
		return
	_scan_ok = true
	_pipe_c.clear()
	_wip_c.clear()
	for it: Item in sim.items.values():
		if it.kind != "part":
			continue
		if it.q != "scrap" and it.loc != Item.Loc.VEHICLE:
			_pipe_c[it.def_id] = int(_pipe_c.get(it.def_id, 0)) + 1
		if it.q == "wip" and it.reserved_by < 0:
			var ok := false
			match it.loc:
				Item.Loc.GROUND:
					ok = true
				Item.Loc.THING:
					var t: Thing = sim.things.get(it.holder)
					ok = t != null and (t.is_storage() or (t.kind() == "machine" and it.slot == 1))
			if ok:
				var k := "%s:%d" % [it.def_id, it.step]
				_wip_c[k] = int(_wip_c.get(k, 0)) + 1


## Сколько изделий уже «в работе»: все детали этого изделия (кроме брака и отгруженных)
## плюс металл, заложенный в станки под первую операцию.
func pipeline(p: String) -> int:
	_scan()
	var n := int(_pipe_c.get(p, 0))
	if not Defs.is_assembly(p):
		var mq := Defs.mat_qty(p)
		for m in sim.things_of("machine"):
			if m.product == p and m.job_step == 0 and m.enabled and not m.broken and sim.power.powered(m):
				m.ensure_incoming()
				n += int((sim.count_slot(m, 0) + int(m.incoming[0])) / mq)
	return n


## Сколько ещё запускать в производство.
func need(p: String) -> int:
	if _need_cache.has(p):
		return int(_need_cache[p])
	var v := demand(p) - pipeline(p)
	_need_cache[p] = v
	return v


## Ближайший срок по заказам, которым нужно это изделие (напрямую или в составе узла).
func deadline_of(p: String) -> float:
	var best := INF
	for o: Dictionary in sim.orders.by_status(["active"]):
		var q := str(o["product"])
		if q == p or Defs.components(q).has(p):
			# приоритет ПДО: срочный заказ — как будто срок на 3 дня раньше
			best = minf(best, float(o["deadline"]) - float(o.get("prio", 0)) * 3.0 * 1440.0)
	return best


## Свободные детали НЗП этого изделия, ждущие операции step (на складе, на полу, на выходе станков).
func wip_available(p: String, step: int) -> int:
	_scan()
	return int(_wip_c.get("%s:%d" % [p, step], 0))


## Точное значение прямо сейчас (для людей, которые решают, брать ли работу).
func wip_available_live(p: String, step: int) -> int:
	var n := 0
	for it: Item in sim.items.values():
		if it.kind != "part" or it.def_id != p or it.q != "wip" or it.step != step or it.reserved_by >= 0:
			continue
		match it.loc:
			Item.Loc.GROUND:
				n += 1
			Item.Loc.THING:
				var t: Thing = sim.things.get(it.holder)
				if t and (t.is_storage() or (t.kind() == "machine" and it.slot == 1)):
					n += 1
	return n


## Свободные годные детали для сборки (не отложенные под отгрузку).
func free_ok(p: String) -> int:
	var n := 0
	for it: Item in sim.items.values():
		if it.kind != "part" or it.def_id != p or it.q != "ok" or it.reserved_by >= 0:
			continue
		if it.loc == Item.Loc.GROUND:
			n += 1
		elif it.loc == Item.Loc.THING:
			var t: Thing = sim.things.get(it.holder)
			if t and t.is_storage():
				n += 1
	return n - sim.orders.allocated(p)


func inputs_available(p: String) -> bool:
	if Defs.is_assembly(p):
		var comps := Defs.components(p)
		for c in comps.keys():
			if free_ok(str(c)) < int(comps[c]):
				return false
		return true
	return sim.free_material(material_of(p)) >= Defs.mat_qty(p)


# ---------------------------------------------------------------- материалы и расходники

func _check_materials() -> void:
	var seen := {}
	for p in Defs.products.keys():
		var mat := material_of(str(p))
		if mat == "" or seen.has(mat):
			continue
		seen[mat] = true
		var d := material_deficit(mat) + reserve_extra(mat)
		if d <= 0:
			continue
		if sim.auto_supply:
			var err := sim.order_material(mat, maxi(5, d + maxi(1, int(ceil(maxf(0.0, material_deficit(mat)) * 0.12)))), true)
			if err == "":
				continue
			sim.notify_once("auto_" + mat, L.t("Снабженец не смог докупить металл: ") + err, Sim.LVL_WARN, Vector2i(-1, -1), 480.0)
		sim.calls.on_metal_low(d, Defs.material_name(mat))
		sim.notify_once("mat_" + mat, L.t("Металла «%s» не хватает на заказы: нужно ещё %d шт., а снабжению не хватает денег.") % [Defs.material_name(mat), d], Sim.LVL_WARN, Vector2i(-1, -1), 480.0)


## Запас металла сверх заказов (настройка «Запас» в «Производство → Металл и расходники»): только для металла,
## из которого делают изделия профиля завода.
func reserve_extra(mat: String) -> int:
	if sim.supply_reserve <= 0:
		return 0
	var used := false
	var avail := sim.prod.processes_available()
	for p in sim.progress.products():
		# 1.39: запас — только под то, что завод уже может сделать (в гараже не копим поковки под фрезерный)
		if material_of(str(p)) == mat and sim.prod.can_make(str(p), avail):
			used = true
			break
	if not used:
		return 0
	var for_orders := 0
	for p2 in Defs.products.keys():
		var ps := str(p2)
		if not Defs.is_assembly(ps) and material_of(ps) == mat:
			for_orders += maxi(0, need(ps)) * Defs.mat_qty(ps)
	if sim.supply_reserve == 1:
		return maxi(8, int(ceil(for_orders * 0.2)))
	return maxi(24, int(ceil(for_orders * 0.5)))


## Сколько металла не хватает на все принятые заказы (с учётом того, что уже едет).
func material_deficit(mat: String) -> int:
	var n := 0
	for p in Defs.products.keys():
		var ps := str(p)
		if Defs.is_assembly(ps) or material_of(ps) != mat:
			continue
		n += maxi(0, need(ps)) * Defs.mat_qty(ps)
	return n - sim.material_total(mat)


## Расходники: если мало и есть станки, которые их едят, — докупить или предупредить.
func _check_cons() -> void:
	var users := {}
	for m in sim.things_of("machine"):
		if m.product == "":
			continue
		var c := str(Defs.processes.get(m.process(), {}).get("cons", ""))
		if c != "":
			users[c] = true
	for c in users.keys():
		var cd: Dictionary = Defs.consumables[c]
		var stock := float(sim.cons.get(c, 0.0))
		var low := float(cd["units"]) * 0.25
		if stock >= low or sim.cons_on_way(str(c)):
			continue
		if sim.auto_supply:
			var err := sim.order_cons(str(c), 1)
			if err == "":
				continue
		sim.notify_once("cons_" + str(c), L.t("Заканчивается %s (осталось на %d операций), а на покупку не хватает денег.") % [L.dt("consumable.%s.short" % c, str(cd["short"])), int(stock)], Sim.LVL_WARN, Vector2i(-1, -1), 480.0)
	# СИЗ: если есть шкаф, держим запас на тех, у кого комплект скоро износится
	if not sim.eng.cabinets().is_empty() and sim.auto_supply and not sim.cons_on_way("ppe"):
		var need := 0
		for w in sim.workers:
			if not w.is_itr() and w.ppe < 30.0:
				need += 1
		var st := float(sim.cons.get("ppe", 0.0))
		if need > 0 and st < need:
			sim.order_cons("ppe", int(ceil((float(need) - st) / 5.0)))


## Подсказать, если чертежи давно стоят: все заняты другой работой.
func _check_construction() -> void:
	if sim.bp_cells.is_empty():
		sim.bp_progress_at = sim.minute
		return
	if not sim.is_work_time():
		return
	if sim.minute - sim.bp_progress_at > 300.0:
		sim.notify_once("bp_idle", L.t("Стройка стоит: все заняты производством. Наймите разнорабочего в разделе «Люди → Найм»."), Sim.LVL_WARN, Vector2i(-1, -1), 1440.0)


# ---------------------------------------------------------------- станки

var _sf_min := -1.0
var _sf := {}


func should_feed(m: Thing) -> bool:
	if m.product == "" or not staffed_cached(m):
		return false
	if m.job_step > 0:
		return true
	return need(m.product) > 0


## 1.22: то же, но с запоминанием на текущую игровую минуту (дума у многих людей за один шаг).
func staffed_cached(m: Thing) -> bool:
	if sim.minute != _sf_min:
		_sf_min = sim.minute
		_sf.clear()
	if not _sf.has(m.id):
		_sf[m.id] = staffed(m)
	return bool(_sf[m.id])


## Есть ли кому встать к станку: станков в работе не больше, чем станочников этого профиля.
func staffed(m: Thing) -> bool:
	if not m.enabled or m.broken:
		return false
	if not sim.power.powered(m):
		if not sim.power.connected(m):
			sim.notify_once("nopower%d" % m.id, L.t("%s не подключён к электросети: заведите кабель от подстанции в клетку его розетки (меню «Сети»).") % m.title(), Sim.LVL_WARN, m.cell, 720.0)
		return false
	var pr := m.process()
	var ops := 0
	for w in sim.workers:
		if sim.prod.is_operator_for(w, pr):
			ops += 1
	if ops == 0:
		return false
	if m.is_batch():
		return true
	var ms := sim.things_of("machine").filter(func(x: Thing) -> bool:
		return x.process() == pr and x.enabled and not x.broken and sim.power.powered(x))
	ms.sort_custom(func(a: Thing, b: Thing) -> bool:
		var au := 0 if a.user >= 0 else 1
		var bu := 0 if b.user >= 0 else 1
		if au != bu:
			return au < bu
		return a.id < b.id)
	var idx := ms.find(m)
	if idx < ops:
		return true
	return idx >= 0 and _exclusive_need(m, ms.slice(0, ops))


## 1.16: на станках «впереди» эта деталь не помещается, а на этом — да, и она нужна. Тогда станок тоже в деле.
func _exclusive_need(m: Thing, front: Array) -> bool:
	var top := -1
	for f: Thing in front:
		top = maxi(top, f.part_rank())
	if m.part_rank() <= top:
		return false
	var pr := m.process()
	for p in Defs.products.keys():
		var ps := str(p)
		var r := Defs.product_rank(ps)
		if r <= top or r > m.part_rank():
			continue
		var rt := Defs.route(ps)
		for i in rt.size():
			if str(rt[i]["op"]) == pr and _job_useful(ps, i):
				return true
	return false


func _busy(m: Thing) -> bool:
	m.ensure_incoming()
	return sim.count_slot(m, 0) > 0 or int(m.incoming[0]) > 0 or m.progress > 0.0 or (m.is_batch() and m.working)


func _job_useful(p: String, step: int) -> bool:
	if step > 0:
		return wip_available(p, step) > 0
	return need(p) > 0 and inputs_available(p)


func _someone_can(pr: String, skill_need: int) -> bool:
	var sk := str(Defs.processes.get(pr, {}).get("skill", "turning"))
	for w in sim.workers:
		if sim.prod.is_operator_for(w, pr) and w.skill(sk) >= skill_need:
			return true
	return false


func _assign(m: Thing) -> void:
	if m.demolish:
		return
	if m.product != "" and _busy(m):
		return  # доделываем то, что уже заложено или несут
	if not staffed(m):
		m.product = ""
		return
	if m.product != "" and _job_useful(m.product, m.job_step):
		return
	var pr := m.process()
	var best_p := ""
	var best_step := 0
	var best_s := -INF
	for p in Defs.products.keys():
		var ps := str(p)
		var rt := Defs.route(ps)
		for i in rt.size():
			if str(rt[i]["op"]) != pr:
				continue
			var s := -INF
			if i > 0:
				var avail := wip_available(ps, i)
				if avail <= 0:
					continue
				s = 1000.0 + avail
			else:
				if need(ps) <= 0 or not inputs_available(ps):
					continue
				var dl := deadline_of(ps)
				s = 500.0 - (dl / 1440.0 if dl < INF else 400.0)
			if not m.fits_part(ps):
				# 1.16: деталь не влезает на этот станок; если на заводе нет станка побольше — сказать
				if not Production.size_ok(ps, pr, sim.prod.processes_available()):
					sim.notify_once("size_%s_%d" % [ps, i], L.t("«%s» — %s деталь: для операции «%s» нужен станок под %s детали. Такие есть в меню «Объекты».") % [Defs.product_name(ps), L.t(Defs.SIZE_ONE[Defs.product_rank(ps)]), Defs.process_name(pr), L.t(Defs.SIZE_PL[Defs.product_rank(ps)])], Sim.LVL_WARN, m.cell, 1440.0)
				continue
			s -= 40.0 * float(m.part_rank() - Defs.product_rank(ps))   # 1.16: крупный станок — сначала под крупные детали
			var sk := int(rt[i].get("skill", 1))
			if not _someone_can(pr, sk):
				sim.notify_once("skill_%s_%d" % [ps, i], L.t("Некому выполнить операцию «%s» для «%s»: нужен работник с навыком от %d.") % [Defs.process_name(pr), Defs.product_name(ps), sk], Sim.LVL_WARN, m.cell, 720.0)
				continue
			if s > best_s:
				best_s = s
				best_p = ps
				best_step = i
	if debug and (best_p != m.product or best_step != m.job_step):
		print("[planner] %s %s: станок %d (%s) '%s'/%d -> '%s'/%d" % [sim.date_str(), sim.time_str(), m.id, pr, m.product, m.job_step, best_p, best_step])
	m.product = best_p
	m.job_step = best_step
