class_name Office
extends RefCounted
## Управление заводом: ИТР-отделы и их кабинеты,
## политики начальника цеха, исследования техотдела, налоги, кредиты, поставщики,
## отчёт о движении денег по неделям.

const CATS := {
	"sales": "Выручка от заказов", "materials": "Металл", "consumables": "Расходники", "wages": "Зарплата",
	"energy": "Электроэнергия", "rent": "Аренда", "maintenance": "Обслуживание и ремонт",
	"capex": "Стройка и оборудование", "taxes": "Налоги", "fines": "Штрафы проверок", "claims": "Неустойки заказчикам",
	"finance": "Кредиты и лизинг",
	"hr": "Найм и премии", "insurance": "Страхование", "other": "Прочее",
}
const CAT_ORDER := ["sales", "materials", "consumables", "wages", "energy", "rent", "maintenance", "hr", "taxes", "fines", "claims", "insurance", "finance", "capex", "other"]
const DESK_LABELS := {
	"foreman": "Заполняет наряды и табель", "chief": "Проводит планёрку по телефону",
	"accountant": "Ведёт учёт, считает налоги", "buyer": "Обзванивает поставщиков",
	"dispatcher": "Составляет план производства", "hr": "Разбирает анкеты кандидатов",
	"technologist": "Разрабатывает техпроцесс",
	"sales_manager": "Обзванивает заказчиков", "safety_engineer": "Заполняет журнал инструктажей",
	"chief_engineer": "Сверяет график ППР", "lawyer": "Готовит претензию",
}

var sim: Sim
var policies: Dictionary = {"rush": false, "overtime": false, "auto_accept": false, "auto_hire": false}
var supplier := "base"
var research_done: Array = []
var research_cur := ""
var research_pts: Dictionary = {}
var weeks: Array = []            ## [{week, cats}] — новые в начале
var loans: Array = []            ## [{amount, payment, left, rate}]
var vacancies: Array = []        ## профессии уволившихся — для кадровика
var research_today := 0.0
var _t := 0.0
var _shift_cache: Dictionary = {}   ## смена -> {k, defect, covered}
var all_depts := false              ## для тестов старых версий: все отделы считаются работающими


func _init(s: Sim) -> void:
	sim = s


# ---------------------------------------------------------------- отделы и рабочие места

func staff(d: String) -> Array[Worker]:
	var prof := str(Defs.departments.get(d, {}).get("prof", ""))
	var out: Array[Worker] = []
	for w in sim.workers:
		if w.prof == prof:
			out.append(w)
	return out


## Насколько хорошо специалист устроен: свой отдел — 1, общая контора — 0,7, нет стола — 0.
func desk_k(w: Worker) -> float:
	var desk: Thing = sim.things.get(w.desk_id)
	if desk == null or not desk.built or desk.demolish or desk.def_id != "office_desk":
		return 0.0
	var r := sim.rooms.room_of_thing(desk)
	if r == null or not r.valid:
		return 0.0
	var own := str(Defs.departments.get(w.dept(), {}).get("room", ""))
	if r.type == own:
		return 1.0
	if r.type == "office":
		return Defs.b("office_shared_k")
	return 0.0


func skill_k(w: Worker) -> float:
	return 0.6 + 0.08 * w.skill(w.main_skill())


## Эффективность отдела 0…~1,4: лучший специалист с учётом кабинета и навыка.
func eff(d: String) -> float:
	if not sim.progress.dept_open(d):
		return 0.0
	var best := 0.0
	for w in staff(d):
		best = maxf(best, desk_k(w) * skill_k(w))
	return best


func active(d: String) -> bool:
	return all_depts or eff(d) > 0.0


