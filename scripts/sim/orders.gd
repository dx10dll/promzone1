class_name OrderBook
extends RefCounted
## Заказы клиентов: предложения, принятые, отгрузка, оплата, просрочки.

var sim: Sim
var list: Array = []
var _t := 0.0


func _init(s: Sim) -> void:
	sim = s


func get_order(id: int) -> Dictionary:
	for o: Dictionary in list:
		if int(o["id"]) == id:
			return o
	return {}


func short(o: Dictionary) -> String:
	return "%s × %d для %s" % [Defs.product_name(str(o["product"])), int(o["qty"]), str(o["client"])]


const KIND_NAMES := {"export": "Экспорт", "state": "Госзаказ", "contract": "Контракт"}
const EXPORT_CLIENTS := ["ТОО «Степьмаш» (Казахстан)", "ЧУП «Полесьетехника» (Беларусь)", "ООО «Узмаштех» (Узбекистан)", "ОсОО «Ала-Тоо Индастри» (Киргизия)", "ООО «Араратмаш» (Армения)"]
const STATE_CLIENTS := ["ФКП «Госзаказ-7»", "АО «Спецкомплект»", "ФГУП «Северный арсенал»", "АО «НПО Восход»"]


func remaining(o: Dictionary) -> int:
	return int(o["qty"]) - int(o["shipped"])


func by_status(st: Array) -> Array:
	return list.filter(func(o: Dictionary) -> bool: return st.has(str(o["status"])))


## Сколько заказов можно держать в работе: растёт вместе со штатом.
func max_active() -> int:
	return clampi(int(Defs.b("max_active_orders")) + int(sim.workers.size() / 3), 5, 20)


func active_count() -> int:
	return by_status(["active", "ready", "shipping"]).size()


## Сколько деталей этого типа ещё нужно отгрузить по всем принятым заказам.
func demand(p: String) -> int:
	var n := 0
	for o: Dictionary in list:
		if str(o["product"]) == p and ["active", "ready", "shipping"].has(str(o["status"])):
			n += remaining(o)
	return n


## 1.17: игрок открыл производство раньше конца недели стройки — пара заявок сразу.
func open_early() -> void:
	for i in 3:
		sim.sales.inquiry(_maybe_trial(make_offer()))


## Утро: недельные партии по контрактам, затем заявки заказчиков — их разбирает отдел сбыта.
## Решения игрока остаются только для тендеров (экспорт, госзаказ) и «горящих» заказов.
func morning() -> void:
	# убрать протухшие предложения
	for o: Dictionary in list:
		if str(o["status"]) == "offer" and sim.minute > float(o["expires"]):
			o["status"] = "expired"
	list = list.filter(func(o: Dictionary) -> bool: return str(o["status"]) != "expired")
	sim.sales.morning()
	sim.progress.quiet_morning()
	if sim.progress.quiet():
		return   # 1.17: неделя стройки — заявок нет
	if not sim.is_workday() and sim.day() > 1:
		return
	# чем больше станочников и выше репутация, тем больше заявок; часть сбыт отклонит
	var ops := sim.office.load_ops() if sim.office else 1.0
	var n := sim.rng.randi_range(1, 3) + int(maxf(0.0, ops - 1.0) / 2.0)
	if sim.day() == 1:
		n = 4
	else:
		if sim.season.month() >= 10:
			n += 1   # конец года: заказчики спешат закрыть план
		# профиль завода, сезон и репутация: сельхозмашу весной заявок вдвое больше, зимой — мало
		var fk := sim.progress.offers_k() * float(n) * clampf(0.6 + sim.reputation / 125.0, 0.6, 1.4) * sim.market.inquiry_k()
		n = int(floor(fk)) + (1 if sim.rng.randf() < fk - floor(fk) else 0)
	var had := by_status(["offer"]).size()
	_special_offers()
	if by_status(["offer"]).size() > had:
		sim.notify("Пришёл тендер — решение за вами: «Заказы» → «Контракты».", Sim.LVL_INFO)
	for i in n:
		sim.sales.inquiry(_maybe_trial(make_offer()))


