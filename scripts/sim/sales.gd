class_name Sales
extends RefCounted
## Отдел сбыта. Заказчики каждое утро шлют заявки — сбыт сам берёт те, что завод успеет
## сделать с выгодой (по проблемному месту, с учётом уже принятых). Игрок управляет стратегией:
## ассортимент, риск, минимальная маржа и долгие контракты с крупными клиентами.
## Отказы копятся в «упущенной выгоде»: видно, какого оборудования и каких людей не хватает.

const RISK_NAMES := ["С запасом", "Обычно", "Впритык"]
const RISK_K := [0.6, 0.75, 0.9]
const MARGINS := [0.05, 0.15, 0.25]
## Крупные заказчики — вымышленные.
const BIG_CLIENTS := ["АО «Агромашкомплекс»", "ПАО «Волжский автоагрегат»", "АО «Магистраль-Вагон»", "ООО «Химмашпроект»", "АО «Невский машзавод»",
	"ПАО «Сталь Приполярья»", "ООО «Агротехмаш»", "АО «Гидроузел»", "ООО «Спецтехника-Урал»", "АО «Цемагрегат»"]

var sim: Sim
var off: Dictionary = {}          ## изделие -> true: снято с ассортимента
var risk := 1                     ## 0 — с запасом, 1 — обычно, 2 — впритык (нужен ПДО)
var margin_i := 1                 ## индекс в MARGINS
var log: Array = []               ## заявки за 14 дней: {day, p, qty, sum, ok, why, procs}
var contracts: Array = []         ## долгие контракты (см. _new_contract)
var market: Dictionary = {}       ## изделие -> индекс цены 0.85–1.2 (меняется по понедельникам)
var market_prev: Dictionary = {}
var next_contract := 6.0          ## день, когда придёт следующее предложение контракта
var enabled := true               ## для тестов: без заявок и контрактов
var paused := false               ## 1.20: директор приостановил приём заказов
var queue: Array = []             ## заявки в рассмотрении: ждут, пока освободится мощность (до полутора суток)
var _qt := 0.0


func _init(s: Sim) -> void:
	sim = s


# ================================================================ заявки

func risk_k() -> float:
	var r := risk
	if r == 2 and not sim.dev.on("plan3"):
		r = 1
	return float(RISK_K[r])


func min_margin() -> float:
	return float(MARGINS[clampi(margin_i, 0, MARGINS.size() - 1)])


func in_assortment(p: String) -> bool:
	return not off.has(p)


## Все переделы изделия (с учётом деталей для сборки).
func procs_of(p: String) -> Array[String]:
	var out: Array[String] = []
	var todo: Array[String] = [p]
	while not todo.is_empty():
		var q: String = todo.pop_back()
		for o: Dictionary in Defs.route(q):
			if not out.has(str(o["op"])):
				out.append(str(o["op"]))
		for c in Defs.components(q).keys():
			todo.append(str(c))
	return out


## Каких переделов не хватает для изделия (с учётом деталей для сборки).
func missing(p: String) -> Array[String]:
	var avail := sim.prod.processes_available()
	var out: Array[String] = []
	var todo: Array[String] = [p]
	while not todo.is_empty():
		var q: String = todo.pop_back()
		for o: Dictionary in Defs.route(q):
			var pr := str(o["op"])
			if not Production.size_ok(q, pr, avail) and not out.has(pr):
				out.append(pr)
		for c in Defs.components(q).keys():
			todo.append(str(c))
	return out