## Стол для специалиста: закреплённый или свободный, свой отдел лучше общей конторы.
func desk_for(w: Worker) -> Thing:
	var cur: Thing = sim.things.get(w.desk_id)
	if cur and cur.built and not cur.demolish and cur.def_id == "office_desk" and _desk_score(w, cur) > 0.0:
		return cur
	w.desk_id = -1
	var taken := {}
	for o in sim.workers:
		if o != w and o.desk_id >= 0:
			taken[o.desk_id] = true
	var best: Thing = null
	var bs := 0.0
	for t: Thing in sim.things.values():
		if t.def_id != "office_desk" or not t.built or t.demolish or taken.has(t.id):
			continue
		var sc := _desk_score(w, t)
		if sc > bs:
			bs = sc
			best = t
	if best:
		w.desk_id = best.id
	return best


func _desk_score(w: Worker, t: Thing) -> float:
	var r := sim.rooms.room_of_thing(t)
	if r == null or not r.valid:
		return 0.01  # стол без кабинета — лучше, чем ничего
	var own := str(Defs.departments.get(w.dept(), {}).get("room", ""))
	if r.type == own:
		return 3.0
	if r.type == "office":
		return 2.0
	if Rooms.OFFICE_TYPES.has(r.type):
		return 0.0  # чужой отдел
	return 0.01


func room_status(d: String) -> Array:
	var room := str(Defs.departments.get(d, {}).get("room", ""))
	if not sim.rooms.of_type(room).is_empty():
		return [1, "✓ " + Defs.room_name(room)]
	if not sim.rooms.of_type("office").is_empty():
		return [0, L.t("в общей конторе (на 30% хуже)")]
	var rd: Dictionary = Defs.rooms.get(room, {})
	var needs: Array[String] = []
	for n: Dictionary in rd.get("needs", []):
		needs.append(L.t(str(n.get("text", ""))))
	if not (rd.get("floors", []) as Array).is_empty():
		needs.append(L.t("линолеум"))
	return [-1, L.t("✗ нет: постройте помещение «%s» (%s)") % [Defs.room_name(room), ", ".join(needs)]]


# ---------------------------------------------------------------- исследования

func has_tech(k: String) -> bool:
	return research_done.has(k)


func unlocked(def: Dictionary) -> bool:
	var r := str(def.get("research", ""))
	return r == "" or has_tech(r)


func research_available(k: String) -> bool:
	if has_tech(k):
		return false
	for req in Defs.research.get(k, {}).get("req", []):
		if not has_tech(str(req)):
			return false
	return true


## 1.15: дерево разработок открывается, когда в техотделе есть технолог.
func research_open() -> bool:
	return not staff("tech").is_empty()


## Состояние разработки для дерева: works — изучено, busy — в работе, ready — можно начать, locked.
func research_status(id: String) -> String:
	if has_tech(id):
		return "works"
	if research_cur == id:
		return "busy"
	if research_open() and research_available(id):
		return "ready"
	return "locked"


## Ветки в порядке data/research.json, разработки каждой — по ярусам зависимостей: [[ветка, [[id, ...], ...]], ...].
static func research_layout() -> Array:
	var branches: Array[String] = []
	for k in Defs.research.keys():
		var b := str(Defs.research[k]["branch"])
		if not branches.has(b):
			branches.append(b)
	var out: Array = []
	for b2 in branches:
		var depth := {}
		var ids: Array[String] = []
		for k2 in Defs.research.keys():
			if str(Defs.research[k2]["branch"]) == b2:
				ids.append(str(k2))
		for _pass in 4:
			for id in ids:
				var dd := 0
				for rq in Defs.research[id].get("req", []):
					if depth.has(str(rq)):
						dd = maxi(dd, int(depth[str(rq)]) + 1)
				depth[id] = dd
		var rows: Array = []
		for id2 in ids:
			var d := int(depth[id2])
			while rows.size() <= d:
				rows.append([])
			(rows[d] as Array).append(id2)
		out.append([b2, rows])
	return out


func set_research(k: String) -> void:
	if research_available(k):
		research_cur = k


## Очков исследований в смену от техотдела (для подсказки).
func research_rate() -> float:
	var total := 0.0
	for w in staff("tech"):
		total += desk_k(w) * skill_k(w)
	return total * Defs.b("research_per_hour") * 8.0