# ---------------------------------------------------------------- пробная партия и перенос срока (1.9.1)

const MOVE_DAYS := 2          ## на сколько рабочих дней переносят срок
const MOVE_DISCOUNT := 0.12   ## скидка заказчику за перенос
const MAX_LATE_CUT := 0.3     ## неустойка за просрочку — не больше 30% суммы заказа


## Делали ли уже это изделие на заказ (принят, отгружается или выполнен).
func tried(p: String) -> bool:
	return list.any(func(o: Dictionary) -> bool: return str(o["product"]) == p and str(o["status"]) in ["active", "ready", "shipping", "done"])


## Первый заказ на новое многооперационное изделие — пробная партия: малая, с двойным сроком
## и без неустойки. Цех учится на ней, а не платит за освоение месячной прибылью.
func _maybe_trial(o: Dictionary) -> Dictionary:
	var p := str(o["product"])
	if Defs.route(p).size() < 2 and not Defs.is_assembly(p):
		return o
	if tried(p) or list.any(func(x: Dictionary) -> bool: return str(x["product"]) == p and bool(x.get("trial", false)) and str(x["status"]) == "offer"):
		return o
	o["qty"] = maxi(2, int(ceil(int(o["qty"]) * 0.4)))
	o["lead"] = int(o["lead"]) * 2
	o["deadline"] = deadline_after(int(o["lead"]))
	o["penalty"] = 0.0
	o["trial"] = true
	return o


## Можно ли перенести срок: пустая строка — можно, иначе причина.
func postpone_block(o: Dictionary) -> String:
	if str(o.get("status", "")) != "active":
		return "Заказ уже не в работе"
	if str(o.get("kind", "")) == "state":
		return "Госзаказ не переносится"
	if bool(o.get("moved", false)):
		return "Срок уже переносили — второй раз заказчик не согласится"
	return ""


## Позвонить заказчику: срок +2 рабочих дня за скидку 12% и немного репутации.
func postpone(id: int) -> String:
	var o := get_order(id)
	if o.is_empty():
		return "Заказ не найден"
	var why := postpone_block(o)
	if why != "":
		return why
	var d := maxi(int(float(o["deadline"]) / 1440.0) + 1, sim.day())
	var counted := 0
	while counted < MOVE_DAYS:
		d += 1
		if sim.is_workday(d):
			counted += 1
	o["deadline"] = float(d - 1) * 1440.0 + Defs.b("shift_end")
	o["price"] = int(round(float(o["price"]) * (1.0 - MOVE_DISCOUNT) / 10.0) * 10)
	o["lead"] = int(o.get("lead", 3)) + MOVE_DAYS
	o["moved"] = true
	sim.reputation = maxf(0.0, sim.reputation - 2.0)
	sim.stats["postponed"] = int(sim.stats.get("postponed", 0)) + 1
	sim.notify("Договорились с заказчиком: %s — срок до %s, скидка %d%%." % [short(o), deadline_str(o), int(MOVE_DISCOUNT * 100.0)], Sim.LVL_INFO)
	return ""


## Обычный срок заказа в рабочих днях (средний — без случайной добавки 1–3 дня).
func make_lead(p: String, qty: int) -> int:
	var work_min := qty * route_minutes(p) / 0.7
	return int(ceil(work_min / 420.0)) + 2 + (1 if Defs.route(p).size() > 1 else 0)


