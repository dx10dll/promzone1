class_name Market
extends RefCounted
## Рынок (1.8): заводы-конкуренты и доля рынка, ценовая политика, индекс цены металла,
## дневная статистика для графиков, сертификат ISO 9001, лизинг станков, страхование
## и советы главного инженера. Все заводы и компании вымышленные.

const POLICIES := {
	"dump": {"name": "Демпинг", "price": 0.9, "pull": 1.3,
		"desc": "Цены на 10% ниже рынка: заявок на треть больше, но маржа тоньше. Конкуренты в долгу не останутся."},
	"market": {"name": "По рынку", "price": 1.0, "pull": 1.0, "desc": "Обычные цены."},
	"premium": {"name": "Премиум", "price": 1.12, "pull": 0.72,
		"desc": "Цены на 12% выше: заявок меньше. С сертификатом ISO 9001 заказчики почти не уходят."},
}
## Заводы региона (вымышленные). Первые четыре работают с начала игры, остальные появляются на месте обанкротившихся.
const POOL := [
	{"id": "tehmash", "name": "ООО «Техмаш-Регион»", "size": 3.0, "price": 1.0, "quality": 0.72, "spec": ["turning", "milling"]},
	{"id": "zarechny", "name": "АО «Заречный машзавод»", "size": 6.0, "price": 1.06, "quality": 0.82, "spec": ["welding", "assembly", "paint"]},
	{"id": "promdetal", "name": "ООО «ПромДеталь-Сервис»", "size": 2.0, "price": 0.93, "quality": 0.62, "spec": ["turning", "drilling"]},
	{"id": "stankoagr", "name": "ЗАО «Станкоагрегат»", "size": 4.5, "price": 1.1, "quality": 0.9, "spec": ["milling", "heat", "assembly"]},
	{"id": "kovalchuk", "name": "Мастерская «Ковальчук и сыновья»", "size": 1.5, "price": 0.9, "quality": 0.7, "spec": ["turning"]},
	{"id": "metallist", "name": "ООО «Металлист-Плюс»", "size": 3.5, "price": 0.98, "quality": 0.75, "spec": ["welding", "turning"]},
	{"id": "vektor", "name": "АО «Вектор-Деталь»", "size": 5.0, "price": 1.04, "quality": 0.85, "spec": ["milling", "drilling", "heat"]},
]
const COMP_COLORS := ["#d8644e", "#7fb6d8", "#a58ad8", "#8fcf78", "#e0aa48", "#c98bb9", "#6fc2b0"]

const ISO_COST := 120000.0
const ISO_RENEW := 45000.0
const ISO_DAYS := 84          ## сертификат действует полгода (84 игровых дня), потом надзорный аудит
const LEASE_ADV := 0.2        ## аванс лизинга
const LEASE_UP := 0.18        ## удорожание
const LEASE_WEEKS := 12
const LEASE_MIN := 40000.0    ## в лизинг — только дорогое оборудование
const INSURANCE := {
	"property": {"name": "Имущество и оборудование", "icon": "wrench",
		"desc": "Возмещает 80% стоимости ремонта станков и ущерб от пожара."},
	"liability": {"name": "Ответственность перед заказчиками", "icon": "handshake",
		"desc": "Возмещает половину неустоек за опоздание, компенсаций по рекламациям и штрафов по контрактам."},
	"accident": {"name": "Несчастный случай", "icon": "injury",
		"desc": "Полностью выплачивает компенсацию пострадавшему по акту Н-1."},
}

var sim: Sim
var comps: Array = []         ## [{id, name, size, price, quality, spec, alive, war_until, weak_weeks, share}]
var policy := "market"
var share := 0.0              ## наша доля рынка (0..1), пересчёт каждое утро
var share_hist: Array = []    ## по неделям: {week, ours, comps: {id: доля}}
var metal := 1.0              ## индекс цены металла
var metal_week := 1.0         ## индекс неделю назад
var hist: Array = []          ## по дням: {d, money, rev, exp, share, metal, mood, rep, staff, done}
var outcomes: Array = []      ## последние 20 отгрузок: true — вовремя
var last_reclam := -100       ## день последней рекламации
var iso: Dictionary = {"status": "none"}   ## none | audit | ok | remarks | suspended; since, until, audit_at, reclam
var insurance: Dictionary = {}             ## вид -> {since: день}
var paid_claims: Dictionary = {}           ## вид -> сумма выплат за всё время
var leases: Array = []        ## [{id, thing, title, payment, left, total}]
var leasing_on := false       ## покупать станки в лизинг
var memo_on := true           ## записка главного инженера по понедельникам
var _hd := -1


func _init(s: Sim) -> void:
	sim = s
	for i in 4:
		comps.append(_new_comp(POOL[i]))


func _new_comp(p: Dictionary) -> Dictionary:
	var c := p.duplicate(true)
	c["alive"] = true
	c["war_until"] = -1
	c["weak_weeks"] = 0
	c["share"] = 0.0
	c["base_price"] = float(p["price"])
	return c


func alive_comps() -> Array:
	return comps.filter(func(c: Dictionary) -> bool: return bool(c["alive"]))


