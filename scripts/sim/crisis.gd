class_name Crisis
extends RefCounted
## 1.20 «Последствия»: что бывает, когда дела идут плохо.
## — Зарплата в долг: касса может уйти в минус ради зарплаты только раз в 3 месяца. Дальше зарплату задерживают:
##   люди жалуются, грозят уволиться и уходят — первым тот, у кого настроение хуже. Три ухода за две недели —
##   трудовая инспекция закрывает завод (конец игры).
## — Нет инструмента (расходников) и нет денег — письмо: взять в долг или ждать; станочники недовольны.
## — Долги и просрочки бьют по репутации каждый день; заказчик с просроченным заказом приезжает разбираться.

const CREDIT_DAYS := 90          ## раз в сколько дней зарплату можно выдать в долг
const QUIT_WINDOW := 14          ## «короткое время» для трёх увольнений
const QUITS_TO_CLOSE := 3

var sim: Sim
var wage_credit_day := -9999     ## когда в последний раз выдали зарплату в долг
var unpaid_since := -1           ## с какого дня зарплата задержана (-1 — долгов нет)
var arrears_quits: Array = []    ## дни увольнений из-за долгов по зарплате
var closed: Dictionary = {}      ## конец игры: {reason, title, text, day}
var tools_short := {}            ## расходник -> сколько дней подряд нечем работать и не на что купить
var visited: Dictionary = {}     ## id заказа -> заказчик уже приезжал
var debt_days := 0
var suits: Array = []            ## иски незаконно уволенных: [{name, due, sum}]


func _init(s: Sim) -> void:
	sim = s


func is_over() -> bool:
	return not closed.is_empty()


# ================================================================ зарплата

## Можно ли сейчас выдать зарплату в долг (касса уйдёт в минус).
func can_credit_wages() -> bool:
	return sim.day() - wage_credit_day >= CREDIT_DAYS


func credit_left_days() -> int:
	return maxi(0, CREDIT_DAYS - (sim.day() - wage_credit_day))


## Пятница: хватает денег — платим; нет — один раз в 3 месяца в долг; иначе задерживаем. true — выплачено.
func pay_wages(total: float) -> bool:
	if total <= 0.0:
		return true
	# сначала — старые долги, если теперь есть чем платить
	if sim.progress.arrears_total() > 0.0 and sim.money >= sim.progress.arrears_total() + total:
		sim.progress.pay_arrears()
		unpaid_since = -1
	if sim.money >= total:
		return true
	if can_credit_wages():
		wage_credit_day = sim.day()
		sim.story.info("Зарплату выдали в долг", "Денег на зарплату не хватило — выдали из резерва, касса ушла в минус. Так выручить можно только раз в три месяца: в следующий раз зарплату задержат, и люди начнут уходить. Срочно сдавайте заказы или берите кредит (Финансы → Кредиты).", "money", Sim.LVL_BAD, Vector2i(-1, -1), true)
		return true
	# задержка: долг каждому
	for w in sim.workers:
		var due := float(w.get_meta("wage_due", 0.0))
		if due > 0.0:
			w.set_meta("arrears", float(w.get_meta("arrears", 0.0)) + due)
		Mood.add(sim, w, "wage_late")
	if unpaid_since < 0:
		unpaid_since = sim.day()
	sim.story.letter("crisis_wages", "Нечем платить зарплату", "Денег нет, а в долг зарплату уже выдавали меньше трёх месяцев назад (снова можно через %d дн.). Люди остались без денег — жалуются и грозят уволиться. Если трое уйдут за две недели, придёт трудовая инспекция и закроет завод. Долг по зарплате: %s." % [credit_left_days(), Defs.money_str(sim.progress.arrears_total())],
		"strike", Sim.LVL_BAD, [{"text": "Взять кредит и выплатить", "hint": _loan_hint()}, {"text": "Попросить потерпеть до следующей недели", "hint": "Настроение упадёт ещё, кто-то может уйти"}], 1)
	return false


func _loan_hint() -> String:
	if sim.progress.stage < 2:
		return "Банки кредитуют с этапа «Мастерская» — сейчас не дадут"
	return "Кредит 800 000 ₽ на полгода, если банк одобрит"