func make_offer(product: String = "") -> Dictionary:
	var rng := sim.rng
	var p := product
	if p == "":
		# чаще предлагают то, что завод умеет делать; изредка — «на вырост»
		var avail := sim.prod.processes_available()
		var pool: Array = []
		for k in sim.progress.products():
			var ks := str(k)
			if not Defs.products.has(ks) or not sim.office.unlocked(Defs.products[ks]):
				continue
			var weight := 1   # то, что завод пока не умеет, тоже просят — это видно в упущенной выгоде
			if sim.prod.can_make(ks, avail):
				weight = 6
			else:
				for o: Dictionary in Defs.route(ks):
					if avail.has(str(o["op"])):
						weight = 2
			for j in weight:
				pool.append(ks)
		if pool.is_empty():
			for k2 in sim.progress.products():
				if Defs.products.has(str(k2)) and sim.office.unlocked(Defs.products[str(k2)]):
					pool.append(str(k2))
		if pool.is_empty():
			pool = ["pin"]
		p = str(pool[rng.randi_range(0, pool.size() - 1)])
	var pd: Dictionary = Defs.products[p]
	var qr: Array = pd.get("qty", [5, 15])
	# крупному заводу дают партии побольше
	var ops := sim.office.load_ops() if sim.office else 1.0
	var big_k := clampf(1.0 + 0.08 * (ops - 1.0), 1.0, 1.5)
	var qty := maxi(1, int(round(rng.randi_range(int(qr[0]), int(qr[1])) * sim.progress.qty_k() * big_k)))
	var pr: Array = pd.get("price", [500, 800])
	var rep_k := (0.9 + sim.reputation / 500.0) * (1.1 if sim.season.month() >= 10 else 1.0) * sim.story.mod("order_price") * sim.progress.price_k() * sim.market.price_k()
	var price := int(round(rng.randf_range(float(pr[0]), float(pr[1])) * rep_k * sim.sales.price_index(p) / 10.0) * 10)
	var work_days := make_lead(p, qty) - 2 + rng.randi_range(1, 3)
	var clients: Array = Defs.names.get("clients", ["ИП Иванов"])
	return {
		"id": sim.new_id(), "client": str(clients[rng.randi_range(0, clients.size() - 1)]),
		"product": p, "qty": qty, "price": price, "lead": work_days,
		"deadline": deadline_after(work_days),
		"penalty": Defs.b("late_penalty_per_day"), "status": "offer", "shipped": 0,
		"allocated": 0, "created": sim.minute, "expires": sim.minute + 2.0 * 1440.0,
		"pickup_eta": -1.0, "pickup_spawned": false, "accepted": -1.0, "kind": "",
	}


## Тендеры: экспорт (ступень «Контракты») и госзаказ (ступень «Тендеры» или режимный завод).
func _special_offers() -> void:
	var pg := sim.progress
	var has_cp := sim.story.has_checkpoint()
	# режимный завод получает госзаказ с первого дня; остальным нужна ступень «Тендеры» (её держит юрист)
	var state_ok := (bool(pg.pdef().get("state", false)) and has_cp) or (sim.dev.on("law3") and pg.ooo and has_cp)
	if not state_ok and not bool(pg.pdef().get("state", false)) and pg.stage >= 4 and not sim.dev.on("law3"):
		sim.notify_once("need_lawyer", "Госзаказ разыгрывают на тендере: нужна ступень «Тендеры» (Управление → Развитие), документы готовит юрист.", Sim.LVL_INFO, Vector2i(-1, -1), 7.0 * 1440.0)
	if bool(pg.pdef().get("state", false)) and not has_cp:
		sim.notify_once("need_cp", "Госзаказ дают только режимным предприятиям: поставьте «Проходную с вахтой» (Объекты → Безопасность).", Sim.LVL_WARN, Vector2i(-1, -1), 2880.0)
	var chance_state := 0.45 if bool(pg.pdef().get("state", false)) else 0.15
	if state_ok and sim.rng.randf() < chance_state and by_status(["offer"]).filter(func(o: Dictionary) -> bool: return str(o.get("kind", "")) == "state").is_empty():
		var o := make_offer()
		o["kind"] = "state"
		o["client"] = STATE_CLIENTS[sim.rng.randi_range(0, STATE_CLIENTS.size() - 1)]
		o["price"] = int(round(float(o["price"]) * 1.35 / 10.0) * 10)
		o["qty"] = int(ceil(int(o["qty"]) * 1.3))
		o["penalty"] = 0.12
		o["expires"] = sim.minute + 3.0 * 1440.0
		list.append(o)
	if sim.dev.on("mkt3") and sim.reputation >= 60.0 and sim.rng.randf() < (0.3 if sim.market.iso_ok() else 0.22) and by_status(["offer"]).filter(func(o2: Dictionary) -> bool: return str(o2.get("kind", "")) == "export").is_empty():
		var e := make_offer()
		e["kind"] = "export"
		e["client"] = EXPORT_CLIENTS[sim.rng.randi_range(0, EXPORT_CLIENTS.size() - 1)]
		e["price"] = int(round(float(e["price"]) * 1.6 / 10.0) * 10)
		e["qty"] = int(ceil(int(e["qty"]) * 1.5))
		e["lead"] = int(e["lead"]) + 2
		e["deadline"] = deadline_after(int(e["lead"]))
		e["expires"] = sim.minute + 3.0 * 1440.0
		list.append(e)