func _add_research(pts: float) -> void:
	research_today += pts
	if research_cur == "" or not research_available(research_cur):
		research_cur = ""
		for k in Defs.research.keys():
			if research_available(str(k)):
				research_cur = str(k)
				break
		if research_cur == "":
			return
		sim.notify(L.t("Техотдел сам взялся за разработку: «%s». Выбрать другое — в окне «Разработки».") % Defs.research_name(research_cur), Sim.LVL_INFO)
	var cur := research_cur
	research_pts[cur] = float(research_pts.get(cur, 0.0)) + pts
	var cost := float(Defs.research[cur]["cost"])
	if float(research_pts[cur]) >= cost:
		research_done.append(cur)
		research_pts.erase(cur)
		research_cur = ""
		sim.thing_rev += 1
		sim.notify(L.t("Техотдел закончил разработку: «%s»! %s") % [Defs.research_name(cur), Defs.research_desc(cur)], Sim.LVL_GOOD)


## Специалист поработал за столом dt минут.
func add_work(w: Worker, dt: float) -> void:
	if w.prof == "technologist":
		_add_research(dt / 60.0 * Defs.b("research_per_hour") * desk_k(w) * skill_k(w))


# ---------------------------------------------------------------- влияние на производство

## Мастера на смене: множитель скорости и брака для этой смены.
func _shift_info(sh: int) -> Dictionary:
	if _shift_cache.has(sh):
		return _shift_cache[sh]
	var n := 0
	var cap := 0.0
	var bonus := 0.0
	for w in sim.workers:
		if not w.present or w.shift != sh:
			continue
		if w.prof == "foreman":
			var k := desk_k(w)
			if k > 0.0:
				cap += Defs.b("foreman_cap")
				bonus = maxf(bonus, (Defs.b("foreman_speed") + 0.01 * w.skill("manage")) * k)
		elif not w.is_itr():
			n += 1
	var cover := 1.0 if n == 0 else minf(1.0, cap / float(n))
	var info := {"k": 1.0 + bonus * cover, "defect": 1.0 - 0.15 * cover, "covered": cover, "n": n,
		"chaos": n > int(Defs.b("no_master_from")) and cap <= 0.0}
	if info["chaos"]:
		info["k"] = 0.9
	_shift_cache[sh] = info
	return info


func speed_k(w: Worker) -> float:
	if w.is_itr():
		return 1.0
	var info := _shift_info(w.shift)
	var k := float(info["k"])
	if active("chief"):
		k += Defs.b("chief_speed")
		if policies["rush"]:
			k += Defs.b("rush_speed")
	if has_tech("five_s"):
		k += 0.05
	if has_tech("lean"):
		k += 0.05
	return k


func defect_k(w: Worker) -> float:
	var k := float(_shift_info(w.shift)["defect"])
	if rush_on():
		k *= Defs.b("rush_defect")
	if has_tech("spc"):
		k *= 0.75
	return k * sim.story.perk("defect_k")


func rush_on() -> bool:
	return (bool(policies["rush"]) and active("chief")) or sim.story.has_mod("rush")


func overtime_on() -> bool:
	return bool(policies["overtime"]) and active("chief")


func absence_k(w: Worker) -> float:
	for o in sim.workers:
		if o.prof == "foreman" and o.shift == w.shift and desk_k(o) > 0.0:
			return 0.5
	return 1.0


func op_time_k(process: String) -> float:
	var k := 1.0
	if has_tech("fast_cutting") and process in ["turning", "milling", "drilling"]:
		k *= 0.85
	if has_tech("heat_modes") and process == "heat":
		k *= 0.75
	if has_tech("weld_jigs") and process == "welding":
		k *= 0.8
	return k


func process_defect_k(process: String) -> float:
	return 0.7 if has_tech("weld_jigs") and process == "welding" else 1.0


func setup_time() -> float:
	var t := Defs.b("setup_time")
	if active("pdo"):
		t *= 0.5
	if sim.dev and sim.dev.on("plan2"):
		t *= 0.7   # Развитие → «Партии»
	if has_tech("lean"):
		t *= 0.5
	return t * sim.story.perk("setup_k")