func _wages_daily() -> void:
	var arr := sim.progress.arrears_total()
	if arr <= 0.0:
		unpaid_since = -1
		return
	if unpaid_since < 0:
		unpaid_since = sim.day()
	var days := sim.day() - unpaid_since
	sim.notify_once("arrears_daily", "Люди жалуются: зарплату задерживают уже %d дн. (долг %s). Грозят уволиться — выплатите: Финансы → «Выплатить долги по зарплате»." % [maxi(1, days), Defs.money_str(arr)], Sim.LVL_BAD, Vector2i(-1, -1), 1200.0)
	if days < 3:
		return
	# уходит тот, у кого настроение хуже всех
	var worst: Worker = null
	for w in sim.workers:
		if float(w.get_meta("arrears", 0.0)) <= 0.0:
			continue
		if worst == null or w.mood < worst.mood:
			worst = w
	if worst == null:
		return
	if worst.mood < 40.0 + float(days) * 3.0:
		_quit_unpaid(worst)


func _quit_unpaid(w: Worker) -> void:
	var owed := float(w.get_meta("arrears", 0.0))
	w.set_meta("arrears", 0.0)
	if owed > 0.0:
		sim.office.add_debt(owed, 2, "Долг уволившемуся по зарплате: " + w.full_name())
	var nm := w.full_name()
	var fem := w.female
	sim.fire(w, true)
	arrears_quits.append(sim.day())
	arrears_quits = arrears_quits.filter(func(dd: int) -> bool: return sim.day() - dd < QUIT_WINDOW)
	var n := arrears_quits.size()
	sim.notify(Nicks.gendered("%s уволил{ся|ась}: «Не платят — работать не буду». Уже %d за две недели — после %d-го придёт трудовая инспекция.", fem) % [nm, n, QUITS_TO_CLOSE], Sim.LVL_BAD)
	if n >= QUITS_TO_CLOSE:
		close("labor", "Трудовая инспекция закрыла завод",
			"За две недели %d человек уволились, потому что им не платили зарплату. Они написали жалобу — трудовая инспекция проверила ведомости, наложила арест на счёт и приостановила деятельность предприятия. Завод закрыт." % n)


## Конец игры.
func close(reason: String, title: String, text: String) -> void:
	if is_over():
		return
	closed = {"reason": reason, "title": title, "text": text, "day": sim.day(), "date": sim.date_str()}
	sim.notify(title + ". " + text, Sim.LVL_BAD)


# ================================================================ инструмент и расходники

func _tools_daily() -> void:
	var av := sim.prod.processes_available()
	var used := {}
	for pr in av.keys():
		var c := str(Defs.processes.get(pr, {}).get("cons", ""))
		if c != "":
			used[c] = true
	for c2: String in used.keys():
		var cd: Dictionary = Defs.consumables.get(c2, {})
		var low := float(sim.cons.get(c2, 0.0)) < 2.0 and not sim.cons_on_way(c2)
		var broke := not sim.can_afford(float(cd.get("price", 0.0)))
		if low and broke:
			tools_short[c2] = int(tools_short.get(c2, 0)) + 1
			for w in sim.workers:
				if not w.is_itr():
					Mood.add(sim, w, "no_tools")
			if int(tools_short[c2]) == 1 and sim.story.get_letter_by_ev("crisis_tools").is_empty():
				sim.story.letter("crisis_tools", "Нечем работать: кончился %s" % str(cd.get("short", c2)),
					"%s закончился, а денег на новый (%s) нет. Станки стоят, люди простаивают, жалуются и грозят уволиться." % [str(cd.get("name", c2)), Defs.money_str(float(cd.get("price", 0.0)))],
					"wrench", Sim.LVL_BAD, [{"text": "Взять у поставщика в долг", "hint": "%s через две недели (+10%%)" % Defs.money_str(float(cd.get("price", 0.0)) * 1.1)},
						{"text": "Пусть ждут денег", "hint": "Настроение падает каждый день"}], 0, {"cons": c2})
		else:
			tools_short.erase(c2)


# ================================================================ репутация: долги и просрочки, заказчики

func _debt_daily() -> void:
	if sim.money < 0.0:
		debt_days += 1
		if debt_days >= 2:
			sim.reputation = maxf(0.0, sim.reputation - 1.0)
			sim.notify_once("debt_rep", "Завод в долгах %d дн.: поставщики и заказчики это знают — репутация падает каждый день, сбыт новых заказов не берёт." % debt_days, Sim.LVL_BAD, Vector2i(-1, -1), 1200.0)
	else:
		debt_days = 0