## Почему сбыт откажет в заявке: [текст, переделы-виновники]. Пустой текст — берём.
func verdict(o: Dictionary) -> Array:
	var p := str(o["product"])
	if paused:
		return ["приём заказов на паузе (решение директора)", []]
	if sim.money < 0.0:
		return ["завод в долгах — новых заказов не берём", []]
	if not in_assortment(p):
		return ["снято с ассортимента", []]
	var miss := missing(p)
	if not miss.is_empty():
		var names: Array[String] = []
		var av := sim.prod.processes_available()
		for pr in miss:
			names.append(sim.prod.missing_name(p, pr, av))
		return ["нет оборудования: " + ", ".join(names), miss]
	if sim.orders.active_count() >= sim.orders.max_active():
		return ["слишком много заказов в работе (%d)" % sim.orders.max_active(), []]
	var mg := sim.office.margin(o)
	if mg < min_margin():
		return ["маржа %d%% ниже порога %d%%" % [int(round(mg * 100.0)), int(round(min_margin() * 100.0))], []]
	var li := sim.office.load_info(p, int(o["qty"]))
	if float(li[0]) > float(int(o.get("lead", 3))) * risk_k():
		if sim.office.ops_for(str(li[1])) <= 0.0:
			# 1.47: на переделе никто не работает — так и сказать, а не «не успеваем»
			return ["не успеваем: некому работать — %s" % Defs.process_name(str(li[1])).to_lower(), [str(li[1])]]
		return ["не успеваем: проблемный участок — %s" % Defs.process_name(str(li[1])).to_lower(), [str(li[1])]]
	var mat := sim.planner.material_of(p)
	if mat != "":
		# платить только за то, чего нет на складе и не едет
		var short := maxi(0, sim.planner.material_deficit(mat) + Defs.mat_qty(p) * int(o["qty"]))
		var cost := sim.material_price(mat) * short
		if cost > 0.0 and sim.money - cost < 0.0 and sim.trade_credit_left() < cost:
			return ["не хватает денег на металл", []]
	return ["", []]


## Заявку можно подержать, если отказ временный: освободится станок — возьмём.
static func _can_wait(why: String) -> bool:
	return why.begins_with("не успеваем") or why.begins_with("слишком много") or why.begins_with("не хватает денег")


## Новая заявка заказчика: взять сразу, подержать в рассмотрении или отказать.
func inquiry(o: Dictionary) -> bool:
	if not enabled:
		return false
	o["arrived"] = sim.day()
	var v := verdict(o)
	var why := str(v[0])
	if why == "":
		_take(o)
		return true
	if _can_wait(why):
		o["why"] = why
		o["procs"] = v[1]
		o["wait_until"] = sim.minute + 1.5 * 1440.0
		queue.append(o)
		return false
	_log(o, false, why, v[1])
	return false


func _take(o: Dictionary) -> void:
	_log(o, true, "", [])
	o["status"] = "offer"
	sim.orders.list.append(o)
	sim.orders.accept(int(o["id"]), true, true)


func _log(o: Dictionary, ok: bool, why: String, procs: Array) -> void:
	log.append({"day": int(o.get("arrived", sim.day())), "p": str(o["product"]), "qty": int(o["qty"]), "sum": float(o["price"]) * int(o["qty"]),
		"ok": ok, "why": why, "procs": procs, "client": str(o["client"])})


## Заявки в рассмотрении: как только освободилась мощность — берём самые выгодные.
func tick(dt: float) -> void:
	_qt -= dt
	if _qt > 0.0 or queue.is_empty():
		return
	_qt = 30.0
	queue.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["price"]) * int(a["qty"]) > float(b["price"]) * int(b["qty"]))
	for o: Dictionary in queue.duplicate():
		if sim.minute > float(o["wait_until"]):
			queue.erase(o)
			_log(o, false, str(o["why"]), o.get("procs", []))
			continue
		var v := verdict(o)
		if str(v[0]) == "":
			queue.erase(o)
			_take(o)
		elif _can_wait(str(v[0])):
			o["why"] = str(v[0])
			o["procs"] = v[1]
		else:
			queue.erase(o)
			_log(o, false, str(v[0]), v[1])


func queue_sum() -> float:
	var s := 0.0
	for o: Dictionary in queue:
		s += float(o["price"]) * int(o["qty"])
	return s