func carry_cap() -> int:
	return 9 if has_tech("kanban") else 6


## 1.39: название текущего поставщика на языке игры.
func supplier_name() -> String:
	var key := supplier if active("supply") else "base"
	var nm := str(supplier_def().get("name", ""))
	return L.dt("supplier.%s.name" % key, nm, {"name": L.translit(nm)})


func supplier_def() -> Dictionary:
	var key := supplier if active("supply") else "base"
	return Defs.suppliers.get(key, Defs.suppliers.get("base", {}))


func material_k() -> float:
	var k := float(supplier_def().get("k", 1.0))
	if has_tech("nesting"):
		k *= 0.92
	return k


func candidates_n() -> int:
	return int(Defs.b("hr_candidates")) if active("hr") else 4


func ad_cost_k() -> float:
	return 0.5 if active("hr") else 1.0


func tax_rate() -> float:
	return maxf(0.0, (Defs.b("tax_rate_acc") if active("accounting") else Defs.b("tax_rate")) - (sim.town.tax_break() if sim.town else 0.0))


func loan_rate() -> float:
	if sim.dev and sim.dev.on("fin3"):
		return 0.14   # Развитие → «Банк и лизинг»
	return Defs.b("loan_rate_acc") if active("accounting") else Defs.b("loan_rate")


func rest_k() -> float:
	return 0.85 if has_tech("gymnastics") else 1.0


func skill_growth_k() -> float:
	return 2.0 if has_tech("training") else 1.0


# ---------------------------------------------------------------- деньги: учёт по неделям, налоги, кредиты

func week_no() -> int:
	return int((sim.day() - 1) / 7) + 1


static func cat_of(reason: String) -> String:
	var r := reason.to_lower()
	var map := [[L.t("развитие:"), "capex"], [L.t("страхов"), "insurance"], [L.t("оплата"), "sales"], [L.t("металл"), "materials"], [L.t("расходники"), "consumables"],
		[L.t("зарплата"), "wages"], [L.t("расчёт при увольнении"), "wages"], [L.t("сверхурочн"), "wages"], [L.t("стипендия"), "wages"],
		[L.t("обучение"), "hr"], [L.t("инструктаж"), "hr"], [L.t("договор с пту"), "hr"],
		[L.t("премия"), "hr"], [L.t("объявление"), "hr"], [L.t("электроэнергия"), "energy"],
		[L.t("аренда"), "rent"], [L.t("отопление"), "energy"], [L.t("охрана"), "other"], [L.t("песок"), "other"], [L.t("юрист"), "other"], [L.t("обслуживание"), "maintenance"], [L.t("ремонт"), "maintenance"],
		[L.t("рекламац"), "claims"], [L.t("неустойк"), "claims"], [L.t("срыв госзаказа"), "claims"], [L.t("срыв партии"), "claims"], [L.t("перенос срока"), "claims"],
		[L.t("пени"), "fines"], [L.t("штраф"), "fines"], [L.t("налог"), "taxes"],
		[L.t("лизинг"), "finance"], [L.t("реклама в"), "other"],
		[L.t("кредит"), "finance"], [L.t("процент"), "finance"], [L.t("погашение"), "finance"],
		[L.t("стройка"), "capex"], [L.t("покупка"), "capex"], [L.t("электромонтаж"), "capex"], [L.t("отмена"), "capex"],
		[L.t("возврат"), "capex"], [L.t("снос"), "capex"], [L.t("демонтаж"), "capex"], [L.t("техприсоединение"), "capex"]]
	for pair in map:
		if r.contains(str(pair[0])):
			return str(pair[1])
	return "other"


func book(reason: String, v: float) -> void:
	var wk := week_no()
	if weeks.is_empty() or int(weeks[0]["week"]) != wk:
		weeks.push_front({"week": wk, "cats": {}})
		if weeks.size() > 12:
			weeks.resize(12)
	var cats: Dictionary = weeks[0]["cats"]
	var c := cat_of(reason)
	cats[c] = float(cats.get(c, 0.0)) + v


