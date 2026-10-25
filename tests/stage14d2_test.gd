extends SceneTree
## 1.39, перевод D2 (экономика в симуляции): в английском — ни одного русского слова в текстах экономики.
## Каждый сценарий гоняем несколько дней на английском и собираем: заказы, заявки сбыта, контракты, советы,
## ISO, причины простоя станков, цели и этапы, даты и сезоны, отчёт по статьям, уведомления и журнал денег.
## Тексты других частей перевода (письма, мысли людей…) в уведомлениях не считаем ошибкой D2: ошибка —
## только если русский текст подходит под шаблон из strings_d2.csv (значит, перевод не применён).
## Русские тексты не меняются (проверяем пару строк в русском), детерминизм — одинаковые деньги в ru и en.
## godot --headless --path . -s res://tests/stage14d2_test.gd

const S := preload("res://tests/setups.gd")

var fails: Array[String] = []
var _mine: Array[RegEx] = []


func check(cond: bool, what: String) -> void:
	print(("  ✓ " if cond else "  ✗ ") + what)
	if not cond:
		fails.append(what)


func _run(sim: Sim, days: float) -> void:
	var end := sim.minute + days * 1440.0
	while sim.minute < end:
		sim.tick(0.5)


## Шаблоны (русские ключи) этой части перевода — чтобы узнать «свой» непереведённый текст.
func _load_mine() -> void:
	var f := FileAccess.open("res://assets/i18n/strings_d2.csv", FileAccess.READ)
	f.get_csv_line()
	while not f.eof_reached():
		var row := f.get_csv_line()
		if row.size() < 2 or row[0].length() < 12:
			continue
		var k := row[0].replace("%%", "%")
		var parts := RegEx.create_from_string("%[-+0-9.]*[sdf]").sub(k, "\u0001", true).split("\u0001")
		var esc: Array[String] = []
		for p in parts:
			esc.append(_esc(p))
		var re := RegEx.create_from_string("^" + ".*".join(esc) + "$")
		if re.is_valid():
			_mine.append(re)


func _esc(s: String) -> String:
	var out := ""
	for ch in s:
		out += ("\\" + ch) if "\\^$.|?*+()[]{}".contains(ch) else ch
	return out


func _is_mine(t: String) -> bool:
	for re in _mine:
		if re.search(t) != null:
			return true
	return false


func _no_cyr(texts: Array, what: String) -> void:
	var bad: Array[String] = []
	for t in texts:
		if L.has_cyr(str(t)):
			bad.append(str(t).replace("\n", " ").left(110))
	check(bad.is_empty(), "%s: %d текстов без кириллицы%s" % [what, texts.size(), "" if bad.is_empty() else " — " + " | ".join(bad.slice(0, 5))])


func _collect(sim: Sim) -> Array:
	var out: Array = []
	var pg := sim.progress
	out.append(pg.stage_title())
	out.append(sim.season.date_str())
	out.append(sim.season.short_date())
	out.append(sim.season.long_date())
	out.append(sim.season.season_name())
	for st in range(1, Progress.STAGE_COUNT + 1):
		out.append(pg.stage_title(st))
	var sg := pg.scenario_goals()
	for gi in sg.size():
		out.append(L.dt("scn.%s.goal%d" % [sim.scenario, gi], str((sg[gi] as Dictionary).get("text", ""))))
		out.append(str(pg.goal_state(sg[gi])[1]))
	for g: Dictionary in pg.stage_goals() + (pg.stage_choice().get("list", []) as Array):
		out.append(L.t(str(g.get("text", ""))))
		out.append(str(pg.goal_state(g)[1]))
		if g.has("route"):
			out.append(L.t(str(g["route"])))
	out.append(L.dt("stage.%s.opens" % str(pg.stage_def().get("id", "")), str(pg.stage_def().get("opens", ""))))
	for o: Dictionary in sim.orders.list:
		out.append(sim.orders.short(o))
		out.append(sim.orders.deadline_str(o))
		out.append(Company.firm(str(o.get("client", ""))))
		out.append(L.tx(str(sim.sales.verdict(o)[0])))
	for e: Dictionary in sim.sales.log:
		out.append(L.tx(str(e["why"])))
	for c: Dictionary in sim.sales.contracts:
		out.append(sim.sales.contract_text(c))
	for a: Dictionary in sim.market.advice(20):
		out.append(str(a["title"]))
		out.append(str(a["text"]))
	out.append(sim.market.iso_text())
	for c2: Dictionary in sim.market.comps:
		out.append(Company.firm(str(c2["name"])))
	for m: Thing in sim.things_of("machine", false):
		var r := Stall.reason(sim, m)
		if not r.is_empty():
			out.append(str(r["why"]))
			out.append(str(r["hint"]))
		out.append(m.title())
		out.append(Defs.machine_spec(m.def_id))
	for id: String in ["fin2", "fin3"]:
		out.append(sim.dev.block_reason(id))
	for d: String in Defs.objects.keys():
		out.append(sim.progress.locked_reason(d))
	return out


