extends SceneTree
## Тест версии 1.10 «Отделы»: четыре новых отдела и профессии, функции открываются людьми
## (лизинг и страховка — бухгалтер, ценовая политика и контракты — сбыт, обжалование и
## рекламации — юрист, ППР и советы — главный инженер, травмы и Н-1 — инженер по ОТ),
## доля зарплат в выручке и предупреждение бухгалтера, совет о простаивающих станочниках.
## godot --headless --path . -s res://tests/stage110_test.gd

const S := preload("res://tests/setups.gd")

var fails: Array[String] = []


func check(cond: bool, what: String) -> void:
	print(("  ✓ " if cond else "  ✗ ") + what)
	if not cond:
		fails.append(what)


func _init() -> void:
	Defs.load_all()
	var sim := Scenario.new_game("garage", "mech", "calm", 110)
	sim.story.enabled = false
	sim.progress.tutorial = -1

	print("— новые отделы и профессии")
	for d in ["sales", "safety", "engineer", "legal"]:
		var dd: Dictionary = Defs.departments.get(d, {})
		check(not dd.is_empty() and Defs.rooms.has(str(dd["room"])) and Worker.PROF_NAMES.has(str(dd["prof"])), "отдел «%s»: кабинет «%s», специалист «%s»" % [str(dd.get("name", d)), str(Defs.rooms.get(str(dd.get("room", "")), {}).get("name", "?")), str(Worker.PROF_NAMES.get(str(dd.get("prof", "")), "?"))])
		var room := str(dd["room"])
		check(Rooms.TYPES.has(room) and Rooms.OFFICE_TYPES.has(room), "кабинет «%s» можно назначить и посадить туда ИТР" % room)
		var w := People.make(sim.rng, str(dd["prof"]))
		check(w.is_itr() and w.dept() == d and w.wage >= 3400 and str(w.look.get("outfit", "")) == "suit", "%s: ИТР, ставка %d ₽, в костюме" % [w.prof_name(), w.wage])
	for oid in ["phone_stand", "safety_stand", "law_shelf"]:
		check(Defs.objects.has(oid) and ResourceLoader.exists("res://assets/objects/%s.svg" % oid), "новый объект: %s" % str(Defs.objects.get(oid, {}).get("name", oid)))

	print("— без бухгалтера")
	sim.progress.stage = 2
	sim.market.leasing_on = true
	check(not sim.office.active("accounting"), "бухгалтерии нет")
	check(not sim.market.can_lease("lathe", 160000.0), "лизинг недоступен")
	sim.market.toggle_insurance("property", true)
	check(not sim.market.insurance.has("property"), "страховку не оформить")
	sim.office.all_depts = true
	check(sim.market.can_lease("lathe", 160000.0), "с бухгалтером — лизинг есть")
	sim.market.toggle_insurance("property", true)
	check(sim.market.insurance.has("property"), "с бухгалтером — страховка оформлена")
	sim.office.all_depts = false

	print("— сбыт")
	sim.market.policy = "dump"
	check(str(sim.market.pol().get("name", "")) == str(Market.POLICIES["market"]["name"]), "без менеджера по сбыту цены «по рынку», демпинг не работает")
	var k0 := sim.market.inquiry_k()
	sim.office.all_depts = true
	check(str(sim.market.pol().get("name", "")) == str(Market.POLICIES["dump"]["name"]), "с менеджером — своя ценовая политика")
	check(sim.market.inquiry_k() > k0, "с менеджером заявок больше (×%.2f против ×%.2f)" % [sim.market.inquiry_k(), k0])
	sim.office.all_depts = false
	sim.market.policy = "market"
	sim.reputation = 60.0
	sim.sales.next_contract = 0.0
	var n0 := sim.sales.contracts.size()
	while not sim.is_workday():
		sim.tick(1.0)
	sim.sales._contract_offers()
	check(sim.sales.contracts.size() == n0, "без отдела сбыта крупные заказчики контракт не предлагают")
	sim.office.all_depts = true
	sim.sales.next_contract = 0.0
	sim.sales._contract_offers()
	check(sim.sales.contracts.size() >= n0, "с отделом сбыта — предлагают (или ищут подходящее изделие)")
	sim.office.all_depts = false

	print("— юрист")
	var ins := sim.inspect
	sim.progress.stage = 4
	ins._act("labor", [{"key": "no_aid", "text": "Нет аптечки", "fine": 10000.0, "cell": [-1, -1]}], [], "")
	var l := sim.story.get_letter_by_ev("inspection_act")
	check((l["choices"] as Array).size() == 1 and str(l["text"]).contains("юрист"), "без юриста штраф не обжаловать")
	sim.story.resolve(int(l["id"]), 0)
	sim.office.all_depts = true
	ins._act("labor", [{"key": "no_ppe", "text": "Нет СИЗ", "fine": 15000.0, "cell": [-1, -1]}], [], "")
	var l2 := sim.story.get_letter_by_ev("inspection_act")
	check((l2["choices"] as Array).size() == 2 and ins.appeal_chance() >= 0.6, "с юристом — обжалование, шанс %d%%" % int(ins.appeal_chance() * 100.0))
	sim.story.resolve(int(l2["id"]), 0)
	sim.office.all_depts = false

	print("— главный инженер и охрана труда")
	sim.ppr = false
	var s0 := sim.service_at()
	sim.office.all_depts = true
	check(sim.service_at() > s0, "главный инженер ведёт ППР сам (обслуживание с %.0f%% вместо %.0f%%)" % [sim.service_at(), s0])
	sim.office.all_depts = false
	var w0: Worker = sim.workers[0]
	sim.story.enabled = true
	var i0 := sim.story.injury_chance(w0, null)
	sim.office.all_depts = true
	var i1 := sim.story.injury_chance(w0, null)
	sim.office.all_depts = false
	sim.story.enabled = false
	check(i1 < i0 * 0.9, "с инженером по ОТ травм меньше (%.5f → %.5f)" % [i0, i1])

	print("— зарплаты и выручка")
	sim.office.weeks = [{"week": 5, "cats": {"sales": 100000.0, "wages": -80000.0}}, {"week": 4, "cats": {"sales": 120000.0, "wages": -85000.0}}, {"week": 3, "cats": {"sales": 90000.0, "wages": -85000.0}}]
	var sh := sim.office.payroll_share(4)
	check(absf(sh - 250000.0 / 310000.0) < 0.01, "доля зарплат в выручке: %d%%" % int(sh * 100.0))
	var ev0 := sim.events.size()
	sim.office._payroll_check()
	check(sim.events.size() == ev0, "без бухгалтера никто не предупреждает")
	sim.office.all_depts = true
	sim.office._payroll_check()
	check(sim.events.size() > ev0 and str(sim.events[0]["text"]).contains("Бухгалтер"), "бухгалтер предупреждает: зарплаты съедают выручку")
	sim.office.all_depts = false

	print("— совет о простое")
	var sim2 := Scenario.new_game("garage", "mech", "calm", 111)
	sim2.story.enabled = false
	S.big_shop(sim2)
	var o := sim2.orders.make_offer("pin")
	sim2.orders.list.append(o)
	sim2.orders.accept(int(o["id"]), false)
	var adv: Array = sim2.market.advice(99)
	var idle := adv.filter(func(a: Dictionary) -> bool: return str(a["title"]).begins_with("Без работы"))
	check(not idle.is_empty() and str(idle[0]["title"]).contains("сварщик"), "главный инженер замечает простой: %s" % (str(idle[0]["title"]) if not idle.is_empty() else "—"))

	print("— отдел заработал по-настоящему")
	var sim3 := Scenario.new_game("garage", "mech", "calm", 112)
	sim3.story.enabled = false
	S.offices(sim3)
	var acc := S.hire(sim3, "accountant", "office", 5)
	for i in 40:
		sim3.tick(0.5)
	var desk := sim3.office.desk_for(acc)
	if desk:
		acc.desk_id = desk.id
	check(sim3.office.active("accounting"), "бухгалтер за столом в конторе — бухгалтерия работает (%d%%)" % int(sim3.office.eff("accounting") * 100.0))
	check(not sim3.office.active("sales"), "отдел сбыта без человека не работает")

	print("РЕЗУЛЬТАТ: " + ("OK" if fails.is_empty() else "ОШИБКИ: " + ", ".join(fails)))
	quit(0 if fails.is_empty() else 1)