func comp(id: String) -> Dictionary:
	for c: Dictionary in comps:
		if str(c["id"]) == id:
			return c
	return {}


func comp_color(id: String) -> Color:
	for i in POOL.size():
		if str(POOL[i]["id"]) == id:
			return Color(COMP_COLORS[i % COMP_COLORS.size()])
	return Color("#999999")


# ================================================================ конкурентоспособность и доля

func pol() -> Dictionary:
	if not sim.office.active("sales"):
		return POLICIES["market"]   # без отдела сбыта цены «по рынку»
	return POLICIES.get(policy, POLICIES["market"])


## Множитель цены заказов от политики.
func price_k() -> float:
	return float(pol()["price"])


## Доля заказов, выполненных вовремя (по последним 20 отгрузкам).
func ontime() -> float:
	# 1.20: просроченные заказы в работе — тоже «не вовремя», а не только отгруженные
	var overdue := 0
	for od: Dictionary in sim.orders.by_status(["active", "ready", "shipping"]):
		if sim.orders.is_overdue(od):
			overdue += 1
	if outcomes.is_empty() and overdue == 0:
		return 0.8
	var n := 0
	for o in outcomes:
		if bool(o):
			n += 1
	return float(n) / float(outcomes.size() + overdue)


func iso_ok() -> bool:
	return str(iso.get("status", "none")) == "ok"


## Сколько заказчик готов к нам прийти, если сравнить с рынком: качество, сроки, цены, сертификат.
func competitiveness() -> float:
	var q := float(sim.progress.rating.get("quality", 0.5))
	var k := (0.7 + q * 0.6) * (0.7 + ontime() * 0.4)
	var pull := float(pol()["pull"])
	if policy == "premium" and iso_ok():
		pull = 0.92
	k *= pull
	if iso_ok():
		k *= 1.12
	return k


func war_active() -> bool:
	for c: Dictionary in alive_comps():
		if int(c["war_until"]) >= sim.day():
			return true
	return false


## Множитель числа заявок в день (используется в Orders.morning).
func inquiry_k() -> float:
	var k := competitiveness() * (1.1 if sim.office.active("sales") else 1.0)
	if war_active() and policy != "dump":
		k *= 0.85
	return clampf(k, 0.55, 1.6)


## Наша «сила» на рынке: мощность (станочники) × конкурентоспособность × репутация.
func our_power() -> float:
	var ops := sim.office.load_ops() if sim.office else 1.0
	return maxf(0.3, ops) * competitiveness() * (0.6 + sim.reputation / 125.0)


func comp_power(c: Dictionary) -> float:
	if not bool(c["alive"]):
		return 0.0
	var pr := float(c["price"])
	return float(c["size"]) * (0.7 + float(c["quality"]) * 0.6) / (pr * pr) * (1.25 if int(c["war_until"]) >= sim.day() else 1.0)


func _update_share() -> void:
	var ours := our_power()
	var total := ours
	for c: Dictionary in comps:
		total += comp_power(c)
	share = ours / maxf(0.01, total)
	sim.stats["share_max"] = maxi(int(sim.stats.get("share_max", 0)), int(share * 100.0))
	for c2: Dictionary in comps:
		c2["share"] = comp_power(c2) / maxf(0.01, total)


# ================================================================ металл

## Индекс цены металла: каждый день понемногу гуляет, иногда — скачок.
func _tick_metal() -> void:
	var m := metal * (1.0 + sim.rng.randf_range(-0.012, 0.012)) + (1.0 - metal) * 0.03
	metal = clampf(m, 0.75, 1.4)


func metal_trend() -> float:
	return metal / maxf(0.01, metal_week) - 1.0


# ================================================================ утро

func morning() -> void:
	_tick_metal()
	_expire_wars()
	_update_share()
	_record_day()
	if sim.weekday() == 0:
		_on_monday()
	_tick_iso()


func _expire_wars() -> void:
	for c: Dictionary in comps:
		if int(c["war_until"]) >= 0 and int(c["war_until"]) < sim.day():
			c["war_until"] = -1
			c["price"] = float(c["base_price"])


func _on_monday() -> void:
	var wk := int((sim.day() - 1) / 7) + 1
	var cs := {}
	for c: Dictionary in comps:
		if bool(c["alive"]):
			cs[str(c["id"])] = float(c["share"])
	share_hist.append({"week": wk, "ours": share, "comps": cs})
	if share_hist.size() > 52:
		share_hist.pop_front()
	_metal_shock()
	metal_week = metal
	_pay_leases()
	_pay_insurance()
	if sim.day() >= 8 and sim.story.enabled:
		_comp_events()
	if memo_on and sim.day() >= 7 and sim.office.active("engineer"):
		var adv := advice()
		if not adv.is_empty():
			sim.notify(L.t("Главный инженер: «%s» — и ещё %d %s в «Управление → Главный инженер».") % [str(adv[0]["title"]), adv.size() - 1, Defs.plural(adv.size() - 1, "совет", "совета", "советов")], Sim.LVL_INFO)