## Трудоёмкость одного изделия по маршруту (печь — на партию, детали для сборки — тоже считаются).
func route_minutes(p: String) -> float:
	var t := 0.0
	for o: Dictionary in Defs.route(p):
		var mins := float(o.get("time", 30))
		if str(o["op"]) == "heat":
			mins /= 6.0
		t += mins
	var comps := Defs.components(p)
	for c in comps.keys():
		t += route_minutes(str(c)) * int(comps[c])
	return t


## Конец рабочего дня через n рабочих дней от сегодня (выходные не в счёт).
func deadline_after(n: int) -> float:
	var d := sim.day()
	var counted := 0
	while counted < n:
		d += 1
		if sim.is_workday(d):
			counted += 1
	return float(d - 1) * 1440.0 + Defs.b("shift_end")


func accept(id: int, auto_buy: bool, by_sales: bool = false) -> String:
	var o := get_order(id)
	if o.is_empty() or str(o["status"]) != "offer":
		return "Заказ недоступен"
	if active_count() >= max_active() and str(o.get("kind", "")) != "contract":
		return "Слишком много заказов в работе (максимум %d — растёт со штатом)" % max_active()
	o["status"] = "active"
	o["accepted"] = sim.minute
	o["deadline"] = deadline_after(int(o.get("lead", 3)))
	var p := str(o["product"])
	var msg := ("Сбыт взял заказ: %s, %s. Срок — %s." % [short(o), Defs.money_str(float(o["price"]) * int(o["qty"])), deadline_str(o)]) if by_sales else ("Заказ принят: %s. Срок — %s." % [short(o), deadline_str(o)])
	if str(o.get("kind", "")) == "contract":
		msg = "Партия по контракту: %s. Срок — %s." % [short(o), deadline_str(o)]
	if bool(o.get("trial", false)):
		msg += " Пробная партия: срок вдвое больше, без неустойки."
	if str(o.get("kind", "")) == "state":
		var adv := float(o["price"]) * int(o["qty"]) * 0.5
		o["paid_part"] = adv
		sim.earn(adv, "Оплата: аванс 50% по госзаказу")
		msg += " Получен аванс %s." % Defs.money_str(adv)
	if auto_buy:
		var mat := sim.planner.material_of(p)
		var need := sim.planner.material_deficit(mat)
		if need > 0:
			var extra := maxi(1, int(ceil(remaining(o) * 0.12)))
			var err := sim.order_material(mat, need + extra, true)
			if err != "":
				msg += " Металл не заказан: " + err
	sim.notify(msg, Sim.LVL_INFO if by_sales else Sim.LVL_GOOD)
	return ""


## Сколько металла уже «обещано» другим принятым заказам.
func _committed_material(mat: String, except_id: int) -> int:
	var n := 0
	for o: Dictionary in list:
		if int(o["id"]) == except_id:
			continue
		if ["active", "ready", "shipping"].has(str(o["status"])) and sim.planner.material_of(str(o["product"])) == mat:
			n += maxi(0, remaining(o) - sim.ok_in_storage(str(o["product"])))
	return n


func decline(id: int) -> void:
	var o := get_order(id)
	if not o.is_empty() and str(o["status"]) == "offer":
		list.erase(o)


func deadline_str(o: Dictionary) -> String:
	var dl := float(o["deadline"])
	var d := int(dl / 1440.0) + 1
	var left := d - sim.day()
	var base := "день %d (%s)" % [d, sim.weekday_name(d)]
	if left == 0:
		return base + ", сегодня"
	if left == 1:
		return base + ", завтра"
	if left < 0:
		return base + ", просрочен"
	return base + ", через %d %s" % [left, Defs.plural(left, "день", "дня", "дней")]


