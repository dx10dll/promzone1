extends SceneTree
## Тест версии 1.8 «Рынок»: конкуренты и доля рынка, ценовая политика, индекс металла,
## статистика для графиков, события конкурентов, ISO 9001, лизинг, страхование, главный инженер, сохранение.
## godot --headless --path . -s res://tests/stage18_test.gd

const S := preload("res://tests/setups.gd")

var fails: Array[String] = []


func check(cond: bool, what: String) -> void:
	print(("  ✓ " if cond else "  ✗ ") + what)
	if not cond:
		fails.append(what)


func _run(sim: Sim, minutes: float) -> void:
	var end := sim.minute + minutes
	while sim.minute < end:
		sim.tick(0.5)


func _init() -> void:
	Defs.load_all()
	var sim := Scenario.new_game("garage", "mech", "calm", 18)
	sim.story.enabled = false
	S.big_shop(sim)
	sim.office.all_depts = true   # с 1.10 политика цен — у сбыта, лизинг — у бухгалтерии
	var mk := sim.market

	print("— конкуренты и доля рынка")
	check(mk.alive_comps().size() == 4, "в районе четыре завода-конкурента")
	for c: Dictionary in mk.comps:
		check(not str(c["name"]).is_empty() and (c["spec"] as Array).size() > 0, "конкурент: %s (%s)" % [str(c["name"]), mk._spec_text(c)])
	mk._update_share()
	var total := mk.share
	for c2: Dictionary in mk.comps:
		total += float(c2["share"])
	check(absf(total - 1.0) < 0.001, "доли рынка в сумме дают 100%")
	check(mk.share > 0.02 and mk.share < 0.6, "наша доля %d%%" % int(mk.share * 100.0))
	var k0 := mk.inquiry_k()
	check(k0 > 0.7 and k0 < 1.4, "множитель заявок по умолчанию ×%.2f" % k0)

	print("— ценовая политика")
	mk.policy = "dump"
	check(mk.inquiry_k() > k0 and mk.price_k() < 1.0, "демпинг: заявок больше (×%.2f), цены ниже" % mk.inquiry_k())
	var sd := 0.0
	for i in 30:
		sd += float(sim.orders.make_offer("bushing")["price"])
	mk.policy = "premium"
	check(mk.inquiry_k() < k0 and mk.price_k() > 1.0, "премиум: заявок меньше (×%.2f), цены выше" % mk.inquiry_k())
	var sp := 0.0
	for i2 in 30:
		sp += float(sim.orders.make_offer("bushing")["price"])
	check(sp > sd * 1.12, "средняя цена заявки при премиуме выше, чем при демпинге (%d > %d)" % [int(sp / 30.0), int(sd / 30.0)])
	mk.policy = "market"
	for i in 10:
		mk.on_shipped(3)
	check(mk.ontime() < 0.6 and mk.inquiry_k() < k0, "срывы сроков снижают конкурентоспособность (вовремя %d%%)" % int(mk.ontime() * 100.0))
	for j in 20:
		mk.on_shipped(0)
	check(mk.ontime() >= 0.99, "сдаём вовремя — доверие возвращается")

	print("— металл")
	var p0 := sim.material_price("bar45")
	mk.metal = 1.2
	var p1 := sim.material_price("bar45")
	check(p1 > p0 * 1.15, "индекс металла 1.20 поднимает цену прутка: %d → %d ₽" % [int(p0), int(p1)])
	mk.metal = 1.0
	for d in 30:
		mk._tick_metal()
	check(mk.metal >= 0.75 and mk.metal <= 1.4, "индекс металла гуляет в пределах: %.2f" % mk.metal)

	print("— статистика для графиков")
	var h0 := mk.hist.size()
	_run(sim, 3.0 * 1440.0)
	check(mk.hist.size() >= h0 + 3, "каждое утро записывается день (%d записей)" % mk.hist.size())
	var e: Dictionary = mk.hist[mk.hist.size() - 1]
	check(e.has("money") and e.has("rev") and e.has("share") and e.has("cs") and e.has("metal") and e.has("mood"), "в записи: деньги, выручка, доля, конкуренты, металл, настроение")

	print("— события конкурентов")
	var war_c: Dictionary = mk.alive_comps()[0]
	mk._start_war(war_c)
	check(mk.war_active() and float(war_c["price"]) < float(war_c["base_price"]), "война цен: конкурент снизил цены")
	var kw := mk.inquiry_k()
	mk.policy = "market"
	check(kw < mk.competitiveness() + 0.001, "во время войны цен заявок меньше")
	var wl := sim.story.get_letter_by_ev("price_war")
	check(not wl.is_empty(), "письмо «Война цен»")
	sim.story.resolve(int(wl["id"]), 0)
	check(mk.policy == "dump", "ответили демпингом")
	mk.policy = "market"
	war_c["war_until"] = sim.day() - 1
	mk._expire_wars()
	check(not mk.war_active() and absf(float(war_c["price"]) - float(war_c["base_price"])) < 0.001, "война цен закончилась — цены вернулись")
	var weak: Dictionary = mk.alive_comps()[2]
	mk._bankrupt(weak)
	check(not bool(weak["alive"]) and mk.alive_comps().size() == 3, "банкротство конкурента")
	var al := sim.story.get_letter_by_ev("auction")
	if not al.is_empty():
		var def := str(al["data"]["def"])
		sim.story.resolve(int(al["id"]), 0)
		check(sim.thing_cost(def) <= float(Defs.objects[def]["cost"]) * 0.45, "станок с торгов — 40%% цены: %s" % Defs.money_str(sim.thing_cost(def)))
	var sh_before := mk.share
	mk._update_share()
	check(mk.share > sh_before - 0.0001, "доля рынка после банкротства выросла: %d%%" % int(mk.share * 100.0))
	var pw: Worker = null
	for w in sim.workers:
		if w.has_grade() and (pw == null or w.grade() > pw.grade()):
			pw = w
	pw.skills[pw.main_skill()] = 9
	pw.grade_n = pw.pot_grade()   # 1.15: разряд подтверждён экзаменом
	var wage0 := pw.wage
	mk._poach()
	var pl := sim.story.get_letter_by_ev("poach")
	check(not pl.is_empty(), "конкурент переманивает опытного рабочего")
	sim.story.resolve(int(pl["id"]), 0)
	check(pw.wage > wage0 and sim.get_worker(pw.id) != null, "подняли ставку — остался")

	print("— ISO 9001")
	check(mk.iso_reqs().size() == 6, "шесть требований стандарта")
	sim.progress.stage = 2
	sim.money += 1000000.0
	var err := mk.iso_apply()
	check(err == "" and str(mk.iso["status"]) == "audit", "аудит заказан")
	check(mk.iso_apply() != "", "второй раз не заказать")
	# требования не выполнены → несоответствия
	mk.iso["audit_at"] = sim.day()
	mk._tick_iso()
	check(str(mk.iso["status"]) == "remarks", "без ОТК и техотдела — несоответствия, сертификата нет")
	check(not mk.iso_ok(), "сертификат не выдан")
	# всё выполнено — сертификат
	mk.iso = {"status": "ok", "since": sim.day(), "until": sim.day() + Market.ISO_DAYS, "reclam": 0}
	var kiso := mk.inquiry_k()
	mk.iso = {"status": "none"}
	check(kiso > mk.inquiry_k(), "с ISO заявок больше (×%.2f против ×%.2f)" % [kiso, mk.inquiry_k()])
	mk.iso = {"status": "ok", "since": sim.day(), "until": sim.day() + Market.ISO_DAYS, "reclam": 0}
	mk.on_reclamation()
	check(mk.iso_ok(), "одна рекламация — предупреждение")
	mk.on_reclamation()
	check(str(mk.iso["status"]) == "suspended", "две рекламации — сертификат приостановлен")

	print("— лизинг")
	mk.leasing_on = true
	var cost := sim.thing_cost("mill")
	check(mk.can_lease("mill", cost), "фрезерный станок можно взять в лизинг")
	var m0 := sim.money
	var t := sim.place_thing("mill", Vector2i(30, 8), false)
	var paid := m0 - sim.money
	check(absf(paid - cost * Market.LEASE_ADV) < 1.0, "сразу — аванс 20%%: %s из %s" % [Defs.money_str(paid), Defs.money_str(cost)])
	check(mk.leases.size() == 1 and int(mk.leases[0]["left"]) == Market.LEASE_WEEKS, "договор лизинга на %d недель" % Market.LEASE_WEEKS)
	check(absf(float(mk.leases[0]["total"]) - cost * 0.8 * 1.18) < 2.0, "удорожание 18%")
	var m1 := sim.money
	mk._pay_leases()
	check(m1 - sim.money >= float(mk.leases[0]["payment"]) - 1.0 and int(mk.leases[0]["left"]) == Market.LEASE_WEEKS - 1, "платёж по понедельникам")
	check(Office.cat_of("Лизинг: платёж за станок") == "finance", "лизинг в отчёте — «Кредиты и лизинг»")
	sim.cancel_thing(t)
	check(mk.leases.is_empty(), "отменили заказ до отправки — лизинг расторгнут")
	mk.leasing_on = false
	sim.story.remove_mod("voucher:lathe")   # купон с торгов банкрота мог выпасть на токарный
	var m2 := sim.money
	sim.place_thing("lathe", Vector2i(30, 12), false)
	check(absf(m2 - sim.money - sim.thing_cost("lathe")) < 1.0 and mk.leases.is_empty(), "лизинг выключен — платим сразу всю цену (%d из %d, лизингов %d)" % [int(m2 - sim.money), int(sim.thing_cost("lathe")), mk.leases.size()])

	print("— страхование")
	check(mk.premium("property") >= 1500.0 and mk.premium("accident") >= 1000.0, "взносы: имущество %s, несчастный случай %s" % [Defs.money_str(mk.premium("property")), Defs.money_str(mk.premium("accident"))])
	check(mk.claim("property", 30000.0, "тест") == 0.0, "без полиса возмещения нет")
	var m3 := sim.money
	mk.toggle_insurance("property", true)
	check(sim.money < m3 and mk.insurance.has("property"), "полис оформлен, первый взнос списан")
	check(mk.claim("property", 30000.0, "тест") == 0.0, "полис действует со следующего дня")
	_run(sim, 1440.0)
	var m4 := sim.money
	var pay := mk.claim("property", 30000.0, "ремонт станка")
	check(absf(pay - 24000.0) < 1.0 and sim.money - m4 >= 23999.0, "возмещение 80%% ремонта: %s" % Defs.money_str(pay))
	check(Office.cat_of("Страховое возмещение: ремонт станка") == "insurance" and Office.cat_of("Страховое возмещение: штраф по контракту") == "insurance", "возмещения — статья «Страхование»")
	mk.toggle_insurance("liability", true)
	_run(sim, 1440.0)
	check(absf(mk.claim("liability", 10000.0, "неустойка") - 5000.0) < 1.0, "ответственность — половина неустойки")
	mk.toggle_insurance("liability", false)
	check(not mk.insurance.has("liability"), "полис можно расторгнуть")

	print("— главный инженер")
	for m in sim.things_of("machine"):
		m.broken = true
		break
	var adv := mk.advice()
	check(not adv.is_empty(), "советов: %d" % adv.size())
	check(adv.any(func(a: Dictionary) -> bool: return str(a["title"]).begins_with("Станков сломано")), "заметил сломанный станок")
	check(int(adv[0]["prio"]) >= int(adv[adv.size() - 1]["prio"]), "самые важные советы — первыми")
	mk.metal = 0.82
	check(mk.advice(99).any(func(a: Dictionary) -> bool: return str(a["title"]).begins_with("Металл подешевел")), "подсказал закупить дешёвый металл")
	for a2: Dictionary in adv:
		check(str(a2["open"]) in ["", "orders", "prod", "people", "finance", "office", "goals", "events"], "совет ведёт в окно «%s»" % str(a2["open"]))

	print("— вымышленные заказчики")
	for nm in Sales.BIG_CLIENTS:
		check(not (str(nm).contains("КАМАЗ") or str(nm).contains("Ростсельмаш") or str(nm).contains("Северсталь")), "крупный заказчик вымышленный: " + str(nm))

	print("— сохранение")
	mk.policy = "premium"
	mk.toggle_insurance("accident", true)
	mk.leasing_on = true
	var dd := Sim.from_dict(JSON.parse_string(JSON.stringify(sim.to_dict())))
	var dm := dd.market
	check(dm.policy == "premium" and dm.leasing_on, "политика и лизинг сохраняются")
	check(dm.comps.size() == mk.comps.size() and dm.alive_comps().size() == mk.alive_comps().size(), "конкуренты сохраняются")
	check(dm.hist.size() == mk.hist.size() and absf(dm.metal - mk.metal) < 0.0001, "статистика и индекс металла сохраняются")
	check(dm.insurance.has("accident") and str(dm.iso["status"]) == "suspended", "полисы и ISO сохраняются")
	dd.dispose()
	sim.dispose()
	print("РЕЗУЛЬТАТ: ", "OK" if fails.is_empty() else "ОШИБКИ: " + ", ".join(fails))
	quit(0 if fails.is_empty() else 1)