func _metal_shock() -> void:
	if sim.rng.randf() >= 0.1:
		return
	var up := sim.rng.randf() < 0.6
	var k := sim.rng.randf_range(0.08, 0.15)
	metal = clampf(metal * (1.0 + k if up else 1.0 - k), 0.75, 1.4)
	var why: String = [L.t("подорожал прокат на комбинатах"), L.t("выросли тарифы на перевозку"), L.t("новые пошлины на сталь")][sim.rng.randi_range(0, 2)] if up else [L.t("комбинаты распродают запасы"), L.t("упал спрос у строителей"), L.t("открылся новый склад проката")][sim.rng.randi_range(0, 2)]
	sim.story.info(L.t("Металл %s на %d%%") % [L.t("подорожал") if up else L.t("подешевел"), int(roundf(k * 100.0))],
		L.t("Новость с металлобазы: %s. %s") % [why, L.t("Держите запас «Только под заказы», пока цены не вернутся.") if up else L.t("Самое время закупить металл впрок — поставьте запас «Большой».")],
		"supply", Sim.LVL_WARN if up else Sim.LVL_GOOD)


## Записать день для графиков.
func _record_day() -> void:
	var d := sim.day()
	if d == _hd:
		return
	_hd = d
	var rev := 0.0
	var exp := 0.0
	for e: Dictionary in sim.ledger:
		var ed := int(e["day"])
		if ed < d - 1:
			break
		if ed != d - 1:
			continue
		var v := float(e["v"])
		if str(e.get("base", e["text"])).begins_with("Кредит получен"):
			continue
		if v > 0.0:
			rev += v
		else:
			exp -= v
	var mood := 0.0
	for w in sim.workers:
		mood += w.mood
	mood = mood / maxf(1.0, float(sim.workers.size())) if not sim.workers.is_empty() else 50.0
	var cs := {}
	for c: Dictionary in comps:
		if bool(c["alive"]):
			cs[str(c["id"])] = float(c["share"])
	hist.append({"d": d, "money": sim.money, "rev": rev, "exp": exp, "share": share, "cs": cs, "metal": metal, "mood": mood,
		"rep": sim.reputation, "staff": sim.workers.size(), "done": int(sim.stats.get("orders_done", 0))})
	if hist.size() > 168:
		hist.pop_front()


# ================================================================ события конкурентов

func _comp_events() -> void:
	var rng := sim.rng
	var al := alive_comps()
	# банкротство слабого (долго с маленькой долей)
	for c: Dictionary in al:
		if float(c["share"]) < 0.06:
			c["weak_weeks"] = int(c["weak_weeks"]) + 1
		else:
			c["weak_weeks"] = 0
		if int(c["weak_weeks"]) >= 4 and rng.randf() < 0.35 and al.size() > 2:
			_bankrupt(c)
			return
	# новый завод на месте ушедшего
	if al.size() < 4 and rng.randf() < 0.3:
		for p: Dictionary in POOL:
			if comp(str(p["id"])).is_empty():
				var nc := _new_comp(p)
				comps.append(nc)
				sim.story.info(L.t("Новый конкурент: %s") % Company.firm(str(nc["name"])), L.t("В районе открылся %s. Специализация: %s.") % [Company.firm(str(nc["name"])), _spec_text(nc)], "chart_down", Sim.LVL_WARN)
				return
	var r := rng.randf()
	if r < 0.16 and not war_active():
		_start_war(al[rng.randi_range(0, al.size() - 1)])
	elif r < 0.28:
		_poach()
	elif r < 0.36:
		var c2: Dictionary = al[rng.randi_range(0, al.size() - 1)]
		c2["size"] = float(c2["size"]) + 0.8
		sim.story.info(L.t("%s расширяется") % Company.firm(str(c2["name"])), L.t("%s поставил новые станки — будет брать больше заказов. Держите сроки и качество, чтобы заказчики оставались с нами.") % Company.firm(str(c2["name"])), "chart_down", Sim.LVL_INFO)
	elif r < 0.42 and policy == "dump":
		# демпинг злит соседей
		_start_war(al[rng.randi_range(0, al.size() - 1)], true)


func _spec_text(c: Dictionary) -> String:
	var n: Array[String] = []
	for pr in c["spec"]:
		n.append(Defs.process_name(str(pr)).to_lower())
	return ", ".join(n)


func _start_war(c: Dictionary, answer: bool = false) -> void:
	c["war_until"] = sim.day() + 14
	c["price"] = float(c["base_price"]) * 0.88
	var t := L.t("%s снизил цены на 12%%%s — заказчики считают деньги, заявок к нам станет меньше на две недели.") % [Company.firm(str(c["name"])), L.t(" в ответ на наш демпинг") if answer else ""]
	sim.story.letter("price_war", L.t("Война цен"), t, "chart_down", Sim.LVL_WARN,
		[{"text": L.t("Ответить демпингом"), "hint": L.t("Цены −10%, заявок больше, маржа меньше")},
		{"text": L.t("Держать цены"), "hint": L.t("Заявок −15% две недели")},
		{"text": L.t("Сделать упор на качество (60 000 ₽)"), "hint": L.t("Реклама в отраслевом журнале: репутация +4, война цен кончится раньше")}],
		1, {"comp": str(c["id"])})