func week_total(wd: Dictionary, include_capex: bool = false) -> float:
	var t := 0.0
	var cats: Dictionary = wd["cats"]
	for c in cats.keys():
		if (c == "capex" or c == "finance") and not include_capex:
			continue
		t += float(cats[c])
	return t


## Доля зарплат в выручке за последние n недель (0, если выручки не было).
func payroll_share(n: int = 4) -> float:
	var w := 0.0
	var r := 0.0
	for wk: Dictionary in weeks.slice(0, n):
		var cats: Dictionary = wk["cats"]
		w -= float(cats.get("wages", 0.0))
		r += float(cats.get("sales", 0.0))
	return w / r if r > 1000.0 else 0.0


## Бухгалтер предупреждает: зарплаты съедают выручку (РП-32).
func _payroll_check() -> void:
	if not active("accounting") or weeks.size() < 3:
		return
	var sh := payroll_share(4)
	if sh > 0.7:
		sim.notify(L.t("Бухгалтер: зарплаты съедают %d%% выручки за последние недели. Посмотрите, кто простаивает (Производство → Станки), или возьмите больше заказов.") % int(round(sh * 100.0)), Sim.LVL_WARN)


## Пятница, после зарплаты: налог с выручки недели, штрафы без бухгалтерии.
func on_payday() -> void:
	_payroll_check()
	var sales := 0.0
	if not weeks.is_empty() and int(weeks[0]["week"]) == week_no():
		sales = float((weeks[0]["cats"] as Dictionary).get("sales", 0.0))
	var tax := sales * tax_rate()
	if tax > 0.0:
		sim.spend(tax, "Налог УСН %d%% с выручки недели" % int(round(tax_rate() * 100.0)))
	var need_acc := sim.workers.size() > int(Defs.b("staff_needs_accounting"))
	if need_acc and not active("accounting"):
		if sim.rng.randf() < Defs.b("tax_penalty_chance"):
			var pen := Defs.b("tax_penalty_base") + tax * 0.5
			sim.spend(pen, "Пени и штраф налоговой: учёт «на коленке»")
			sim.notify(L.t("Налоговая выписала штраф %s: на заводе больше %d человек, а бухгалтерии нет. Постройте бухгалтерию и наймите бухгалтера.") % [Defs.money_str(pen), int(Defs.b("staff_needs_accounting"))], Sim.LVL_BAD)
		else:
			sim.notify(L.t("Учёт ведётся «на коленке»: в штате больше %d человек, нужна бухгалтерия, иначе налоговая будет штрафовать.") % int(Defs.b("staff_needs_accounting")), Sim.LVL_WARN)


func loan_options() -> Array:
	return [[800000.0, 26], [3000000.0, 52]]


## Большой кредит банк даёт только заводу с налаженными финансами (Развитие → «Банк и лизинг»).
func loan_ok(amount: float) -> bool:
	return amount <= 800000.0 or sim.dev.on("fin3")


func loan_payment(amount: float, weeks_n: int, rate: float) -> float:
	var r := rate / 52.0
	return amount * r / (1.0 - pow(1.0 + r, -weeks_n))


func take_loan(amount: float, weeks_n: int) -> String:
	if sim.progress.stage < 2:
		return L.t("Банки кредитуют предприятия от этапа «Мастерская». Пока — гранты и программы поддержки")
	if loans.size() >= 2:
		return L.t("Банк не даст больше двух кредитов одновременно")
	if not loan_ok(amount):
		return L.t("Кредит больше 800 тыс. ₽ — после ступени «Банк и лизинг» (Управление → Развитие)")
	if sim.reputation < 30.0:
		return L.t("Банк отказал: слишком низкая репутация")
	var rate := loan_rate()
	var pay := loan_payment(amount, weeks_n, rate)
	loans.append({"amount": amount, "payment": pay, "left": weeks_n, "rate": rate})
	sim.earn(amount, "Кредит получен: %s на %d нед." % [Defs.money_str(amount), weeks_n])
	sim.notify(L.t("Банк выдал кредит %s под %d%% годовых. Платёж %s каждый понедельник.") % [Defs.money_str(amount), int(round(rate * 100.0)), Defs.money_str(pay)], Sim.LVL_GOOD)
	return ""