## Сводка за последние n дней: взято/отказано, суммы, причины, переделы-виновники.
func summary(days: int = 7) -> Dictionary:
	var d0 := sim.day() - days
	var taken := 0
	var taken_sum := 0.0
	var lost := 0
	var lost_sum := 0.0
	var by_proc := {}
	var by_why := {}
	for e: Dictionary in log:
		if int(e["day"]) <= d0:
			continue
		if bool(e["ok"]):
			taken += 1
			taken_sum += float(e["sum"])
			continue
		var why := str(e["why"])
		if why == "снято с ассортимента":
			continue
		lost += 1
		lost_sum += float(e["sum"])
		var key := why.split(":")[0]
		by_why[key] = float(by_why.get(key, 0.0)) + float(e["sum"])
		for pr in (e.get("procs", []) as Array):
			by_proc[str(pr)] = float(by_proc.get(str(pr), 0.0)) + float(e["sum"])
	var top := ""
	var top_v := 0.0
	for pr2 in by_proc.keys():
		if float(by_proc[pr2]) > top_v:
			top_v = float(by_proc[pr2])
			top = str(pr2)
	return {"taken": taken, "taken_sum": taken_sum, "lost": lost, "lost_sum": lost_sum, "by_proc": by_proc, "by_why": by_why, "top": top, "top_sum": top_v}


## Заявки по изделию за n дней: [шт., сумма, взято шт.].
func demand(p: String, days: int = 7) -> Array:
	var d0 := sim.day() - days
	var q := 0
	var s := 0.0
	var got := 0
	for e: Dictionary in log:
		if int(e["day"]) > d0 and str(e["p"]) == p:
			q += int(e["qty"])
			s += float(e["sum"])
			if bool(e["ok"]):
				got += int(e["qty"])
	return [q, s, got]


## Сколько штук в неделю завод может сделать (по самому медленному переделу).
func capacity_week(p: String) -> float:
	var acc := {}
	sim.office._add_route_load(acc, p, 1.0)
	var best := INF
	for pr in acc.keys():
		var ops := sim.office.ops_for(str(pr))
		if ops <= 0.0:
			return 0.0
		best = minf(best, ops * 300.0 * 5.0 / maxf(1.0, float(acc[pr])))
	return 0.0 if best == INF else best


## Если на переделе есть люди, но все на больничном или в отпуске — пояснение; иначе пусто.
func absent_note(pr: String) -> String:
	var total := 0
	var back := INF
	for w in sim.workers:
		if sim.office._can_do(w, pr):
			total += 1
			if w.sick_until < sim.minute + 720.0:
				return ""
			back = minf(back, w.sick_until)
	if total == 0:
		return ""
	return L.t("все, кто работает на переделе «%s», на больничном или в отпуске (вернутся в день %d)") % [Defs.process_name(pr), int(back / 1440.0) + 1]


## Что сделать, чтобы передел перестал быть проблемным участком.
func advice(pr: String) -> String:
	var an := absent_note(pr)
	if an != "":
		return L.t("Сейчас %s — наймите ещё одного человека, чтобы не простаивать.") % an
	if pr == "qc":
		if sim.things_of("qc").size() <= int(sim.office.ops_for("qc")):
			return L.t("Поставьте ещё стол ОТК.")
		return L.t("Наймите ещё контролёра ОТК.")
	if not sim.prod.processes_available().has(pr):
		return L.t("Купите станок для этого передела.")
	var n := 0
	for w in sim.workers:
		if sim.prod.is_operator_for(w, pr):
			n += 1
	var m := 0
	for t in sim.things_of("machine"):
		if t.process() == pr:
			m += 1
	if n < m:
		return L.t("Станки есть — наймите ещё человека на этот передел.")
	return L.t("Поставьте ещё станок и наймите человека к нему.")


# ================================================================ рынок

func price_index(p: String) -> float:
	return float(market.get(p, 1.0))


func trend(p: String) -> float:
	return price_index(p) / maxf(0.01, float(market_prev.get(p, price_index(p)))) - 1.0


func _update_market() -> void:
	market_prev = market.duplicate()
	for p in Defs.products.keys():
		var k := float(market.get(p, 1.0))
		k = k * (1.0 + sim.rng.randf_range(-0.07, 0.07)) + (1.0 - k) * 0.2
		market[p] = clampf(k, 0.85, 1.2)


# ================================================================ утро

func morning() -> void:
	if sim.weekday() == 0:
		_update_market()
		_weekly_report()
		_contract_orders()
	_contract_offers()
	# журнал — только за две недели
	var d0 := sim.day() - 14
	log = log.filter(func(e: Dictionary) -> bool: return int(e["day"]) > d0)