func _bankrupt(c: Dictionary) -> void:
	c["alive"] = false
	sim.stats["comp_bankrupt"] = int(sim.stats.get("comp_bankrupt", 0)) + 1
	var mach: Array = ["lathe", "mill", "drill", "weld_post", "furnace"]
	var pick := ""
	for m in mach:
		if Defs.objects.has(m) and sim.progress.locked_reason(m) == "":
			pick = m
			if sim.rng.randf() < 0.5:
				break
	var t := L.t("%s обанкротился: его заказчики ищут новых подрядчиков — наша доля рынка вырастет.") % Company.firm(str(c["name"]))
	if pick != "":
		t += L.t(" Конкурсный управляющий распродаёт оборудование: «%s» с торгов — за 40%% цены.") % Defs.obj_name(pick)
		sim.story.letter("auction", L.t("Банкротство конкурента"), t, "court", Sim.LVL_GOOD,
			[{"text": L.t("Купить с торгов"), "hint": L.t("Следующий такой станок обойдётся в 40% цены (две недели)")}, {"text": L.t("Не нужно"), "hint": ""}],
			1, {"def": pick})
	else:
		sim.story.info(L.t("Банкротство конкурента"), t, "court", Sim.LVL_GOOD)


func _poach() -> void:
	if sim.workers.size() < 5:
		return   # гараж на троих конкурентам неинтересен
	var best: Worker = null
	for w in sim.workers:
		if not w.has_grade() or w.grade() < 4 or w.practice_until >= 0:
			continue
		if best == null or w.grade() > best.grade() or (w.grade() == best.grade() and w.mood < best.mood):
			best = w
	if best == null:
		return
	var al := alive_comps()
	if al.is_empty():
		return
	var c: Dictionary = al[sim.rng.randi_range(0, al.size() - 1)]
	var raise := int(roundf(best.wage * 0.15 / 50.0) * 50)
	sim.story.letter("poach", L.t("Переманивают %s") % best.full_name(),
		L.t("%s зовёт к себе %s (%s): обещают на 20%% больше. Человек думает.") % [Company.firm(str(c["name"])), best.full_name(), best.title_lc()],
		"thief", Sim.LVL_WARN,
		[{"text": L.t("Поднять ставку на %s") % Defs.money_str(raise), "hint": L.t("Останется и будет доволен")},
		{"text": L.t("Поговорить по душам"), "hint": L.t("Останется, если %s у нас хорошо (настроение %d)") % [L.t("ей") if best.female else L.t("ему"), int(best.mood)]},
		{"text": L.t("Отпустить"), "hint": L.t("Уйдёт к конкуренту")}],
		1, {"w": best.id, "raise": raise, "comp": str(c["id"])})


## Решение по письму (вызывается из Story.resolve).
func on_letter(ev: String, d: Dictionary, choice: int) -> void:
	match ev:
		"price_war":
			var c := comp(str(d.get("comp", "")))
			if choice == 0:
				policy = "dump"
				sim.notify(L.t("Перешли на демпинг: цены −10%. Вернуть цены можно в «Заказы → Конкуренты»."), Sim.LVL_INFO)
			elif choice == 2:
				if sim.money < 60000.0:
					sim.notify(L.t("Денег на рекламу нет — держим цены."), Sim.LVL_WARN)
					return
				sim.spend(60000.0, "Реклама в отраслевом журнале")
				sim.reputation = minf(100.0, sim.reputation + 4.0)
				if not c.is_empty():
					c["war_until"] = mini(int(c["war_until"]), sim.day() + 5)
				sim.notify(L.t("Статья о заводе вышла: заказчики помнят о качестве. Война цен скоро выдохнется."), Sim.LVL_GOOD)
		"auction":
			if choice == 0:
				var def := str(d.get("def", ""))
				sim.story.add_mod("voucher:" + def, 0.4, 14.0 * 1440.0, L.t("Станок с торгов"))
				sim.notify(L.t("Выкупили с торгов «%s»: ставьте его в течение двух недель — заплатите 40%% цены.") % Defs.obj_name(def), Sim.LVL_GOOD)
		"poach":
			var w := sim.get_worker(int(d.get("w", -1)))
			if w == null:
				return
			var c2 := comp(str(d.get("comp", "")))
			var cn := Company.firm(str(c2.get("name", L.t("конкурент"))))
			if choice == 0:
				w.wage += int(d.get("raise", 300))
				Mood.add(sim, w, "raise")
				w.add_history(sim.day(), L.t("Звали к конкуренту — остался за прибавку"))
				sim.notify(L.t("%s остаётся: ставку подняли.") % w.full_name(), Sim.LVL_GOOD)
			elif choice == 1 and w.mood >= 50.0:
				w.add_history(sim.day(), L.t("Звали к конкуренту — остался: «Здесь свои»"))
				sim.notify(L.t("%s подумал и остался: «Здесь свои люди, куда я пойду».") % w.full_name(), Sim.LVL_GOOD)
			else:
				w.add_history(sim.day(), L.t("Ушёл в %s") % cn)
				sim.notify(L.t("%s ушёл в %s.") % [w.full_name(), cn], Sim.LVL_BAD)
				sim.fire(w, true)
				if not c2.is_empty():
					c2["quality"] = minf(0.95, float(c2["quality"]) + 0.02)
		"iso_audit":
			pass


