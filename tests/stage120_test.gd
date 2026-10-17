extends SceneTree
## Тест версии 1.20 «Последствия»: зарплата в долг раз в 3 месяца, задержка зарплаты и уходы,
## закрытие завода инспекцией, сбыт и снабжение в долгах, пауза приёма заказов, просрочки в рейтинге,
## причины увольнения и суд, насосная без лимита (одна на завод), электрокотёл для батарей,
## пояснения «как исправить» у нарушений, кликабельные уведомления, миграция v12.
## godot --headless --path . -s res://tests/stage120_test.gd

var fails: Array[String] = []


func check(cond: bool, what: String) -> void:
	print(("  ✓ " if cond else "  ✗ ") + what)
	if not cond:
		fails.append(what)


func _game(seed_v: int) -> Sim:
	var g := Scenario.new_game("garage", "mech", "calm", seed_v)
	g.story.enabled = false
	g.progress.tutorial = -1
	g.bmats.enabled = false
	return g


func _staff(g: Sim) -> Array[Worker]:
	var out: Array[Worker] = []
	for w in g.workers:
		if not w.visitor:
			out.append(w)
	return out


func _init() -> void:
	Defs.load_all()

	print("— зарплата в долг и задержка")
	var g := _game(201)
	var ws := _staff(g)
	check(ws.size() >= 2, "в гараже есть люди: %d" % ws.size())
	for w in ws:
		w.set_meta("wage_due", 10000.0)
	g.money = 5000.0
	check(g.crisis.can_credit_wages(), "в долг можно")
	check(g.crisis.pay_wages(10000.0 * ws.size()), "первый раз зарплату выдали в долг")
	check(not g.crisis.can_credit_wages() and g.crisis.credit_left_days() > 80, "второй раз — только через 3 месяца (%d дн.)" % g.crisis.credit_left_days())
	check(not g.crisis.pay_wages(10000.0 * ws.size()), "второй раз денег нет — зарплату задержали")
	check(g.progress.arrears_total() >= 10000.0 * ws.size() - 1.0, "долг по зарплате: %s" % Defs.money_str(g.progress.arrears_total()))
	check(not g.story.get_letter_by_ev("crisis_wages").is_empty(), "письмо «Нечем платить зарплату»")
	check(g.crisis.unpaid_since >= 0, "задержка отмечена")
	# выплата долга
	g.money = 1000000.0
	var e := g.progress.pay_arrears()
	check(e == "" and g.progress.arrears_total() <= 0.0, "долги по зарплате выплачены")

	print("— три ухода за две недели — инспекция закрывает завод")
	var g2 := _game(202)
	for i in 3:
		var w2 := Worker.new()
		w2.id = g2.new_id()
		w2.first = "Тест"
		w2.last = "Тестов%d" % i
		w2.prof = "laborer"
		w2.set_meta("arrears", 5000.0)
		g2.workers.append(w2)
	var quitters: Array[Worker] = []
	for w3 in g2.workers:
		if float(w3.get_meta("arrears", 0.0)) > 0.0:
			quitters.append(w3)
	for w4 in quitters:
		g2.crisis._quit_unpaid(w4)
	check(g2.crisis.is_over(), "завод закрыт")
	check(str(g2.crisis.closed.get("reason", "")) == "labor", "причина — трудовая инспекция")
	var m0 := g2.minute
	g2.tick(5.0)
	check(g2.minute == m0, "после закрытия время стоит")
	var d2 := g2.to_dict()
	var g2b := Sim.from_dict(d2)
	check(g2b.crisis.is_over(), "закрытие сохраняется")

	print("— сбыт и снабжение в долгах, пауза приёма")
	var g3 := _game(203)
	g3.progress.quiet_until = -1
	var off := g3.orders.make_offer()
	if off.is_empty():
		off = {"product": "bolt", "qty": 10, "price": 2000.0, "deadline": g3.minute + 10000.0, "client": "Тест", "id": 999}
	g3.money = -1000.0
	var vd: Array = g3.sales.verdict(off)
	check(str(vd[0]).contains("долг"), "в долгах сбыт не берёт: «%s»" % str(vd[0]))
	g3.money = 500000.0
	g3.sales.paused = true
	vd = g3.sales.verdict(off)
	check(str(vd[0]).contains("пауз"), "пауза приёма: «%s»" % str(vd[0]))
	g3.sales.paused = false
	g3.money = 100.0
	var mat := str(Defs.materials.keys()[0])
	var debt0 := g3.office.debt()
	var err := g3.order_material(mat, 10, true)
	check(err != "" and g3.office.debt() == debt0, "снабжение само в долг металл не покупает")
	var g3d := Sim.from_dict(g3.to_dict())
	g3.sales.paused = true
	g3d = Sim.from_dict(g3.to_dict())
	check(g3d.sales.paused, "пауза сохраняется")

	print("— просрочки в рейтинге и сроках")
	var g4 := _game(204)
	var o4 := {"id": g4.new_id(), "product": "bolt", "qty": 10, "price": 2000.0, "status": "active", "deadline": g4.minute - 3.0 * 1440.0,
		"client": "Завод-тест", "made": 0, "shipped": 0, "allocated": 0, "accepted": g4.minute - 5000.0}
	g4.orders.list.append(o4)
	check(g4.market.ontime() < 0.8, "просроченный заказ портит долю «в срок»: %.2f" % g4.market.ontime())
	g4.progress._rate()
	check(float(g4.progress.rating["output"]) < 0.6, "и рейтинг выпуска: %.2f" % float(g4.progress.rating["output"]))
	var rep0 := g4.reputation
	g4.crisis._clients_daily()
	check(g4.reputation < rep0, "просрочка бьёт по репутации: %d → %d" % [int(rep0), int(g4.reputation)])
	check(not g4.story.get_letter_by_ev("crisis_client").is_empty(), "заказчик приехал разбираться")
	g4.crisis.on_letter("crisis_client", {"order": int(o4["id"])}, 1)
	check(float(o4.get("promise", -1.0)) > g4.minute, "пообещали за 2 дня")
	g4.minute = float(o4["promise"]) + 10.0
	g4.crisis._clients_daily()
	check(str(o4["status"]) == "failed", "не успели — заказ отменён")
	g4.money = -10.0
	var rep1 := g4.reputation
	g4.crisis._debt_daily()
	g4.crisis._debt_daily()
	check(g4.reputation < rep1, "долги бьют по репутации")

	print("— причины увольнения")
	var g5 := _game(205)
	var w5: Worker = _staff(g5)[0]
	var rs: Array = g5.crisis.fire_reasons(w5)
	var keys: Array = rs.map(func(r: Dictionary) -> String: return str(r["key"]))
	check(keys.has("agree") and keys.has("absence") and keys.has("none"), "есть причины: %s" % ", ".join(PackedStringArray(keys)))
	var abs_r: Dictionary = rs.filter(func(r: Dictionary) -> bool: return str(r["key"]) == "absence")[0]
	check(not bool(abs_r["legal"]), "без прогулов «за прогулы» — нет оснований")
	w5.set_meta("absences", 2)
	abs_r = g5.crisis.fire_reasons(w5).filter(func(r: Dictionary) -> bool: return str(r["key"]) == "absence")[0]
	check(bool(abs_r["legal"]), "с прогулами — законно")
	var n5 := g5.workers.size()
	g5.crisis.fire_with(w5, "absence")
	check(g5.workers.size() == n5 - 1 and g5.crisis.suits.is_empty(), "уволен за прогулы, без суда")
	var w6: Worker = _staff(g5)[0]
	g5.money = 1000000.0
	g5.crisis.fire_with(w6, "none")
	check(g5.crisis.suits.size() == 1, "без причины — иск в суд")
	var lab := g5.inspect.queue.any(func(q: Dictionary) -> bool: return str(q["type"]) == "labor")
	check(lab, "и жалоба в трудовую инспекцию")
	var mny := g5.money
	g5.minute += 8.0 * 1440.0
	g5.crisis._suits_daily()
	check(g5.money < mny and g5.crisis.suits.is_empty(), "суд взыскал: %s" % Defs.money_str(mny - g5.money))

	print("— насосная и электрокотёл")
	var g6 := _game(206)
	var pumps := g6.things_of("pump")
	check(pumps.size() == 1, "в гараже одна насосная")
	var heaters := g6.things_of("heater")
	check(heaters.size() == 1, "и электрокотёл рядом с ней")
	var free_c := Vector2i(-1, -1)
	for y in range(g6.world.plot.position.y + 2, g6.world.plot.end.y - 2):
		for x in range(g6.world.plot.position.x + 2, g6.world.plot.end.x - 2):
			if g6.can_place("pump_house", Vector2i(x, y)).contains("уже есть"):
				free_c = Vector2i(x, y)
				break
		if free_c.x >= 0:
			break
	check(free_c.x >= 0, "вторую насосную поставить нельзя: «%s»" % (g6.can_place("pump_house", free_c) if free_c.x >= 0 else ""))
	var far := Vector2i(-1, -1)
	for y2 in range(g6.world.plot.position.y + 2, g6.world.plot.end.y - 2):
		for x2 in range(g6.world.plot.position.x + 2, g6.world.plot.end.x - 2):
			var er2 := g6.can_place("water_heater", Vector2i(x2, y2))
			if er2.contains("насосн"):
				far = Vector2i(x2, y2)
				break
		if far.x >= 0:
			break
	check(far.x >= 0, "электрокотёл вдали от насосной — нельзя")
	g6.rooms.update()
	g6.power.tick(0.0)
	g6.rooms.update()
	check(g6.eng.heater_problem(heaters[0]) == "", "электрокотёл работает: «%s»" % g6.eng.heater_problem(heaters[0]))
	var rad: Thing = null
	for t in g6.things_of("radiator"):
		rad = t
		break
	if rad == null:
		var c6 := Vector2i(-1, -1)
		for r in g6.rooms.list:
			for cc in r.cells:
				if g6.can_place("radiator", cc) == "":
					c6 = cc
					break
			if c6.x >= 0:
				break
		rad = g6.place_thing("radiator", c6, true, false)
	check(rad != null and g6.eng.radiator_on(rad), "батарея горячая при работающем котле")
	heaters[0].enabled = false
	g6.thing_rev += 1
	g6.minute += 10.0
	check(not g6.eng.radiator_on(rad), "котёл выключен — батарея холодная")
	heaters[0].enabled = true
	g6.thing_rev += 1
	# без лимита приборов
	g6.water.bonus = 0
	g6.water._sig = ""
	g6.water.update()
	check(g6.water.low.is_empty(), "насосной хватает на все приборы")
	# миграция v12: старое сохранение без котла
	g6.remove_thing(heaters[0], 0.0)
	check(g6.things_of("heater", false).is_empty(), "котёл убран для миграции")
	var d6 := g6.to_dict()
	d6["version"] = 11
	var g6b := Sim.from_dict(d6)
	check(g6b.things_of("heater").size() == 1, "миграция v12 поставила электрокотёл")

	print("— как исправить нарушения")
	var g7 := _game(207)
	var fx := 0
	var miss: Array[String] = []
	for k in (Defs.inspections.get("texts", {}) as Dictionary).keys():
		if Inspections.fix_text(str(k)) != "":
			fx += 1
		else:
			miss.append(str(k))
	check(miss.is_empty(), "у всех нарушений есть «как исправить» (%d), без: %s" % [fx, ", ".join(miss)])
	var any_v := false
	for t7 in ["fire", "labor", "sanitary", "tech", "ecology"]:
		for v7: Dictionary in g7.inspect.violations(t7):
			any_v = true
			check(str(v7.get("fix", "")) != "", "нарушение «%s» с пояснением" % str(v7["text"]))
			break
		if any_v:
			break

	print("— кликабельные уведомления")
	check(Links.target("Люди жалуются: зарплату задерживают уже 3 дн.") == "finance:summary", "зарплата → финансы")
	check(Links.target("Снабжение: на металл нет денег") == "prod:supply", "снабжение → металл")
	check(Links.target("Заказ сорван: болт ×10") == "orders:active", "заказ → заказы")
	check(Links.target("Что-то совсем другое") == "events:log", "прочее → журнал")
	check(Links.target("Что-то совсем другое", "") == "", "без запасного варианта — никуда")

	print("— автосохранения у каждого завода")
	var ga := _game(208)
	var gb := _game(209)
	var ua := Company.uid_of(ga)
	var ub := Company.uid_of(gb)
	check(ua != "" and ub != "" and ua != ub, "у заводов разные номера: %s / %s" % [ua, ub])
	var gad := Sim.from_dict(ga.to_dict())
	check(Company.uid_of(gad) == ua, "номер завода сохраняется")
	Company.set_data(ga, "Новое имя", Company.emblem_of(ga))
	check(Company.uid_of(ga) == ua, "переименование номер не меняет")

	print("")
	if fails.is_empty():
		print("РЕЗУЛЬТАТ: OK")
	else:
		print("РЕЗУЛЬТАТ: ОШИБКИ (%d)" % fails.size())
		for f in fails:
			print("  - " + f)
	quit(0 if fails.is_empty() else 1)