func _weekly_report() -> void:
	if sim.day() < 6:
		return
	var s := summary(7)
	if float(s["lost_sum"]) < 20000.0:
		return
	var tail := ""
	if str(s["top"]) != "":
		var pr := str(s["top"])
		var no_equip := pr != "qc" and not sim.prod.processes_available().has(pr)
		tail = L.t(" Больше всего потеряли из-за передела «%s» (%s): %s. %s") % [Defs.process_name(pr), L.t("нет оборудования") if no_equip else L.t("не успевает"), Defs.money_str(float(s["top_sum"])), advice(pr)]
	sim.notify(L.t("Сбыт: за неделю отказали заказчикам на %s (%d заявок).%s Подробности — «Заказы» → «Рынок».") % [Defs.money_str(float(s["lost_sum"])), int(s["lost"]), tail], Sim.LVL_WARN)


# ================================================================ контракты

func contract(id: int) -> Dictionary:
	for c: Dictionary in contracts:
		if int(c["id"]) == id:
			return c
	return {}


func by_state(st: Array) -> Array:
	return contracts.filter(func(c: Dictionary) -> bool: return st.has(str(c["status"])))


func max_contracts() -> int:
	return 1 + int(sim.progress.stage / 2)


func _contract_offers() -> void:
	# протухшие предложения
	for c: Dictionary in by_state(["offer"]):
		if sim.minute > float(c["until"]):
			c["status"] = "expired"
			sim.notify(L.t("%s не дождался ответа и отдал контракт другому заводу.") % Company.firm(str(c["client"])), Sim.LVL_INFO)
	contracts = contracts.filter(func(c: Dictionary) -> bool: return str(c["status"]) != "expired")
	if not enabled or paused or sim.money < 0.0 or float(sim.day()) < next_contract or not sim.is_workday() or sim.progress.quiet():
		return
	next_contract = float(sim.day()) + sim.rng.randf_range(7.0, 12.0) / maxf(0.6, sim.progress.offers_k()) / (1.25 if sim.market.iso_ok() else 1.0)
	if not by_state(["offer"]).is_empty() or by_state(["active", "wait"]).size() >= max_contracts():
		return
	if sim.reputation < 35.0:
		return
	if not sim.dev.on("mkt3"):
		if sim.progress.stage >= 3:
			sim.notify_once("no_sales_mgr", L.t("Крупные заказчики ищут, с кем подписать контракт, — но завод не готов: нужна ступень «Контракты» (Управление → Развитие), её держит менеджер по сбыту."), Sim.LVL_INFO, Vector2i(-1, -1), 7.0 * 1440.0)
		return
	var c := _new_contract()
	if c.is_empty():
		return
	if year_ok() and sim.rng.randf() < 0.4:
		_make_year(c)
	contracts.append(c)
	sim.calls.on_contract_offer(Company.firm(str(c["client"])))
	sim.story.letter("contract", (L.t("Договор на год: %s") if bool(c.get("year", false)) else L.t("Контракт: %s")) % Company.firm(str(c["client"])), contract_text(c), "orders", Sim.LVL_GOOD,
		[{"text": L.t("Подписать"), "hint": L.t("Поставки начнутся %s") % _day_str(int(c["start"]))}, {"text": L.t("Отказаться"), "hint": ""}, {"text": L.t("Подумать (вкладка «Контракты»)"), "hint": L.t("Предложение действует 2 дня"), "open": "orders"}], 2, {"contract": int(c["id"])})


## 1.26: договор на год — большому заводу (от «Среднего предприятия», репутация от 55), один за раз.
func year_ok() -> bool:
	if sim.progress.stage < 4 or sim.reputation < 55.0:
		return false
	for c: Dictionary in contracts:
		if bool(c.get("year", false)) and ["offer", "wait", "active"].has(str(c["status"])):
			return false
	return true


## Сколько срывов договор терпит: обычный — один, годовой — два (третий расторгает).
static func max_fails(c: Dictionary) -> int:
	return 3 if bool(c.get("year", false)) else 2