func _clients_daily() -> void:
	var hits := 0
	for o: Dictionary in sim.orders.by_status(["active"]):
		var late := (sim.minute - float(o["deadline"])) / 1440.0
		if late <= 0.0:
			continue
		hits += 1
		var promise := float(o.get("promise", -1.0))
		if promise > 0.0 and sim.minute > promise:
			o["promise"] = -1.0
			sim.orders.fail(o, "Заказчик не дождался обещанного срока и расторг договор со скандалом")
			sim.reputation = maxf(0.0, sim.reputation - 4.0)
			continue
		if late >= 2.0 and not visited.has(int(o["id"])) and sim.story.get_letter_by_ev("crisis_client").is_empty():
			visited[int(o["id"])] = true
			var sum := float(o["price"]) * int(o["qty"])
			sim.story.letter("crisis_client", "Заказчик приехал разбираться",
				"Представитель «%s» приехал на завод: заказ «%s» просрочен на %d дн. Требует объяснений и денег за срыв графика." % [str(o["client"]), sim.orders.short(o), int(late)],
				"handshake", Sim.LVL_BAD, [{"text": "Извиниться и заплатить неустойку", "hint": "%s, срок +4 дня" % Defs.money_str(sum * 0.1)},
					{"text": "Пообещать сдать за 2 дня", "hint": "Не успеете — заказ отменят со скандалом"},
					{"text": "Отказаться от заказа", "hint": "Неустойка %s, репутация −6" % Defs.money_str(sum * 0.05)}], 0, {"order": int(o["id"])})
	if hits > 0:
		sim.reputation = maxf(0.0, sim.reputation - minf(3.0, float(hits)))


func on_letter(ev: String, d: Dictionary, choice: int) -> void:
	match ev:
		"crisis_wages":
			if choice == 0:
				var err := sim.office.take_loan(800000.0, 26)
				if err != "":
					sim.notify("Кредит не дали: %s." % err, Sim.LVL_BAD)
				else:
					var e2 := sim.progress.pay_arrears()
					if e2 == "":
						unpaid_since = -1
			else:
				for w in sim.workers:
					Mood.add(sim, w, "wage_late")
		"crisis_tools":
			var c := str(d.get("cons", "tools"))
			var cd: Dictionary = Defs.consumables.get(c, {})
			if choice == 0 and not cd.is_empty():
				sim.office.add_debt(float(cd["price"]) * 1.1, 2, "Отсрочка платежа за расходники")
				sim.cons_supply.append({"cons": c, "packs": 1, "eta": sim.to_work_time(sim.minute + 120.0)})
				sim.notify("Поставщик отгрузил %s в долг — привезут через пару часов." % str(cd.get("pack", c)), Sim.LVL_WARN)
				tools_short.erase(c)
		"crisis_client":
			var o := sim.orders.get_order(int(d.get("order", -1)))
			if o.is_empty() or str(o["status"]) != "active":
				return
			var sum := float(o["price"]) * int(o["qty"])
			match choice:
				0:
					sim.spend(sum * 0.1, "Неустойка заказчику: " + sim.orders.short(o))
					o["deadline"] = float(o["deadline"]) + 4.0 * 1440.0
					sim.reputation = maxf(0.0, sim.reputation - 1.0)
					sim.notify("Заказчик принял извинения: срок продлён на 4 дня.", Sim.LVL_INFO)
				1:
					o["promise"] = sim.minute + 2.0 * 1440.0
					sim.notify("Пообещали сдать «%s» за 2 дня. Не успеете — заказ отменят." % sim.orders.short(o), Sim.LVL_WARN)
				2:
					sim.spend(sum * 0.05, "Неустойка за отказ: " + sim.orders.short(o))
					sim.orders.fail(o, "Отказались от заказа")
					sim.reputation = maxf(0.0, sim.reputation - 6.0)


# ================================================================ увольнение: причина

## Причины увольнения. legal — есть ли законное основание у этого человека; why — почему да или нет.
func fire_reasons(w: Worker) -> Array:
	var out: Array = []
	var abs_n := int(w.get_meta("absences", 0))
	var theft := int(w.get_meta("caught_theft", 0))
	var tenure := sim.day() - w.hired_day
	var weak := w.grade() <= 1 and tenure >= 20 and not w.is_itr()
	var sev := float(w.wage) * 10.0
	var agree := float(w.wage) * 5.0
	out.append({"key": "agree", "name": "По соглашению сторон", "legal": true, "cost": agree,
		"why": "Договорились по-хорошему: компенсация %s. Остальные спокойны." % Defs.money_str(agree)})
	out.append({"key": "cut", "name": "Сокращение штата", "legal": true, "cost": sev,
		"why": "Законно, но положено выходное пособие — %s (две недели ставки). Люди слегка тревожатся." % Defs.money_str(sev)})
	out.append({"key": "absence", "name": "За прогулы", "legal": abs_n > 0, "cost": 0.0,
		"why": ("Прогулов: %d — основание есть, без выплат." % abs_n) if abs_n > 0 else "Прогулов не было — уволенный пойдёт в суд и к инспектору."})
	out.append({"key": "theft", "name": "За кражу (по статье)", "legal": theft > 0, "cost": 0.0,
		"why": "Пойман%s на краже — основание есть, честные одобрят." % ("а" if w.female else "") if theft > 0 else "На краже не ловили — это клевета, будет суд."})
	out.append({"key": "weak", "name": "Не справляется с работой", "legal": weak, "cost": 0.0,
		"why": "Низкий разряд и брак после испытательного срока — по аттестации можно." if weak else "Работает нормально или ещё на испытательном сроке (20 дней) — оснований нет."})
	out.append({"key": "none", "name": "Без причины", "legal": false, "cost": 0.0,
		"why": "Незаконно: уволенный подаст в суд (≈ %s) и пожалуется в трудовую инспекцию, остальные обидятся." % Defs.money_str(float(w.wage) * 15.0)})
	return out