func tick(dt: float) -> void:
	_t -= dt
	if _t > 0.0:
		return
	_t = 5.0
	var sorted := by_status(["active"])
	sorted.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["deadline"]) < float(b["deadline"]))
	for o: Dictionary in sorted:
		var p := str(o["product"])
		var free_ok := sim.ok_in_storage(p) - allocated(p)
		if free_ok >= remaining(o):
			o["status"] = "ready"
			o["allocated"] = remaining(o)
			var delay := sim.rng.randf_range(Defs.b("pickup_delay_min"), Defs.b("pickup_delay_max"))
			o["pickup_eta"] = sim.to_work_time(sim.minute + delay)
			sim.notify("Заказ готов: %s. Клиент выслал машину." % short(o), Sim.LVL_GOOD)
		elif sim.minute > float(o["deadline"]) + Defs.b("fail_after_days") * 1440.0:
			fail(o, "Клиент ушёл, репутация упала")
		elif sim.minute > float(o["deadline"]):
			var hint := " Можно позвонить заказчику и перенести срок: «Заказы → В работе»." if postpone_block(o) == "" else ""
			sim.notify_once("late_%d" % int(o["id"]), "Просрочка по заказу: %s. Каждый день — штраф %d%%.%s" % [short(o), int(float(o["penalty"]) * 100), hint], Sim.LVL_BAD, Vector2i(-1, -1), 1440.0)
	for o: Dictionary in by_status(["ready"]):
		if not bool(o["pickup_spawned"]) and sim.minute >= float(o["pickup_eta"]):
			var v := sim.spawn_vehicle("pickup")
			v.order_id = int(o["id"])
			v.need = remaining(o)
			# 1.14: машина по партии — фура на экспорт, госзаказ и контракт, грузовик под тяжёлое и большое
			var heavy := bool(Defs.products.get(str(o["product"]), {}).get("heavy", false))
			if str(o.get("kind", "")) in ["export", "state", "contract"]:
				v.body = "semi"
			elif heavy or v.need >= 24:
				v.body = "truck"
			elif v.need >= 8:
				v.body = "flatbed"   # 1.30: поддоны с деталями видно в кузове
			v.cargo_desc = short(o)
			o["pickup_spawned"] = true
			o["status"] = "shipping"


## Заказ сорван: штрафы, репутация, «не вовремя» в статистике сроков (1.20).
func fail(o: Dictionary, why: String) -> void:
	if str(o["status"]) in ["failed", "done"]:
		return
	o["status"] = "failed"
	sim.reputation = maxf(0.0, sim.reputation - (3.0 if bool(o.get("trial", false)) else 8.0))
	if str(o.get("kind", "")) == "state":
		var fine := float(o["price"]) * int(o["qty"]) * MAX_LATE_CUT + float(o.get("paid_part", 0.0))
		sim.spend(fine, "Штраф: срыв госзаказа (возврат аванса и неустойка)")
		sim.reputation = maxf(0.0, sim.reputation - 7.0)
	sim.stats["orders_failed"] = int(sim.stats["orders_failed"]) + 1
	sim.market.on_shipped(99)   # срыв — тоже «не вовремя»
	sim.notify("Заказ сорван: %s. %s." % [short(o), why], Sim.LVL_BAD)
	if str(o.get("kind", "")) == "contract":
		sim.sales.on_order_closed(o, false)


func allocated(p: String) -> int:
	var n := 0
	for o: Dictionary in by_status(["ready", "shipping"]):
		if str(o["product"]) == p:
			n += int(o["allocated"])
	return n


func on_loaded(v: Vehicle, it: Item) -> void:
	var o := get_order(v.order_id)
	if o.is_empty():
		return
	if it and it.defect:
		o["defects"] = int(o.get("defects", 0)) + 1
	o["shipped"] = int(o["shipped"]) + 1
	o["allocated"] = maxi(0, int(o["allocated"]) - 1)