## Из обычного предложения — договор на год: партии крупнее, срок — весь игровой год, наценка меньше,
## аванс 10% при подписании, премия 8% в конце, неустойка при расторжении — 10% от недопоставленного.
func _make_year(c: Dictionary) -> void:
	var p := str(c["product"])
	var cap := capacity_week(p)
	var per := float(int(c["per_week"])) * sim.rng.randf_range(1.3, 1.8)
	if cap > 0.0:
		per = maxf(per, cap * sim.rng.randf_range(0.6, 0.95))
	var base := float(c["price"]) / (1.0 + float(c["prem"]))
	c["year"] = true
	c["per_week"] = maxi(4, int(round(per)))
	c["weeks"] = maxi(12, int(sim.season.days_per_year() / 7))
	c["prem"] = sim.rng.randf_range(0.06, 0.13)
	c["price"] = int(round(base * (1.0 + float(c["prem"])) / 10.0) * 10)
	c["until"] = sim.minute + 3.0 * 1440.0


static func total(c: Dictionary) -> float:
	return float(c["price"]) * int(c["per_week"]) * int(c["weeks"])


func _day_str(d: int) -> String:
	return L.t("в день %d (%s)") % [d, L.t(sim.weekday_name(d))]


## Предложение контракта: изделие, которое завод может делать или почти может (не хватает 1–2 переделов —
## успеете купить станки и обучить людей до начала поставок).
func _new_contract() -> Dictionary:
	var rng := sim.rng
	var pool: Array = []
	for k in sim.progress.products():
		var p := str(k)
		if not Defs.products.has(p) or not sim.office.unlocked(Defs.products[p]):
			continue
		var miss := missing(p).size()
		if miss == 0:
			pool.append(p)
			pool.append(p)
		elif miss <= 2 and not Defs.is_assembly(p):
			pool.append(p)
	if pool.is_empty():
		return {}
	var p2 := str(pool[rng.randi_range(0, pool.size() - 1)])
	var pd: Dictionary = Defs.products[p2]
	var qr: Array = pd.get("qty", [5, 15])
	var mean := (float(qr[0]) + float(qr[1])) * 0.5 * sim.progress.qty_k()
	var cap := capacity_week(p2)
	var per := mean * rng.randf_range(1.0, 1.6)
	if cap > 0.0:
		per = maxf(per, cap * rng.randf_range(0.45, 0.9))
	var per_week := maxi(2, int(round(per)))
	var pr: Array = pd.get("price", [500, 800])
	var mid := (float(pr[0]) + float(pr[1])) * 0.5 * (0.9 + sim.reputation / 500.0) * sim.progress.price_k()
	var prem := rng.randf_range(0.10, 0.25)
	var weeks := rng.randi_range(4, 8)
	var prep := 3 if missing(p2).is_empty() else rng.randi_range(7, 10)
	var start := sim.day() + prep
	while sim.weekday(start) != 0:
		start += 1
	return {"id": sim.new_id(), "client": BIG_CLIENTS[rng.randi_range(0, BIG_CLIENTS.size() - 1)], "product": p2,
		"per_week": per_week, "weeks": weeks, "price": int(round(mid * (1.0 + prem) / 10.0) * 10), "prem": prem,
		"start": start, "status": "offer", "until": sim.minute + 2.0 * 1440.0, "week_i": 0, "fails": 0, "done_w": 0,
		"order": -1}


## Текст предложения и оценка: хватит ли мощности.
func contract_text(c: Dictionary) -> String:
	var p := str(c["product"])
	var t := L.t("%s предлагает долгосрочный контракт: %d шт. «%s» каждую неделю, %d %s подряд, по %s за штуку (на %d%% выше рынка). Всего %s.\n") % [
		str(c["client"]), int(c["per_week"]), Defs.product_name(p), int(c["weeks"]), Defs.plural(int(c["weeks"]), "неделю", "недели", "недель"),
		Defs.money_str(float(c["price"])), int(round(float(c["prem"]) * 100.0)), Defs.money_str(float(c["price"]) * int(c["per_week"]) * int(c["weeks"]))]
	if bool(c.get("year", false)):
		t = L.t("%s предлагает договор на год: %d шт. «%s» каждую неделю, %d недель подряд, по %s за штуку (на %d%% выше рынка). Всего %s.\n") % [
			str(c["client"]), int(c["per_week"]), Defs.product_name(p), int(c["weeks"]), Defs.money_str(float(c["price"])), int(round(float(c["prem"]) * 100.0)), Defs.money_str(total(c))]
		t += L.t("При подписании — аванс 10%% (%s). Сорвали партию — штраф 30%% её стоимости; третий срыв — договор расторгнут и неустойка 10%% от недопоставленного. Выполнили — премия 8%% и большой плюс к репутации.\n") % Defs.money_str(total(c) * 0.1)
	else:
		t += L.t("Первая партия — в неделю со дня %d, каждая партия — к пятнице. Сорвали партию — штраф 30%% её стоимости, две — контракт расторгнут.\n") % int(c["start"])
	t += assess(c)
	return t


