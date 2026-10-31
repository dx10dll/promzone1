extends SceneTree
## Тест 1.62 «Разгрузка: деньги и рынок»: гранты реже и с выбором (заявка за деньги и время, может быть отказ),
## страховка — одна галочка, торгового кредита поставщика нет (старые сейвы грузятся), «Рынок» — одна карточка.
## Окно игры в режиме -s не собрать (автозагрузки), поэтому карточки проверяются в stage162_ui.tscn — этот файл запускает её отдельно.
## godot --headless --path . --audio-driver Dummy -s res://tests/stage162_test.gd

const S := preload("res://tests/setups.gd")

var fails: Array[String] = []


func check(cond: bool, what: String) -> void:
	print(("  ✓ " if cond else "  ✗ ") + what)
	if not cond:
		fails.append(what)


func _run(sim: Sim, minutes: float) -> void:
	var end := sim.minute + minutes
	while sim.minute < end:
		sim.tick(1.0)


func _game(seed_v: int) -> Sim:
	var g := Scenario.new_game("garage", "mech", "calm", seed_v)
	g.story.enabled = false
	g.progress.tutorial = -1
	return g


## Перемотка дней без полной симуляции: только программы поддержки.
func _grant_days(sim: Sim, upto_day: int, answer: int) -> Array[int]:
	var days: Array[int] = []
	while sim.day() < upto_day:
		sim.minute = float(sim.day()) * 1440.0 + 9.0 * 60.0   # следующий день
		sim.grants._t = 0.0
		var before := sim.grants.offered
		sim.grants.tick(1.0)
		if sim.grants.offered > before:
			days.append(sim.day())
			var l := sim.story.get_letter_by_ev("grant_offer")
			if answer >= 0 and not l.is_empty():
				sim.story.resolve(int(l["id"]), answer)
			elif not l.is_empty():
				sim.story.letters.erase(l)
	return days