## Уволить с причиной. Возвращает текст результата.
func fire_with(w: Worker, key: String) -> String:
	var r: Dictionary = {}
	for x: Dictionary in fire_reasons(w):
		if str(x["key"]) == key:
			r = x
	if r.is_empty():
		return "Неизвестная причина"
	var cost := float(r["cost"])
	if cost > 0.0 and not sim.can_afford(cost):
		return "Не хватает денег на выплату: %s" % Defs.money_str(cost)
	var nm := w.full_name()
	var fem := w.female
	var wage := float(w.wage)
	w.set_meta("fire_reason", "theft" if key == "theft" and bool(r["legal"]) else key)
	if cost > 0.0:
		sim.spend(cost, "%s: %s" % [str(r["name"]), nm])
	var legal := bool(r["legal"])
	var calm := legal and key in ["agree", "absence", "theft", "weak"]
	sim.fire(w, false, calm)
	if legal:
		if key == "cut":
			for o in sim.workers:
				Mood.add(sim, o, "coworker_fired")
		return Nicks.gendered("%s уволен{|а}: %s.", fem) % [nm, str(r["name"]).to_lower()]
	# незаконно: суд, жалоба, обида
	var sum := wage * 15.0 * (0.5 if sim.office.active("legal") else 1.0)
	suits.append({"name": nm, "due": sim.day() + 7, "sum": sum})
	sim.inspect.schedule("labor", sim.minute + 3.0 * 1440.0, false, "жалоба уволенного")
	sim.reputation = maxf(0.0, sim.reputation - 2.0)
	for o in sim.workers:
		Mood.add(sim, o, "coworker_fired")
	sim.notify(Nicks.gendered("%s уволен{|а} без законной причины и подал{|а} в суд: через неделю суд, придётся заплатить ≈ %s. И жалоба в трудовую инспекцию.", fem) % [nm, Defs.money_str(sum)], Sim.LVL_BAD)
	return Nicks.gendered("%s уволен{|а} незаконно — будет суд.", fem) % nm


func _suits_daily() -> void:
	var keep: Array = []
	for su: Dictionary in suits:
		if sim.day() >= int(su["due"]):
			var sum := float(su["sum"])
			sim.spend(sum, "Суд: незаконное увольнение (%s)" % str(su["name"]))
			sim.reputation = maxf(0.0, sim.reputation - 2.0)
			sim.notify("Суд восстановил справедливость: %s уволили незаконно. Завод выплатил %s за вынужденный прогул и моральный вред." % [str(su["name"]), Defs.money_str(sum)], Sim.LVL_BAD)
		else:
			keep.append(su)
	suits = keep


func morning() -> void:
	if is_over():
		return
	_suits_daily()
	_wages_daily()
	_tools_daily()
	_debt_daily()
	_clients_daily()


func to_dict() -> Dictionary:
	return {"wcd": wage_credit_day, "unpaid": unpaid_since, "quits": arrears_quits, "closed": closed, "tools": tools_short,
		"visited": visited.keys().map(func(k: Variant) -> String: return str(k)), "debt_days": debt_days, "suits": suits}


func from_dict(d: Dictionary) -> void:
	wage_credit_day = int(d.get("wcd", -9999))
	unpaid_since = int(d.get("unpaid", -1))
	arrears_quits = []
	for q in d.get("quits", []):
		arrears_quits.append(int(q))
	closed = d.get("closed", {})
	tools_short = d.get("tools", {})
	visited = {}
	for k in d.get("visited", []):
		visited[int(str(k))] = true
	debt_days = int(d.get("debt_days", 0))
	suits = d.get("suits", [])