func assess(c: Dictionary) -> String:
	var p := str(c["product"])
	var miss := missing(p)
	if not miss.is_empty():
		var names: Array[String] = []
		var av := sim.prod.processes_available()
		for pr in miss:
			names.append(sim.prod.missing_name(p, pr, av))
		return L.t("Сейчас сделать нельзя — нет оборудования: %s. До начала поставок %d дн.: поставьте станки и наймите людей.") % [", ".join(names), maxi(0, int(c["start"]) - sim.day())]
	var cap := capacity_week(p)
	var need := float(int(c["per_week"]))
	if cap <= 0.0:
		var acc0 := {}
		sim.office._add_route_load(acc0, p, 1.0)
		for pr0 in acc0.keys():
			var an := absent_note(str(pr0))
			if an != "":
				return L.t("Сейчас мощность нулевая: %s. Если людей больше нет — наймите.") % an
	if cap >= need * 1.6:
		return L.t("Мощности хватает с запасом: можете делать ~%d шт. в неделю.") % int(cap)
	if cap >= need:
		return L.t("Мощности хватает впритык (~%d шт. в неделю): на другие заказы времени останется мало.") % int(cap)
	var acc := {}
	sim.office._add_route_load(acc, p, 1.0)
	var worst := ""
	var wv := INF
	for pr2 in acc.keys():
		var v := sim.office.ops_for(str(pr2)) * 1500.0 / maxf(1.0, float(acc[pr2]))
		if v < wv:
			wv = v
			worst = str(pr2)
	return L.t("Мощности не хватает: сейчас ~%d шт. в неделю из %d. Проблемное место — %s. %s") % [int(cap), int(need), Defs.process_name(worst).to_lower(), advice(worst)]


func sign(id: int) -> String:
	var c := contract(id)
	if c.is_empty() or str(c["status"]) != "offer":
		return L.t("Предложение уже недоступно")
	c["status"] = "wait" if sim.day() < int(c["start"]) else "active"
	if bool(c.get("year", false)):
		c["advance"] = total(c) * 0.1
		sim.earn(float(c["advance"]), "Оплата: аванс по договору на год, " + str(c["client"]))
	sim.notify(L.t("Контракт подписан: %s, %d шт. «%s» в неделю. Первая партия — в неделю со дня %d.") % [Company.firm(str(c["client"])), int(c["per_week"]), Defs.product_name(str(c["product"])), int(c["start"])], Sim.LVL_GOOD)
	if sim.weekday() == 0 and sim.day() >= int(c["start"]):
		_contract_orders()
	return ""


func decline(id: int) -> void:
	var c := contract(id)
	if not c.is_empty() and str(c["status"]) == "offer":
		contracts.erase(c)


## Понедельник: недельные партии по действующим контрактам.
func _contract_orders() -> void:
	for c: Dictionary in by_state(["wait", "active"]):
		if sim.day() < int(c["start"]):
			continue
		if int(c["order"]) >= 0:
			var prev := sim.orders.get_order(int(c["order"]))
			if not prev.is_empty() and ["active", "ready", "shipping"].has(str(prev["status"])):
				continue   # прошлая партия ещё в работе — новую не открываем
		c["status"] = "active"
		var p := str(c["product"])
		var o := {
			"id": sim.new_id(), "client": str(c["client"]), "product": p, "qty": int(c["per_week"]), "price": int(c["price"]),
			"lead": 4, "deadline": sim.orders.deadline_after(4), "penalty": Defs.b("late_penalty_per_day"), "status": "offer",
			"shipped": 0, "allocated": 0, "created": sim.minute, "expires": sim.minute + 1440.0, "pickup_eta": -1.0,
			"pickup_spawned": false, "accepted": -1.0, "kind": "contract", "contract": int(c["id"]), "prio": 1,
		}
		sim.orders.list.append(o)
		sim.orders.accept(int(o["id"]), true, true)
		c["order"] = int(o["id"])
		c["week_i"] = int(c["week_i"]) + 1