func _initialize() -> void:
	print("— гранты: раз в 2–3 недели")
	var g := _game(1620)
	g.story.enabled = true
	g.minute = 2.0 * 1440.0
	var days := _grant_days(g, 150, 1)
	check(days.size() >= 5 and days.size() <= 9, "за ~150 дней памяток: %d %s" % [days.size(), str(days)])
	var gaps_ok := true
	for i in range(1, days.size()):
		var gap := days[i] - days[i - 1]
		if gap < 14 or gap > 21:
			gaps_ok = false
	check(gaps_ok and not days.is_empty(), "между памятками 14–21 день (первая — день %d)" % (days[0] if not days.is_empty() else -1))
	check(g.grants.offered == days.size() and g.grants.active.is_empty() and g.grants.pending.is_empty(), "пропуск ничего не берёт и не стоит денег")
	check(not Defs.events["events"].has("grant") or float(Defs.events["events"]["grant"]["w"]) == 0.0, "старое случайное событие «грант» выключено")

	print("— гранты: выбор «Подать заявку»")
	var a := _game(1621)
	a.story.enabled = true
	a.minute = 30.0 * 1440.0
	a.grants.next_offer = 0
	a.grants._t = 0.0
	a.grants.tick(1.0)
	var l1 := a.story.get_letter_by_ev("grant_offer")
	check(not l1.is_empty() and (l1["choices"] as Array).size() == 2, "памятка — карточка решения из двух вариантов")
	check(str((l1["choices"] as Array)[0]["text"]).begins_with("Подать заявку") and str((l1["choices"] as Array)[1]["text"]) == "Пропустить" and int(l1["def"]) == 1, "«Подать заявку» / «Пропустить», по умолчанию — пропустить")
	var gid := str((l1["data"] as Dictionary)["id"])
	var gd := Grants.def(gid)
	var fee := Grants.fee_of(gd)
	var ndays := Grants.docs_days(gd)
	check(fee >= 2000.0 and ndays >= 3, "заявка стоит %s и %d дн. документов" % [Defs.money_str(fee), ndays])
	var m0 := a.money
	a.story.resolve(int(l1["id"]), 0)
	check(absf(m0 - a.money - fee) < 0.5, "заявка списала расходы: %s" % Defs.money_str(m0 - a.money))
	check(a.grants.pending.size() == 1 and a.grants.active.is_empty(), "результат не сразу: заявка ждёт, программы нет")
	var ready := int((a.grants.pending[0] as Dictionary)["ready"])
	check(ready - a.day() == ndays, "решение через %d дн." % ndays)
	var dd := a.to_dict()
	var ad := Sim.from_dict(JSON.parse_string(JSON.stringify(dd)))
	check(ad.grants.pending.size() == 1 and ad.grants.next_offer == a.grants.next_offer, "заявка и срок следующей памятки сохраняются")
	ad.dispose()
	# одобрение: p = 1
	(a.grants.pending[0] as Dictionary)["p"] = 1.0
	a.minute = float(ready - 2) * 1440.0 + 600.0
	a.grants._t = 0.0
	a.grants.tick(1.0)
	check(a.grants.pending.size() == 1, "до срока решения нет")
	a.minute = float(ready) * 1440.0 + 600.0
	a.grants._t = 0.0
	a.grants.tick(1.0)
	check(a.grants.pending.is_empty() and a.grants.is_active(gid), "заявку одобрили — программа в работе")
	check(a.money <= m0 - fee + 1.0, "возмещения нет, пока условия не выполнены")
	# отказ: p = 0
	var b := _game(1622)
	b.story.enabled = true
	b.minute = 30.0 * 1440.0
	var mb := b.money
	check(b.grants.apply("canteen") == "", "заявка подана напрямую")
	(b.grants.pending[0] as Dictionary)["p"] = 0.0
	b.minute = float(int((b.grants.pending[0] as Dictionary)["ready"])) * 1440.0 + 600.0
	b.grants._t = 0.0
	b.grants.tick(1.0)
	check(b.grants.active.is_empty() and b.grants.rejected.has("canteen") and b.money < mb, "отказ: программы нет, расходы не вернули")
	check(b.grants.apply("canteen") == "", "после отказа заявку можно подать снова вручную")
	b.money = 100.0
	check(b.grants.apply("workshop") != "", "без денег заявку не подать")

	print("— гранты: шанс зависит от репутации, ISO и этапа")
	var c := _game(1623)
	c.reputation = 20.0
	var p_low := c.grants.approval_chance()
	c.reputation = 90.0
	var p_hi := c.grants.approval_chance()
	c.market.iso = {"status": "ok", "until": 99999}
	var p_iso := c.grants.approval_chance()
	check(p_low < p_hi and p_hi < p_iso and p_low >= 0.25 and p_iso <= 0.92, "репутация и ISO повышают шанс: %d%% → %d%% → %d%%" % [int(p_low * 100.0), int(p_hi * 100.0), int(p_iso * 100.0)])

	print("— страховка: одна галочка")
	var s := _game(1624)
	S.big_shop(s)
	s.office.all_depts = true
	var mk := s.market
	var price := mk.monthly_premium()
	check(price >= 3000.0 and absf(price - roundf(price / 100.0) * 100.0) < 0.01, "цена в месяц понятная, кратна 100 ₽: %s" % Defs.money_str(price))
	var weekly := 0.0
	for k in Market.INSURANCE.keys():
		weekly += mk.premium(str(k))
	check(absf(price - weekly * float(s.season.dpm()) / 7.0) <= 50.0, "цена = сумма прежних трёх взносов, пересчитанная на месяц")
	var f0 := s.money
	mk.claim("property", 30000.0, "до полиса")
	check(s.money == f0, "без галочки возмещения нет")
	var m1 := s.money
	mk.set_insure_all(true)
	check(mk.insure_all and absf(m1 - s.money - price) < 1.0, "галочка: первый взнос %s" % Defs.money_str(m1 - s.money))
	check(mk.insurance.has("property") and mk.insurance.has("liability") and mk.insurance.has("accident"), "одна галочка включает все три вида")
	check(mk.claim("property", 30000.0, "в день оформления") == 0.0, "действует со следующего дня")
	_run(s, 1440.0)
	var m2 := s.money
	s.story._fire_out(false)
	check(s.money - m2 >= 19999.0, "пожар: возмещено %s (80%% ущерба)" % Defs.money_str(s.money - m2))
	m2 = s.money
	check(absf(mk.claim("property", 30000.0, "ремонт станка") - 24000.0) < 1.0, "поломка станка: 80% ремонта")
	check(absf(mk.claim("liability", 10000.0, "неустойка") - 5000.0) < 1.0, "ответственность: половина неустойки")
	check(absf(mk.claim("accident", 40000.0, "Н-1") - 40000.0) < 1.0, "несчастный случай: полностью")
	# ежемесячный взнос
	var cur_dom := s.season.dom()
	var to_first := float(s.season.dpm() - cur_dom + 1) * 1440.0
	var m3 := s.money
	_run(s, to_first + 600.0)
	var spent := m3 - s.money
	check(spent >= price - 1.0 or s.season.dom() != 1, "в первый день месяца списан взнос (потрачено за период %s)" % Defs.money_str(spent))
	mk.set_insure_all(false)
	check(not mk.insure_all and mk.insurance.is_empty() and mk.claim("property", 30000.0, "после отказа") == 0.0, "снять галочку — страховка расторгнута")
	var s2 := _game(1625)
	s2.market.set_insure_all(true)
	check(not s2.market.insure_all, "без ступени «Банк и лизинг» галочку не включить")
	var sv := Sim.from_dict(JSON.parse_string(JSON.stringify(s.to_dict())))
	check(not sv.market.insure_all, "сохранение: галочка выключена — так и остаётся")
	mk.set_insure_all(true)
	var sv2 := Sim.from_dict(JSON.parse_string(JSON.stringify(s.to_dict())))
	check(sv2.market.insure_all and sv2.market.insured("property") or sv2.market.insurance.has("accident"), "сохранение: галочка и полисы сохраняются")
	sv.dispose()
	sv2.dispose()

	print("— старый сейв: отдельные полисы и торговый кредит")
	var o := _game(1626)
	S.big_shop(o)
	o.office.all_depts = true
	var od := o.to_dict()
	(od["market"] as Dictionary).erase("insure_all")
	(od["market"] as Dictionary)["insurance"] = {"property": {"since": 1}, "accident": {"since": 1}}
	var office_d: Dictionary = od["office"]
	(office_d["loans"] as Array).append({"amount": 80000.0, "payment": 40000.0, "left": 2, "rate": 0.0, "title": "Отсрочка платежа за металл"})
	(office_d["loans"] as Array).append({"amount": 90000.0, "payment": 30000.0, "left": 3, "rate": 0.0, "title": "Отсрочка платежа за расходники"})
	var ol := Sim.from_dict(JSON.parse_string(JSON.stringify(od)))
	check(ol.market.insure_all and ol.market.insurance.size() == 3, "старые полисы объединены в «Застраховать всё»")
	check(ol.market.insured("property") and ol.market.insured("liability") and ol.market.insured("accident") or ol.day() < 2, "покрытие сохранено")
	check(ol.office.loans.size() == 2 and ol.office.loans.all(func(ln: Dictionary) -> bool: return bool(ln.get("legacy", false)) and not str(ln["title"]).begins_with("Отсрочка")), "торговые долги — обычный долг без процентов под новым названием")
	var debt_before := ol.office.debt()
	check(absf(debt_before - (80000.0 + 90000.0)) < 1.0, "долг сохранён: %s" % Defs.money_str(debt_before))
	ol.money = 500000.0
	ol.progress.stage = 2
	check(ol.office.take_loan(300000.0, 26) == "", "старые отсрочки не занимают место в лимите банка")
	for i in 3:
		ol.office.on_monday()
	check(ol.office.loans.all(func(ln: Dictionary) -> bool: return not bool(ln.get("legacy", false))), "старые долги погашены по графику за три понедельника")
	_run(ol, 3.0 * 1440.0)
	check(true, "старый сейв живёт дальше (день %d)" % ol.day())
	ol.dispose()
	var oo := _game(1627)
	var od2 := oo.to_dict()
	(od2["market"] as Dictionary).erase("insure_all")
	(od2["market"] as Dictionary)["insurance"] = {}
	var ol2 := Sim.from_dict(JSON.parse_string(JSON.stringify(od2)))
	check(not ol2.market.insure_all and ol2.market.insurance.is_empty(), "старый сейв без полисов: страховки нет")
	ol2.dispose()

	print("— торгового кредита нет")
	var t := _game(1628)
	t.money = 0.0
	var debt0 := t.office.debt()
	check(t.order_material("bar45", 20) != "" and t.office.debt() == debt0, "нет денег — металл в долг не дают")
	check(not t.has_method("trade_credit_left"), "лимита торгового кредита в коде нет")
	t.money = 5000.0
	t.crisis.tools_short.clear()

	print("— рынок: карточка, 3–4 группы")
	var m := _game(1629)
	S.big_shop(m)
	var mkt := m.market
	var groups := mkt.card_groups()
	check(groups.size() >= 3 and groups.size() <= 4, "групп изделий: %d" % groups.size())
	var ids := {}
	for gr: Dictionary in groups:
		ids[str(gr["id"])] = true
		check(["up", "down", "flat"].has(str(gr["trend"])) and ["▲", "▼", "►"].has(str(gr["arrow"])), "группа «%s»: %s %s" % [str(gr["name"]), str(gr["arrow"]), str(gr["trend"])])
		var cd: Dictionary = gr["comp"]
		check(not cd.is_empty() and mkt.comp(str(cd["id"])).size() > 0 and not str(cd["name"]).is_empty(), "один главный конкурент: %s (%d%%)" % [str(cd.get("name", "")), int(float(cd.get("share", 0.0)) * 100.0)])
	check(ids.size() == groups.size(), "группы не повторяются")
	# спрос растёт / падает / ровный по ценам изделий
	for pid in Defs.products.keys():
		m.sales.market_prev[pid] = 1.0
		m.sales.market[pid] = 1.12
	check(mkt.card_groups().all(func(x: Dictionary) -> bool: return str(x["trend"]) == "up"), "цены растут — «спрос растёт»")
	for pid2 in Defs.products.keys():
		m.sales.market_prev[pid2] = 1.1
		m.sales.market[pid2] = 0.9
	check(mkt.card_groups().all(func(x: Dictionary) -> bool: return str(x["trend"]) == "down"), "цены падают — «спрос падает»")
	for pid3 in Defs.products.keys():
		m.sales.market_prev[pid3] = 1.0
		m.sales.market[pid3] = 1.0
	check(mkt.card_groups().all(func(x: Dictionary) -> bool: return str(x["trend"]) == "flat"), "всё спокойно — «спрос ровный»")
	# главный конкурент: сильнейший по доле среди специализирующихся на переделах группы
	for cp: Dictionary in mkt.comps:
		cp["share"] = 0.05
	var kov := mkt.comp("kovalchuk")
	if kov.is_empty():
		kov = mkt.comps[0]
	var special: Array = (kov["spec"] as Array).duplicate()
	kov["share"] = 0.5
	var mc := mkt.main_competitor(special)
	check(str(mc["id"]) == str(kov["id"]), "главный конкурент группы — сильнейший по доле: %s" % str(mc["name"]))
	check(Market.group_of("pin") == "turn" and Market.group_of("frame") == "weld" and Market.group_of("gearbox") == "asm", "изделия разложены по группам")
	var rv := Rivals.dir_of(mc)
	check(not str(rv["name"]).is_empty(), "директор конкурента (1.53) на месте: %s" % Rivals.dname(mc))
	var before_share := mkt.share
	m.dispose()

	print("— окна: рынок, страховка, гранты")
	var out: Array = []
	var code := OS.execute(OS.get_executable_path(), ["--headless", "--path", ProjectSettings.globalize_path("res://"),
		"--audio-driver", "Dummy", "res://tests/stage162_ui.tscn"], out, true)
	var text := "\n".join(PackedStringArray(out))
	for ln in text.split("\n"):
		if ln.contains("✓") or ln.contains("✗") or ln.contains("—") or ln.contains("ERROR"):
			print(ln)
	check(code == 0 and text.contains("ВСЁ ВЕРНО"), "окна «Рынок», «Страхование», «Гранты» (код %d)" % code)
	if before_share < 0.0:
		pass
	print("РЕЗУЛЬТАТ: " + ("ВСЁ ВЕРНО" if fails.is_empty() else "ОШИБКИ: %d" % fails.size()))
	quit(0 if fails.is_empty() else 1)