## Льготный заём (фонд, госпрограмма): без проверки репутации и лимита банка.
func add_loan(amount: float, weeks_n: int, rate: float, title: String) -> void:
	var pay := loan_payment(amount, weeks_n, rate)
	loans.append({"amount": amount, "payment": pay, "left": weeks_n, "rate": rate})
	sim.earn(amount, "Кредит получен: %s" % title)
	sim.notify(L.t("%s: %s под %d%% годовых, платёж %s по понедельникам.") % [L.tx(title), Defs.money_str(amount), int(round(rate * 100.0)), Defs.money_str(pay)], Sim.LVL_GOOD)


## Долг без получения денег (например, налоги прежнего владельца).
func add_debt(amount: float, weeks_n: int, title: String) -> void:
	var pay := amount / maxf(1.0, float(weeks_n))
	loans.append({"amount": amount, "payment": pay, "left": weeks_n, "rate": 0.0, "title": title})


func debt() -> float:
	var t := 0.0
	for l: Dictionary in loans:
		t += float(l["payment"]) * int(l["left"])
	return t


func on_monday() -> void:
	for l: Dictionary in loans:
		sim.spend(float(l["payment"]), "Погашение кредита с процентами")
		l["left"] = int(l["left"]) - 1
	var before := loans.size()
	loans = loans.filter(func(l: Dictionary) -> bool: return int(l["left"]) > 0)
	if loans.size() < before:
		sim.notify(L.t("Кредит полностью погашен."), Sim.LVL_GOOD)


# ---------------------------------------------------------------- себестоимость

## Оценка себестоимости одного изделия: металл, работа, расходники, энергия, накладные.
func unit_cost(p: String) -> float:
	var pd: Dictionary = Defs.products.get(p, {})
	var c := 0.0
	if Defs.is_assembly(p):
		var comps := Defs.components(p)
		for k in comps.keys():
			c += unit_cost(str(k)) * int(comps[k])
	else:
		var mat := str(pd.get("material", ""))
		c += float(Defs.materials.get(mat, {}).get("price", 0)) * Defs.mat_qty(p) * material_k() * 1.08
	for o: Dictionary in Defs.route(p):
		var pr := str(o["op"])
		var mins := float(o.get("time", 30)) * op_time_k(pr)
		if pr == "heat":
			mins /= 4.0
		c += mins / 60.0 * 430.0
		c += mins / 60.0 * 8.0 * Defs.b("power_price_kwh")
		var prd: Dictionary = Defs.processes.get(pr, {})
		var cn := str(prd.get("cons", ""))
		if cn != "":
			var cd: Dictionary = Defs.consumables.get(cn, {})
			var use := float(o.get("cons", prd.get("cons_use", 1.0)))
			c += float(cd.get("price", 0)) / maxf(1.0, float(cd.get("units", 1))) * use
	return c * 1.12


# ---------------------------------------------------------------- такт: мысли, автоприём, автонайм

func tick(dt: float) -> void:
	_shift_cache.clear()
	_t -= dt
	if _t > 0.0:
		return
	_t = 60.0
	for w in sim.workers:
		if not w.present or w.is_itr():
			continue
		var info := _shift_info(w.shift)
		if bool(info["chaos"]):
			Mood.add(sim, w, "no_master")
		elif float(info["covered"]) > 0.5:
			for o in sim.workers:
				if o.prof == "foreman" and o.present and o.shift == w.shift and o.skill("manage") >= 5:
					Mood.add(sim, w, "master_good")
					break
		if rush_on():
			Mood.add(sim, w, "rush")
		if overtime_on():
			Mood.add(sim, w, "overtime")
		if has_tech("five_s"):
			Mood.add(sim, w, "five_s")
	var chaos := false
	for sh in [0, 1]:
		if bool(_shift_info(sh)["chaos"]):
			chaos = true
	if chaos:
		sim.notify_once("no_master", L.t("Смена больше %d человек без мастера: бардак, работа идёт на 10%% медленнее. Наймите мастера участка и поставьте ему стол (конторка мастера или контора).") % int(Defs.b("no_master_from")), Sim.LVL_WARN, Vector2i(-1, -1), 1440.0)