## Партия по контракту отгружена или сорвана.
func on_order_closed(o: Dictionary, ok: bool) -> void:
	var c := contract(int(o.get("contract", -1)))
	if c.is_empty():
		return
	if ok:
		c["done_w"] = int(c["done_w"]) + 1
	else:
		c["fails"] = int(c["fails"]) + 1
		var fine := float(o["price"]) * int(o["qty"]) * 0.3
		sim.spend(fine, "Штраф: срыв партии по контракту, " + str(c["client"]))
		sim.market.claim("liability", fine, "штраф по контракту, " + str(c["client"]))
		if int(c["fails"]) >= max_fails(c):
			c["status"] = "broken"
			if bool(c.get("year", false)):
				var left := float(c["price"]) * int(c["per_week"]) * maxi(0, int(c["weeks"]) - int(c["done_w"]) - int(c["fails"]))
				var pen := left * 0.1
				sim.spend(pen, "Штраф: неустойка за расторжение договора на год, " + str(c["client"]))
				sim.reputation = maxf(0.0, sim.reputation - 15.0)
				sim.notify(L.t("%s расторг договор на год: сорваны три партии. Неустойка %s, репутация сильно упала.") % [Company.firm(str(c["client"])), Defs.money_str(pen)], Sim.LVL_BAD)
				return
			sim.reputation = maxf(0.0, sim.reputation - 10.0)
			sim.notify(L.t("%s расторг контракт: сорваны две партии. Репутация упала.") % Company.firm(str(c["client"])), Sim.LVL_BAD)
			return
		var left_f := max_fails(c) - int(c["fails"])
		sim.notify(L.t("Сорвана партия по %s с %s: штраф %s. %s") % [L.t("договору") if bool(c.get("year", false)) else L.t("контракту"), Company.firm(str(c["client"])), Defs.money_str(fine),
			L.t("Ещё один срыв — и контракт расторгнут.") if left_f <= 1 else L.t("Ещё %d срыва — и договор расторгнут.") % left_f], Sim.LVL_BAD)
	if int(c["done_w"]) + int(c["fails"]) >= int(c["weeks"]):
		c["status"] = "done"
		var yr := bool(c.get("year", false))
		var bonus := total(c) * (0.08 if yr else 0.05)
		sim.earn(bonus, "Оплата: премия за выполнение %s, %s" % ["договора на год" if yr else "контракта", str(c["client"])])
		sim.reputation = minf(100.0, sim.reputation + (12.0 if yr else 6.0))
		sim.stats["contracts_done"] = int(sim.stats.get("contracts_done", 0)) + 1
		if yr:
			sim.stats["year_contracts_done"] = int(sim.stats.get("year_contracts_done", 0)) + 1
		sim.notify(L.t("Контракт с %s выполнен! Премия %s, репутация выросла.") % [Company.firm(str(c["client"])), Defs.money_str(bonus)], Sim.LVL_GOOD)


# ================================================================ сохранение

func to_dict() -> Dictionary:
	return {"off": off, "risk": risk, "margin": margin_i, "log": log, "contracts": contracts, "market": market,
		"market_prev": market_prev, "next": next_contract, "queue": queue, "paused": paused}


func from_dict(d: Dictionary) -> void:
	off = d.get("off", {})
	risk = int(d.get("risk", 1))
	margin_i = int(d.get("margin", 1))
	log = d.get("log", [])
	contracts = d.get("contracts", [])
	market = d.get("market", {})
	market_prev = d.get("market_prev", {})
	next_contract = float(d.get("next", float(sim.day()) + 5.0))
	queue = d.get("queue", [])
	paused = bool(d.get("paused", false))