# ================================================================ отгрузки и рекламации

func on_shipped(late_days: int) -> void:
	outcomes.append(late_days == 0)
	if outcomes.size() > 20:
		outcomes.pop_front()


func on_reclamation() -> void:
	last_reclam = sim.day()
	if iso_ok():
		iso["reclam"] = int(iso.get("reclam", 0)) + 1
		if int(iso["reclam"]) >= 2:
			iso["status"] = "suspended"
			iso["until"] = sim.day()
			sim.story.info(L.t("Сертификат ISO 9001 приостановлен"), L.t("Две рекламации за срок действия — орган по сертификации приостановил сертификат. Наведите порядок с качеством и закажите аудит заново."), "inspect", Sim.LVL_BAD)
		else:
			sim.notify(L.t("Рекламация при сертификате ISO 9001: ещё одна — и сертификат приостановят."), Sim.LVL_WARN)


# ================================================================ ISO 9001

## Требования стандарта: [текст, выполнено].
func iso_reqs() -> Array:
	var qc_staff := false
	for w in sim.workers:
		if w.prof == "qc":
			qc_staff = true
			break
	var places := sim.eng.workplaces()
	return [
		[L.t("Контролёр ОТК и стол ОТК"), qc_staff and not sim.things_of("qc").is_empty()],
		[L.t("Качество в рейтинге от 65%"), float(sim.progress.rating.get("quality", 0.5)) >= 0.65],
		[L.t("Техотдел с технологом"), sim.office.active("tech")],
		[L.t("СОУТ проведена на всех местах"), not places.is_empty() and sim.eng.unassessed() == 0],
		[L.t("Инструктаж по охране труда действует"), sim.training.tb_valid()],
		[L.t("Без рекламаций последние 14 дней"), sim.day() - last_reclam >= 14],
	]


func iso_ready() -> int:
	var n := 0
	for r: Array in iso_reqs():
		if bool(r[1]):
			n += 1
	return n


## Заказать сертификационный аудит. Аудитор приедет через три дня и проверит требования.
func iso_apply() -> String:
	var st := str(iso.get("status", "none"))
	if st == "audit":
		return L.t("Аудит уже назначен")
	if st == "ok" and int(iso.get("until", 0)) - sim.day() > 14:
		return L.t("Сертификат действует до дня %d") % int(iso["until"])
	if not sim.dev.on("tech3"):
		return L.t("Сертификацию открывает ступень «ISO 9001» (Управление → Развитие)")
	var cost := ISO_RENEW if st == "ok" else ISO_COST
	if sim.money < cost:
		return L.t("Не хватает денег: аудит стоит %s") % Defs.money_str(cost)
	sim.spend(cost, "Сертификация ISO 9001: аудит")
	iso["prev"] = st
	iso["status"] = "audit"
	iso["audit_at"] = sim.day() + 3
	sim.notify(L.t("Орган по сертификации приедет с аудитом в день %d. Проверят: ОТК, качество, техотдел, СОУТ, инструктаж, рекламации.") % int(iso["audit_at"]), Sim.LVL_INFO)
	return ""


func _tick_iso() -> void:
	var st := str(iso.get("status", "none"))
	if st == "audit" and sim.day() >= int(iso.get("audit_at", 0)):
		_audit()
	elif st == "ok" and sim.day() >= int(iso.get("until", 0)):
		iso["status"] = "expired"
		sim.story.info(L.t("Сертификат ISO 9001 истёк"), L.t("Полгода прошло — нужен надзорный аудит (%s). Без сертификата премиальные заказчики уходят.") % Defs.money_str(ISO_RENEW), "inspect", Sim.LVL_WARN)
	elif st == "ok" and int(iso.get("until", 0)) - sim.day() == 10:
		sim.notify(L.t("Сертификат ISO 9001 истекает через 10 дней — закажите надзорный аудит («Управление → ISO 9001»)."), Sim.LVL_WARN)


func _audit() -> void:
	var miss: Array[String] = []
	for r: Array in iso_reqs():
		if not bool(r[1]):
			miss.append(str(r[0]).to_lower())
	if miss.size() == 0 or (miss.size() == 1 and str(iso.get("prev", "")) == "ok"):
		var was := str(iso.get("prev", "none")) == "ok"
		iso = {"status": "ok", "since": sim.day(), "until": sim.day() + ISO_DAYS, "reclam": 0}
		if not was:
			sim.reputation = minf(100.0, sim.reputation + 5.0)
		sim.stats["iso"] = 1
		sim.story.info(L.t("Сертификат ISO 9001 получен") if not was else L.t("Сертификат ISO 9001 продлён"),
			L.t("Аудитор доволен: система менеджмента качества работает. Сертификат действует до дня %d. Премиальные заказчики и экспорт — охотнее, заявок больше.%s") % [int(iso["until"]), "" if miss.is_empty() else L.t(" Замечание: ") + miss[0] + "."],
			"medal", Sim.LVL_GOOD, Vector2i(-1, -1), true)
	else:
		iso = {"status": "remarks", "since": sim.day(), "fix_until": sim.day() + 14}
		sim.story.info(L.t("Аудит ISO 9001: есть несоответствия"),
			L.t("Аудитор нашёл несоответствия: %s. Сертификат не выдан. Исправьте за две недели и закажите аудит снова — повторный обойдётся дешевле.") % ", ".join(miss),
			"inspect", Sim.LVL_BAD, Vector2i(-1, -1), true)