## Утро: кадровик закрывает вакансии (заказы берёт отдел сбыта — см. Sales).
func morning() -> void:
	research_today = 0.0
	if bool(policies["auto_hire"]) and sim.dev.on("hr3") and not vacancies.is_empty():
		_auto_hire()


func margin(o: Dictionary) -> float:
	var p := str(o["product"])
	var price := float(o["price"])
	if price <= 0.0:
		return 0.0
	return (price - unit_cost(p)) / price


## Сколько рабочих дней займут уже принятые заказы (плюс, если задано, новый заказ):
## считается по самому загруженному переделу — где меньше всего людей и станков на объём работы.
func load_days(extra_p: String = "", extra_qty: int = 0) -> float:
	return float(load_info(extra_p, extra_qty)[0])


## [дней, проблемный участок (процесс)].
func load_info(extra_p: String = "", extra_qty: int = 0) -> Array:
	var acc := {}
	for o: Dictionary in sim.orders.by_status(["active"]):
		var p := str(o["product"])
		var left := maxi(0, sim.orders.remaining(o) - sim.ok_in_storage(p))
		_add_route_load(acc, p, float(left))
	if extra_p != "" and extra_qty > 0:
		_add_route_load(acc, extra_p, float(extra_qty))
	# человек, который умеет несколько загруженных переделов, делит смену между ними
	var share := {}
	for w in sim.workers:
		if w.sick_until >= sim.minute + 720.0:
			continue   # на больничном или в отпуске — не считаем
		var can: Array[String] = []
		for pr0 in acc.keys():
			if _can_do(w, str(pr0)):
				can.append(str(pr0))
		for pr1 in can:
			share[pr1] = float(share.get(pr1, 0.0)) + 1.0 / float(can.size())
	var best := 0.0
	var best_pr := ""
	for pr in acc.keys():
		var ops := minf(float(share.get(pr, 0.0)), ops_for(str(pr)))
		# ~300 минут чистой работы за смену: обед, перекуры, туалет, переналадка
		var d := minf(99.0, float(acc[pr]) / (ops * 300.0)) if ops > 0.05 else 99.0
		if d > best:
			best = d
			best_pr = str(pr)
	if extra_p != "" and extra_qty > 0:
		best += route_latency(extra_p)
	return [best, best_pr]


## Сколько дней изделие «лежит» между переделами (перенос, очередь, партия печи и покраски,
## сборка из деталей). Узкое место этого не видит — без поправки сбыт брал многооперационные
## заказы впритык и срывал их (1.9.1).
func route_latency(p: String) -> float:
	var rt := Defs.route(p)
	var lat := 0.3 * maxf(0.0, float(rt.size() - 1))
	for o: Dictionary in rt:
		if str(o["op"]) in ["heat", "paint"]:
			lat += 0.3
	var comps := Defs.components(p)
	if not comps.is_empty():
		var cl := 0.0
		for c in comps.keys():
			cl = maxf(cl, route_latency(str(c)))
		lat += cl + 0.3
	return lat


func _add_route_load(acc: Dictionary, p: String, n: float) -> void:
	if n <= 0.0:
		return
	# тяжёлые детали без кран-балки обрабатываются дольше
	var heavy := 1.0
	if bool(Defs.products.get(p, {}).get("heavy", false)) and sim.things_of("crane").is_empty():
		heavy = 1.0 / maxf(0.1, Defs.b("crane_heavy_k"))
	for o: Dictionary in Defs.route(p):
		var pr := str(o["op"])
		var mins := float(o.get("time", 30)) * op_time_k(pr) * op_skill_k(pr) * heavy
		if pr == "heat":
			mins /= 6.0
		acc[pr] = float(acc.get(pr, 0.0)) + mins * n
	# ОТК: каждую деталь проверяют на столе контролёра (если он есть)
	if not sim.things_of("qc").is_empty():
		var qt := float(Defs.products.get(p, {}).get("qc_time", 6)) * op_skill_k("qc")
		acc["qc"] = float(acc.get("qc", 0.0)) + qt * n
	var comps := Defs.components(p)
	for c in comps.keys():
		_add_route_load(acc, str(c), n * int(comps[c]))