## Уведомления и журнал денег: «свои» тексты (под шаблон strings_d2) должны быть по-английски.
func _check_log(sim: Sim, what: String) -> void:
	var bad: Array[String] = []
	var other := 0
	var n := 0
	for e: Dictionary in sim.events + sim.ledger:
		n += 1
		var t := str(e["text"])
		if not L.has_cyr(t):
			continue
		if _is_mine(t):
			bad.append(t.left(110))
		else:
			other += 1
	check(bad.is_empty(), "%s: уведомления и журнал денег (%d) — своих русских нет%s" % [what, n, "" if bad.is_empty() else " — " + " | ".join(bad.slice(0, 5))])
	if other > 0:
		print("    (русских строк других частей перевода: %d)" % other)
	# статьи отчёта считаются и по английским текстам
	var other_cat := 0
	for e3: Dictionary in sim.ledger:
		if Office.cat_of(str(e3["text"])) == "other":
			other_cat += 1
	print("    (операций в статье «Прочее»: %d из %d)" % [other_cat, sim.ledger.size()])


func _init() -> void:
	Defs.load_all()
	_load_mine()
	check(_mine.size() > 300, "шаблонов D2: %d" % _mine.size())

	print("— русский не изменился")
	L.apply("ru")
	var g0 := Scenario.new_game("garage", "mech", "calm", 1402)
	check(str(g0.events[-1]["text"]).begins_with("Добро пожаловать в «Промзону»!"), "приветствие по-русски")
	check(Company.firm("ООО «Техмаш-Регион»") == "ООО «Техмаш-Регион»", "название фирмы в русском — как есть")
	check(Office.cat_of("Оплата: втулки") == "sales" and Office.cat_of("Зарплата за неделю") == "wages", "статьи по-русски")
	_run(g0, 6.0)
	var ru_money := g0.money
	var ru_ev := g0.events.size()
	var ru_weeks := str(g0.office.weeks)
	var ru_sales := str(g0.sales.log.map(func(e: Dictionary) -> bool: return bool(e["ok"])))

	print("— английский")
	L.apply("en")
	check(L.t("Отсрочка платежа за металл") == "Deferred payment for metal", "перевод D2 загружен")
	check(Company.firm("ООО «Техмаш-Регион»") == "Tekhmash-Region LLC", "фирма: " + Company.firm("ООО «Техмаш-Регион»"))
	check(Company.firm("ТОО «Степьмаш» (Казахстан)") == "Stepmash LLP (Kazakhstan)", "фирма со страной: " + Company.firm("ТОО «Степьмаш» (Казахстан)"))
	check(Company.firm("ИП Гарипов") == "IE Garipov", "ИП: " + Company.firm("ИП Гарипов"))
	for cl in Defs.names.get("clients", []) + Sales.BIG_CLIENTS + OrderBook.EXPORT_CLIENTS + OrderBook.STATE_CLIENTS:
		if L.has_cyr(Company.firm(str(cl))):
			check(false, "заказчик латиницей: " + Company.firm(str(cl)))
	check(L.tx("Зарплата за неделю") == "Weekly wages" and L.tx("Электроэнергия: 120 кВт·ч") == "Electricity: 120 kWh", "готовая русская строка → английская: " + L.tx("Электроэнергия: 120 кВт·ч"))
	check(L.tx("Отопление: 3 radiators от электрокотла") == "Heating: 3 radiators from the electric boiler", "шаблон с подстановкой: " + L.tx("Отопление: 3 radiators от электрокотла"))

	var g1 := Scenario.new_game("garage", "mech", "calm", 1402)
	_run(g1, 6.0)
	check(str(g1.office.weeks) == ru_weeks and str(g1.sales.log.map(func(e: Dictionary) -> bool: return bool(e["ok"]))) == ru_sales, "статьи отчёта и решения сбыта как в русском")
	check(is_equal_approx(g1.money, ru_money) and g1.events.size() == ru_ev, "детерминизм: деньги и события как в русском (%.0f / %.0f)" % [g1.money, ru_money])

	for scn: String in ["garage", "field", "sandbox"]:
		print("— сценарий ", scn)
		var sim := Scenario.new_game(scn, "mech", "calm", 1403)
		if scn != "garage":
			S.big_shop(sim)
		_run(sim, 6.0)
		_no_cyr(_collect(sim), scn + ": тексты экономики")
		_check_log(sim, scn)
	# поздний этап: цели, контракты, ISO
	var big := Scenario.new_game("garage", "mech", "calm", 1404)
	S.big_shop(big)
	big.progress.stage = 3
	big.money = 3000000.0
	_run(big, 8.0)
	_no_cyr(_collect(big), "этап 3: тексты экономики")
	_check_log(big, "этап 3")
	L.apply("ru")

	print("РЕЗУЛЬТАТ: ", "OK" if fails.is_empty() else "ОШИБКИ: %d" % fails.size())
	quit(0 if fails.is_empty() else 1)