func iso_text() -> String:
	match str(iso.get("status", "none")):
		"ok":
			return L.t("действует до дня %d") % int(iso.get("until", 0))
		"audit":
			return L.t("аудит в день %d") % int(iso.get("audit_at", 0))
		"remarks":
			return L.t("несоответствия — исправить и повторить аудит")
		"suspended":
			return L.t("приостановлен из-за рекламаций")
		"expired":
			return L.t("истёк — нужен надзорный аудит")
	return L.t("нет сертификата")


# ================================================================ лизинг

## Покупка в лизинг: вызывается из Sim.place_thing. Возвращает сумму, которую платим сразу.
func lease_buy(t: Thing, cost: float) -> float:
	var adv := roundf(cost * LEASE_ADV)
	var total := cost * (1.0 - LEASE_ADV) * (1.0 + LEASE_UP)
	leases.append({"id": sim.new_id(), "thing": t.id, "title": t.title_ru(), "payment": roundf(total / LEASE_WEEKS), "left": LEASE_WEEKS, "total": roundf(total)})
	return adv


func can_lease(def_id: String, cost: float) -> bool:
	return leasing_on and sim.dev.on("fin3") and str(Defs.objects.get(def_id, {}).get("kind", "")) == "machine" and cost >= LEASE_MIN


func cancel_lease(thing_id: int) -> void:
	leases = leases.filter(func(l: Dictionary) -> bool: return int(l["thing"]) != thing_id)


func lease_debt() -> float:
	var t := 0.0
	for l: Dictionary in leases:
		t += float(l["payment"]) * int(l["left"])
	return t


func lease_week() -> float:
	var t := 0.0
	for l: Dictionary in leases:
		t += float(l["payment"])
	return t


func _pay_leases() -> void:
	for l: Dictionary in leases:
		sim.spend(float(l["payment"]), "Лизинг: платёж за %s" % str(l["title"]))
		l["left"] = int(l["left"]) - 1
		if int(l["left"]) <= 0:
			sim.stats["leases_done"] = int(sim.stats.get("leases_done", 0)) + 1
			sim.notify(L.t("Лизинг за «%s» выплачен — станок полностью наш.") % L.tx(str(l["title"])), Sim.LVL_GOOD)
	leases = leases.filter(func(l2: Dictionary) -> bool: return int(l2["left"]) > 0)


# ================================================================ страхование

func insured(kind: String) -> bool:
	return insurance.has(kind) and sim.day() >= int((insurance[kind] as Dictionary).get("since", 0)) + 1


## Взнос за неделю по виду страховки.
func premium(kind: String) -> float:
	match kind:
		"property":
			var v := 0.0
			for t in sim.things_of("machine"):
				v += float(Defs.objects.get(t.def_id, {}).get("cost", 0))
			return maxf(1500.0, roundf(v * 0.0025 / 10.0) * 10.0)
		"liability":
			var s := 0.0
			for e: Dictionary in hist.slice(maxi(0, hist.size() - 7)):
				s += float(e["rev"])
			return maxf(2000.0, roundf(s * 0.012 / 10.0) * 10.0)
		"accident":
			return maxf(1000.0, 250.0 * sim.workers.size())
	return 0.0


func toggle_insurance(kind: String, on: bool) -> void:
	if on and not insurance.has(kind) and not sim.dev.on("fin3"):
		sim.notify(L.t("Страховку оформляет бухгалтерия после ступени «Банк и лизинг» (Управление → Развитие)."), Sim.LVL_WARN)
		return
	if on and not insurance.has(kind):
		insurance[kind] = {"since": sim.day()}
		var p := premium(kind)
		sim.spend(p, "Страховка: %s, первый взнос" % str(INSURANCE[kind]["name"]).to_lower())
		sim.notify(L.t("Полис «%s» оформлен: %s в неделю, действует со следующего дня.") % [L.t(str(INSURANCE[kind]["name"])), Defs.money_str(p)], Sim.LVL_INFO)
	elif not on and insurance.has(kind):
		insurance.erase(kind)


func _pay_insurance() -> void:
	for k in insurance.keys():
		if int((insurance[k] as Dictionary).get("since", 0)) == sim.day():
			continue
		sim.spend(premium(str(k)), "Страховка: %s" % str(INSURANCE[k]["name"]).to_lower())