## Машина уехала недогруженной: платят за погруженное, остаток заказа снова в работе.
func on_partial_pickup(v: Vehicle) -> void:
	var o := get_order(v.order_id)
	for iid in (sim.veh_items.get(v.id, []) as Array).duplicate():
		var it: Item = sim.items.get(iid)
		if it:
			sim.delete_item(it)
	if o.is_empty():
		return
	var amount := float(o["price"]) * v.loaded
	if amount > 0.0:
		sim.earn(amount, "Частичная оплата: " + short(o))
		o["paid_part"] = float(o.get("paid_part", 0.0)) + amount
		sim.stats["shipped"] = int(sim.stats["shipped"]) + v.loaded
	o["status"] = "active"
	o["allocated"] = 0
	o["pickup_spawned"] = false
	o["pickup_eta"] = -1.0
	sim.notify("Машина уехала недогруженной (%d из %d): не хватило готовых деталей. Остаток заказа снова в работе." % [v.loaded, v.need], Sim.LVL_WARN)


## Пропущенный ОТК брак возвращается рекламацией через несколько дней.
func _reclamation_check(o: Dictionary) -> void:
	var bad := int(o.get("defects", 0))
	if bad <= 0:
		return
	var ch := minf(0.95, float(bad) / maxf(1.0, float(int(o["qty"]))) * 5.0)
	var strict := sim.progress.strict() or str(o.get("kind", "")) != ""
	if strict:
		ch = 1.0   # жёсткая приёмка: брак найдут обязательно
	if sim.rng.randf() >= ch:
		return
	var comp := float(o["price"]) * bad * (6.0 if strict else 2.0)
	sim.story.scheduled_reclamation(o, bad, comp)


func on_pickup_done(v: Vehicle) -> void:
	var o := get_order(v.order_id)
	if o.is_empty():
		return
	# забрать погруженные детали из симуляции
	for iid in (sim.veh_items.get(v.id, []) as Array).duplicate():
		var it: Item = sim.items.get(iid)
		if it:
			sim.delete_item(it)
	var qty := int(o["qty"])
	var amount := float(o["price"]) * qty - float(o.get("paid_part", 0.0))
	var late_days := 0
	if sim.minute > float(o["deadline"]):
		late_days = int(ceil((sim.minute - float(o["deadline"])) / 1440.0))
	var k := maxf(1.0 - MAX_LATE_CUT, 1.0 - float(o["penalty"]) * late_days)
	var full := amount
	amount *= k
	sim.market.on_shipped(late_days)
	o["status"] = "done"
	o["paid"] = amount
	o["late_days"] = late_days
	sim.progress.on_order_done(o)
	if str(o.get("kind", "")) == "contract":
		sim.sales.on_order_closed(o, true)
	if not sim.story.defer_payment(amount, str(o["client"]), short(o)):
		sim.earn(amount, "Оплата: " + short(o))
	else:
		o["deferred"] = true
	if late_days > 0:
		sim.market.claim("liability", full - amount, "неустойка за опоздание, " + short(o))
	_reclamation_check(o)
	sim.stats["orders_done"] = int(sim.stats["orders_done"]) + 1
	var okind := str(o.get("kind", ""))
	if okind == "export" or okind == "state":
		sim.stats[okind + "_done"] = int(sim.stats.get(okind + "_done", 0)) + 1
	sim.stats["shipped"] = int(sim.stats["shipped"]) + v.loaded
	if late_days == 0:
		sim.reputation = minf(100.0, sim.reputation + 3.0)
		sim.notify("Заказ отгружен вовремя: %s. Получено %s." % [short(o), Defs.money_str(amount)], Sim.LVL_GOOD)
	else:
		sim.reputation = maxf(0.0, sim.reputation - 2.0)
		sim.notify("Заказ отгружен с опозданием на %d дн.: получено %s." % [late_days, Defs.money_str(amount)], Sim.LVL_WARN)
	# отрубить старые выполненные заказы, чтобы список не рос бесконечно
	var done := by_status(["done", "failed"])
	if done.size() > 30:
		list.erase(done[0])