## Во сколько раз операция дольше нормы у тех, кто на этом переделе работает (по навыку).
func op_skill_k(pr: String) -> float:
	var sk := "qc" if pr == "qc" else str(Defs.processes.get(pr, {}).get("skill", "turning"))
	var t := 0.0
	var n := 0
	for w in sim.workers:
		if _can_do(w, pr):
			t += clampf(1.35 - 0.065 * w.skill(sk), 0.6, 1.35)
			n += 1
	return t / float(n) if n > 0 else 1.0


## Сколько человек реально может работать на переделе: не больше, чем исправных станков.
func ops_for(pr: String) -> float:
	var n := 0
	for w in sim.workers:
		if _can_do(w, pr) and w.sick_until < sim.minute + 720.0:
			n += 1
	var m := 0
	if pr == "qc":
		m = sim.things_of("qc").size()
	else:
		for t in sim.things_of("machine"):
			if t.process() == pr and t.enabled and not t.broken:
				m += 1
	return float(mini(n, m))


## Работает ли человек на этом переделе (ОТК — контролёры и все, у кого навык контроля от 2).
func _can_do(w: Worker, pr: String) -> bool:
	if pr == "qc":
		return not w.is_itr() and (w.prof == "qc" or w.skill("qc") >= 2)
	return sim.prod.is_operator_for(w, pr)


func load_ops() -> float:
	var ops := 0
	for w in sim.workers:
		if not w.is_itr() and w.prof != "laborer" and w.prof != "builder" and w.prof != "qc" and w.prof != "electrician":
			ops += 1
	return float(ops)


func on_quit(w: Worker) -> void:
	if not w.is_itr():
		vacancies.append(w.prof)


func _auto_hire() -> void:
	var prof := str(vacancies.pop_front())
	var cost := sim.ad_price(prof)
	if not sim.can_afford(cost + 50000.0):
		vacancies.push_front(prof)
		return
	sim.spend(cost, "Объявление о вакансии (кадровик): " + str(Worker.PROF_NAMES.get(prof, prof)))
	sim.refresh_candidates(prof)
	var best := -1
	var bs := -1
	for i in sim.candidates.size():
		var c: Dictionary = sim.candidates[i]
		if str(c.get("prof", "")) != prof:
			continue
		var sk := int((c.get("skills", {}) as Dictionary).get(str(Worker.PROF_SKILL.get(prof, "haul")), 0))
		if sk > bs:
			bs = sk
			best = i
	if best >= 0:
		var nm := "%s %s" % [str(sim.candidates[best].get("first", "")), str(sim.candidates[best].get("last", ""))]
		sim.hire(best)
		sim.notify(L.t("Кадровик нашёл замену: %s, %s.") % [nm, Worker.lc(L.t(str(Worker.PROF_NAMES.get(prof, prof))))], Sim.LVL_GOOD)


# ---------------------------------------------------------------- сохранение

func to_dict() -> Dictionary:
	return {"policies": policies, "supplier": supplier, "done": research_done, "cur": research_cur,
		"pts": research_pts, "weeks": weeks, "loans": loans, "vac": vacancies}


func from_dict(d: Dictionary) -> void:
	var p: Dictionary = d.get("policies", {})
	for k in p.keys():
		policies[k] = bool(p[k])
	supplier = str(d.get("supplier", "base"))
	research_done = d.get("done", [])
	research_cur = str(d.get("cur", ""))
	research_pts = d.get("pts", {})
	weeks = d.get("weeks", [])
	loans = d.get("loans", [])
	vacancies = d.get("vac", [])