## Страховой случай: возмещение части расходов. Возвращает выплату.
func claim(kind: String, loss: float, what: String) -> float:
	if not insured(kind) or loss <= 0.0:
		return 0.0
	var k := 0.8 if kind == "property" else (0.5 if kind == "liability" else 1.0)
	var pay := roundf(loss * k)
	if pay <= 0.0:
		return 0.0
	sim.earn(pay, "Страховое возмещение: " + what)
	paid_claims[kind] = float(paid_claims.get(kind, 0.0)) + pay
	return pay


# ================================================================ главный инженер

## Советы главного инженера: [{prio, title, text, open, sec}], самые важные — первыми.
func advice(limit: int = 6) -> Array:
	var out: Array = []
	# станочники без работы: их передела нет ни в одном заказе
	var used := {}
	for o: Dictionary in sim.orders.by_status(["active"]):
		for pr0 in sim.sales.procs_of(str(o["product"])):
			used[pr0] = true
	var idle: Array[String] = []
	for w in sim.workers:
		if w.is_itr():
			continue
		for pr1 in Defs.processes.keys():
			if str(Defs.processes[pr1].get("prof", "")) == w.prof and not used.has(pr1) and not idle.has(w.prof_lc()):
				var has_m := sim.things_of("machine").any(func(t: Thing) -> bool: return t.process() == str(pr1))
				if has_m and not sim.orders.by_status(["active"]).is_empty():
					idle.append(w.prof_lc())
	if not idle.is_empty():
		out.append({"prio": 72 if sim.office.payroll_share(4) > 0.6 else 45, "title": L.t("Без работы: ") + ", ".join(idle),
			"text": L.t("Их передела нет ни в одном заказе в работе. Возьмите заказы на эти изделия, переобучите людей (Люди → Обучение) или не нанимайте новых, пока работы нет."),
			"open": "orders", "sec": "market"})
	var s := sim.sales.summary(7)
	if float(s["lost_sum"]) >= 30000.0 and str(s["top"]) != "":
		var pr := str(s["top"])
		out.append({"prio": 90, "title": L.t("Проблемное место — %s") % Defs.process_name(pr).to_lower(),
			"text": L.t("За неделю отказали заказчикам на %s, больше всего — из-за этого передела (%s). %s") % [Defs.money_str(float(s["lost_sum"])), Defs.money_str(float(s["top_sum"])), sim.sales.advice(pr)],
			"open": "orders", "sec": "market"})
	var broken := 0
	var worn := 0
	for t in sim.things_of("machine"):
		if t.built and t.broken:
			broken += 1
		elif t.built and t.condition < 35.0:
			worn += 1
	if broken > 0:
		out.append({"prio": 95, "title": L.t("Станков сломано: %d") % broken, "text": L.t("Сломанный станок стоит, а заказы горят. Ремонт делает токарь или рукастый рабочий — проверьте, что у них есть время."), "open": "prod", "sec": "machines"})
	if worn >= 2 and not sim.ppr:
		out.append({"prio": 70, "title": L.t("Включите ППР"), "text": L.t("%d станка сильно изношены. Планово-предупредительный ремонт обслуживает их раньше — поломки реже.") % worn, "open": "prod", "sec": "machines"})
	var late := 0
	for o: Dictionary in sim.orders.by_status(["active"]):
		if sim.minute > float(o["deadline"]) - 1440.0:
			late += 1
	if late > 0:
		out.append({"prio": 85, "title": L.t("Горят сроки: %d %s") % [late, Defs.plural(late, "заказ", "заказа", "заказов")], "text": L.t("Поставьте им приоритет «срочно» — станки возьмут их первыми. Опоздание — неустойка 5% в день и минус репутация."), "open": "orders", "sec": "active"})
	if not sim.workers.is_empty():
		var avg := 0.0
		var bad: Dictionary = {}
		for w in sim.workers:
			avg += w.mood
			for p: Array in Mood.breakdown(sim, w):
				if float(p[1]) < -1.5:
					bad[str(p[0])] = float(bad.get(str(p[0]), 0.0)) + float(p[1])
		avg /= float(sim.workers.size())
		if avg < 45.0 and not bad.is_empty():
			var keys := bad.keys()
			keys.sort_custom(func(a: Variant, b: Variant) -> bool: return float(bad[a]) < float(bad[b]))
			var top: Array[String] = []
			for k in keys.slice(0, 3):
				top.append("«%s»" % str(k))
			out.append({"prio": 80 if avg < 35.0 else 60, "title": L.t("Люди недовольны (%d)") % int(avg), "text": L.t("Больше всего злит: %s. Плохое настроение — медленная работа, прогулы и увольнения.") % ", ".join(top), "open": "people", "sec": "staff"})
	if sim.money < 0.0 or (not sim.workers.is_empty() and sim.money < _weekly_wages()):
		out.append({"prio": 88, "title": L.t("Денег меньше недельной зарплаты"), "text": L.t("Ускорьте отгрузки готовых заказов, возьмите кредит или отложите покупки. Станки можно брать в лизинг — 20% сразу."), "open": "finance", "sec": "loans"})
	if metal < 0.9:
		out.append({"prio": 45, "title": L.t("Металл подешевел (%d%%)") % int(roundf((metal - 1.0) * 100.0)), "text": L.t("Закупите впрок: запас «Большой» в «Производство → Металл и расходники»."), "open": "prod", "sec": "supply"})
	elif metal > 1.15 and sim.supply_reserve > 0:
		out.append({"prio": 45, "title": L.t("Металл дорогой (+%d%%)") % int(roundf((metal - 1.0) * 100.0)), "text": L.t("Держите запас «Только под заказы», пока цены не вернутся."), "open": "prod", "sec": "supply"})
	if war_active() and policy != "dump":
		out.append({"prio": 55, "title": L.t("Война цен у конкурентов"), "text": L.t("Заявок меньше на 15%. Можно ответить демпингом или переждать, держа качество."), "open": "orders", "sec": "compet"})
	if sim.workers.size() >= 4 and sim.eng.unassessed() > 0 and not sim.eng.sout_busy():
		out.append({"prio": 50, "title": L.t("Не проведена СОУТ"), "text": L.t("Без спецоценки трудовая инспекция штрафует, а для ISO 9001 она обязательна."), "open": "people", "sec": "safety"})
	if sim.workers.size() >= 6 and not sim.training.tb_valid() and not sim.training.tb_active():
		out.append({"prio": 50, "title": L.t("Пора провести инструктаж"), "text": L.t("Инструктаж по охране труда — минус 30% травм. Без него штрафуют."), "open": "people", "sec": "train"})
	if sim.workers.size() >= 8 and sim.crew.brigades.is_empty():
		out.append({"prio": 40, "title": L.t("Разбейте людей на бригады"), "text": L.t("Бригадир ускоряет бригаду, люди меньше бегают по заводу."), "open": "people", "sec": "brig"})
	if sim.dev.on("tech3") and not iso_ok() and str(iso.get("status", "none")) != "audit":
		var rd := iso_ready()
		if rd >= 4:
			var miss: Array[String] = []
			for r: Array in iso_reqs():
				if not bool(r[1]):
					miss.append(str(r[0]).to_lower())
			out.append({"prio": 35 + rd * 3, "title": L.t("До ISO 9001 рукой подать (%d из 6)") % rd, "text": (L.t("Осталось: %s. ") % ", ".join(miss) if not miss.is_empty() else L.t("Всё готово — заказывайте аудит. ")) + L.t("Сертификат даёт больше заявок и премиальные цены."), "open": "office", "sec": "iso"})
	var mval := 0.0
	for t2 in sim.things_of("machine"):
		mval += float(Defs.objects.get(t2.def_id, {}).get("cost", 0))
	if mval >= 900000.0 and not insurance.has("property"):
		out.append({"prio": 30, "title": L.t("Застрахуйте оборудование"), "text": L.t("Станков на %s. Полис — %s в неделю, возмещает 80%% ремонта и ущерб от пожара.") % [Defs.money_str(mval), Defs.money_str(premium("property"))], "open": "finance", "sec": "insurance"})
	var unassigned := 0
	for r2 in sim.rooms.list:
		if r2.type == "" and r2.area() >= 6:
			unassigned += 1
	if unassigned > 0:
		out.append({"prio": 25, "title": L.t("Помещений без назначения: %d") % unassigned, "text": L.t("Назначьте их (кнопка «Помещения»): оборудованные цеха, бытовка и столовая поднимают настроение."), "open": "", "sec": ""})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["prio"]) > int(b["prio"]))
	return out.slice(0, limit)


