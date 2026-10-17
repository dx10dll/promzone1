extends SceneTree
## Тест версии 1.0: баланс денег (гараж окупается), отдел сбыта (автоприём, отказы, ассортимент,
## портфель заявок, контракты, товарный кредит), загрузка по узкому месту, массовые действия
## с персоналом, достижения, тексты без «(а)».
## godot --headless --path . -s res://tests/stage10_test.gd

const S := preload("res://tests/setups.gd")

var fails: Array[String] = []


func check(cond: bool, what: String) -> void:
	print(("  ✓ " if cond else "  ✗ ") + what)
	if not cond:
		fails.append(what)


func _monday(sim: Sim) -> void:
	while sim.weekday() != 0:
		sim.minute += 1440.0
	sim.minute = floor(sim.minute / 1440.0) * 1440.0 + 360.0


func _init() -> void:
	Defs.load_all()
	print("— цены и найм")
	var g := Scenario.new_game("garage", "mech", "calm", 3)
	g.story.enabled = false
	g.progress.tutorial = -1
	check(g.ad_price() <= 3000.0 and g.ad_price("turner") <= 4000.0, "объявление: %s, по профессии %s" % [Defs.money_str(g.ad_price()), Defs.money_str(g.ad_price("turner"))])
	var pin_mid := (float(Defs.products["pin"]["price"][0]) + float(Defs.products["pin"]["price"][1])) * 0.5
	check(pin_mid / 20.0 >= 70.0, "палец: %.0f ₽ за минуту станка" % (pin_mid / 20.0))
	var wsum := 0
	for w in g.workers:
		wsum += w.wage
		check(w.wage >= int(Defs.inspections.get("min_wage_shift", 1900)), "ставка %s не ниже МРОТ-смены" % w.first)
	check(wsum < 9500, "фонд гаража за смену %d ₽" % wsum)

	print("— гараж окупается (заказы берёт сбыт сам)")
	while g.day() <= 22:
		g.tick(0.5)
	var nets: Array[float] = []
	for wk: Dictionary in g.office.weeks:
		var cats: Dictionary = wk["cats"]
		var t := 0.0
		for c in cats.keys():
			if c != "capex" and c != "finance":
				t += float(cats[c])
		nets.append(t)
	print("    недели (новые первыми): ", nets)
	# 1.21: недели «прыгают» из-за закупок металла партиями — смотрим три последние недели вместе
	check(nets.size() >= 3 and (nets[1] + nets[2] > 0.0 or nets[0] + nets[1] + nets[2] > -25000.0), "гараж окупается: две полные недели в плюсе или три недели около нуля")
	check(g.orders.by_status(["failed"]).size() <= 1, "сбыт не набирает лишнего: сорвано %d" % g.orders.by_status(["failed"]).size())
	var took := g.sales.log.filter(func(e: Dictionary) -> bool: return bool(e["ok"])).size()
	var lost := g.sales.log.filter(func(e: Dictionary) -> bool: return not bool(e["ok"]))
	check(took >= 3 and int(g.stats["orders_done"]) >= 5, "сбыт сам взял %d заказов, выполнено %d" % [took, int(g.stats["orders_done"])])
	check(lost.any(func(e: Dictionary) -> bool: return str(e["why"]).begins_with("нет оборудования")), "отказы «нет оборудования» видны в упущенной выгоде")
	var sm := g.sales.summary(14)
	check(float(sm["lost_sum"]) > 0.0 and str(sm["top"]) != "" and g.sales.advice(str(sm["top"])) != "", "главная причина потерь: %s — %s" % [Defs.process_name(str(sm["top"])), g.sales.advice(str(sm["top"]))])

	print("— сбыт: ассортимент, портфель заявок, товарный кредит")
	var a := Scenario.new_game("garage", "mech", "calm", 8)
	a.story.enabled = false
	a.sales.off["pin"] = true
	var o1 := a.orders.make_offer("pin")
	check(not a.sales.inquiry(o1) and str(a.sales.log.back()["why"]) == "снято с ассортимента", "снятое с ассортимента не берут")
	a.sales.off.clear()
	var big := a.orders.make_offer("shaft")
	big["qty"] = 400
	a.sales.inquiry(big)
	check(a.sales.queue.has(big), "заявка, на которую нет мощности, ждёт в портфеле")
	a.minute += 2.0 * 1440.0
	a.sales.tick(60.0)
	check(not a.sales.queue.has(big) and str(a.sales.log.back()["why"]).begins_with("не успеваем"), "через полтора дня заказчик ушёл — записано в отказы")
	a.money = 0.0
	var debt0 := a.office.debt()
	check(a.order_material("bar45", 20) == "" and a.office.debt() > debt0, "нет денег — металл в долг с отсрочкой")
	a.money = -500000.0
	check(a.order_material("bar45", 2000) != "", "лимит товарного кредита не бесконечный")
	a.dispose()

	print("— контракты")
	var c := Scenario.new_game("garage", "mech", "calm", 12)
	c.story.enabled = false
	c.sales.enabled = false
	var ct := c.sales._new_contract()
	check(not ct.is_empty() and int(ct["per_week"]) >= 2 and float(ct["prem"]) >= 0.1, "предложение контракта: %s × %d/нед, %d нед." % [str(ct.get("product", "")), int(ct.get("per_week", 0)), int(ct.get("weeks", 0))])
	c.sales.contracts.append(ct)
	ct["start"] = c.day()
	check(c.sales.sign(int(ct["id"])) == "", "контракт подписан")
	_monday(c)
	c.sales._contract_orders()
	var co := c.orders.get_order(int(ct["order"]))
	check(not co.is_empty() and str(co["status"]) == "active" and str(co["kind"]) == "contract", "в понедельник — недельная партия в работе")
	var m1 := c.money
	c.sales.on_order_closed(co, false)
	check(c.money < m1 and int(ct["fails"]) == 1 and str(ct["status"]) == "active", "сорвали партию — штраф")
	c.sales.on_order_closed(co, false)
	check(str(ct["status"]) == "broken", "два срыва — контракт расторгнут")
	var ct2 := c.sales._new_contract()
	ct2["weeks"] = 1
	c.sales.contracts.append(ct2)
	c.sales.sign(int(ct2["id"]))
	var m2 := c.money
	c.sales.on_order_closed({"contract": int(ct2["id"]), "price": ct2["price"], "qty": ct2["per_week"]}, true)
	check(str(ct2["status"]) == "done" and c.money > m2, "контракт выполнен — премия")
	var d3 := Sim.from_dict(JSON.parse_string(JSON.stringify(c.to_dict())))
	check(d3.sales.contracts.size() == c.sales.contracts.size(), "контракты сохраняются")
	d3.dispose()
	c.story._ev_hot_order()
	var hl: Dictionary = c.story.letters.back()
	var hid := int(hl["data"]["order"])
	c.story.resolve(int(hl["id"]), 0)
	check(str(c.orders.get_order(hid).get("status", "")) == "active", "«горящий» заказ: директор решил взять")
	c.dispose()

	print("— поток заказов и узкое место")
	var sh := Scenario.new_game("garage", "mech", "calm", 5)
	sh.story.enabled = false
	S.big_shop(sh, true)
	var ops := sh.office.load_ops()
	var n_big := 0
	var n_small := 0
	var gs := Scenario.new_game("garage", "mech", "calm", 5)
	for k in 6:
		_monday(sh)
		var l0 := sh.sales.log.size() + sh.sales.queue.size()
		sh.orders.morning()
		n_big += sh.sales.log.size() + sh.sales.queue.size() - l0
		sh.minute += 1440.0
		_monday(gs)
		var l1 := gs.sales.log.size() + gs.sales.queue.size()
		gs.orders.morning()
		n_small += gs.sales.log.size() + gs.sales.queue.size() - l1
		gs.minute += 1440.0
	gs.dispose()
	check(ops >= 6.0 and n_big > n_small, "у большого цеха заявок больше: %d против %d у гаража" % [n_big, n_small])
	S.complex_orders(sh, 10, {"housing": 12})
	var li := sh.office.load_info()
	check(str(li[1]) == "milling" or str(li[1]) == "turning" or str(li[1]) == "drilling", "узкое место найдено: %s, %.1f дн." % [str(li[1]), float(li[0])])
	check(sh.office.load_days("housing", 30) > float(li[0]), "новый заказ увеличивает загрузку")

	print("— массовые действия")
	var m0 := sh.money
	check(sh.bonus_all() == "" and is_equal_approx(m0 - sh.money, Defs.b("bonus_amount") * sh.workers.size()), "премия всем")
	var w0 := sh.workers[0]
	var wage0 := w0.wage
	sh.raise_all(0.05)
	check(w0.wage > wage0, "ставки всем +5%")
	w0.wage = 1500
	check(sh.wages_to_market() >= 1 and w0.wage >= int(Mood.market_wage(w0) * 0.96), "ставки подтянуты до рынка")
	check(not sh.events.any(func(e: Dictionary) -> bool: return str(e["text"]).contains("(а)")), "в уведомлениях нет «(а)»")
	w0.female = true
	check(Nicks.gendered("%s получил{|а} премию", true) == "%s получила премию", "женский род подставляется")

	print("— достижения")
	Achievements.load_all()
	var saved := Achievements.got.duplicate()
	Achievements.got.clear()
	sh.stats["orders_done"] = 1
	sh.money = 1200000.0
	var got := Achievements.check(sh)
	var ids: Array = got.map(func(a: Dictionary) -> String: return str(a["id"]))
	check(ids.has("first_order") and ids.has("money_1m") and ids.has("stage_3"), "получены: %s" % str(ids))
	check(Achievements.check(sh).is_empty(), "повторно не выдаются")
	var sb := Scenario.new_game("sandbox", "mech", "calm", 5, {"money": 50000000})
	Achievements.got.clear()
	check(Achievements.check(sb).is_empty(), "в песочнице не засчитываются")
	Achievements.got = saved
	Achievements.save()
	sb.dispose()
	sh.dispose()
	g.dispose()
	print("РЕЗУЛЬТАТ: ", "OK" if fails.is_empty() else "ОШИБКИ: " + ", ".join(fails))
	quit(0 if fails.is_empty() else 1)