func _weekly_wages() -> float:
	var t := 0.0
	for w in sim.workers:
		t += float(w.wage) * 5.0
	return t


## Главный инженер — постоянный персонаж, его внешность не меняется.
static func engineer_look() -> Dictionary:
	return {"skin": 1, "hair": "short", "hair_col": "#a7a39c", "beard": "mustache", "glasses": true, "phones": false,
		"body": "m_norm", "bulk": 1.0, "fem": false, "h": 1.0, "outfit": "coat", "outfit_col": "#e4e6e3", "hat": "helmet", "hat_col": "#f2f2ee"}


# ================================================================ сохранение

func to_dict() -> Dictionary:
	return {"comps": comps, "policy": policy, "share": share, "share_hist": share_hist, "metal": metal, "metal_week": metal_week,
		"hist": hist, "outcomes": outcomes, "last_reclam": last_reclam, "iso": iso, "insurance": insurance, "claims": paid_claims,
		"leases": leases, "leasing_on": leasing_on, "memo": memo_on, "hd": _hd}


func from_dict(d: Dictionary) -> void:
	if d.is_empty():
		return
	comps = d.get("comps", comps)
	policy = str(d.get("policy", "market"))
	share = float(d.get("share", 0.0))
	share_hist = d.get("share_hist", [])
	metal = float(d.get("metal", 1.0))
	metal_week = float(d.get("metal_week", metal))
	hist = d.get("hist", [])
	outcomes = d.get("outcomes", [])
	last_reclam = int(d.get("last_reclam", -100))
	iso = d.get("iso", {"status": "none"})
	insurance = d.get("insurance", {})
	paid_claims = d.get("claims", {})
	leases = d.get("leases", [])
	leasing_on = bool(d.get("leasing_on", false))
	memo_on = bool(d.get("memo", true))
	_hd = int(d.get("hd", -1))
