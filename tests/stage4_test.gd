extends SceneTree
## Тест этапа 4: ИТР-кабинеты, мастер, начальник цеха, бухгалтерия и налоги, снабжение,
## ПДО (автоприём заказов), кадры, техотдел и исследования, кредит, переналадка.
## godot --headless --path . -s res://tests/stage4_test.gd -- [дней]

const S := preload("res://tests/setups.gd")

var fails: Array[String] = []


func check(cond: bool, what: String) -> void:
	print(("  ✓ " if cond else "  ✗ ") + what)
	if not cond:
		fails.append(what)


func room_box(sim: Sim, r: Rect2i, floor_id: int, door: Vector2i) -> void:
	var w := sim.world
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			var c := Vector2i(x, y)
			var i := w.idx(c)
			w.flr[i] = floor_id
			var edge := x == r.position.x or x == r.end.x - 1 or y == r.position.y or y == r.end.y - 1
			if edge and w.wall[i] == World.W_NONE:
				w.wall[i] = World.W_BRICK
	w.wall[w.idx(door)] = World.W_DOOR
	w.refresh_all()


func _init() -> void:
	var days := 10
	var a := OS.get_cmdline_user_args()
	if a.size() > 0:
		days = int(a[0])
	var sim := Scenario.new_garage(555)
	sim.story.enabled = false   # тест механик производства: без случайных событий
	sim.auto_supply = true
	var notes := {}
	var auto_acc := [0]
	sim.notified.connect(func(t: String, _l: int, _c: Vector2i) -> void:
		if t.begins_with("ПДО само приняло"):
			auto_acc[0] += 1
		var k := t.substr(0, 36)
		if not notes.has(k):
			notes[k] = true
			print("    [%s %s] %s" % [sim.date_str(), sim.time_str(), t]))
	S.big_shop(sim)
	S.offices(sim)
	var ok_rooms := true
	for t in ["office", "tech_office", "foreman_office"]:
		if sim.rooms.of_type(t).is_empty():
			ok_rooms = false
			print("    не оборудовано: ", t)
	check(ok_rooms, "контора, техотдел и конторка мастера оборудованы")
	var itr := {}
	for p in [["foreman", "manage", 6], ["chief", "manage", 7], ["accountant", "office", 5], ["buyer", "office", 5],
			["dispatcher", "office", 5], ["hr", "office", 5], ["technologist", "engineering", 6]]:
		itr[p[0]] = S.hire(sim, str(p[0]), str(p[1]), int(p[2]))
	var money0 := sim.money
	sim.progress.stage = maxi(sim.progress.stage, 2)
	var err := sim.office.take_loan(800000.0, 26)
	check(err == "" and sim.money > money0, "кредит выдан " + err)
	sim.sales.risk = 2
	S.complex_orders(sim, days, {"bracket": 8, "housing": 3, "shaft": 6})
	var acts := {}
	var max_k := 1.0
	var tax_seen := false
	while sim.day() <= days:
		sim.tick(0.5)
		if sim.day() == 2 and sim.office.supplier == "base" and sim.office.active("supply"):
			sim.office.supplier = "ural"
		for w: Worker in itr.values():
			if w.present:
				acts[w.activity] = true
		if sim.is_work_time():
			max_k = maxf(max_k, sim.office.speed_k(sim.workers[0]))
	for e: Dictionary in sim.ledger:
		if str(e["text"]).begins_with("Налог УСН"):
			tax_seen = true
	print("  занятия ИТР: ", acts.keys())
	for w: Worker in itr.values():
		print("    %s %s: стол %d, кабинет ×%.1f, %s" % [w.prof_name(), w.first, w.desk_id, sim.office.desk_k(w), w.activity])
	var all_desks := true
	for w: Worker in itr.values():
		if sim.office.desk_k(w) <= 0.0:
			all_desks = false
	check(all_desks, "у всех ИТР есть рабочие места в кабинетах")
	check(acts.has("Ведёт учёт, считает налоги") and acts.has("Разрабатывает техпроцесс"), "ИТР работают за столами")
	check(acts.has("Обходит участок, раздаёт задания"), "мастер обходит участок")
	check(max_k > 1.05, "мастер и начальник цеха ускоряют работу (×%.2f)" % max_k)
	for k in ["accounting", "supply", "pdo", "hr", "tech", "foreman", "chief"]:
		check(sim.office.active(k), "отдел работает: " + str(Defs.departments[k]["name"]))
	check(not sim.office.research_done.is_empty(), "техотдел закончил разработку: " + str(sim.office.research_done))
	check(tax_seen, "в пятницу заплачен налог")
	check(sim.office.loans.size() == 1 and int(sim.office.loans[0]["left"]) < 26, "платёж по кредиту в понедельник")
	sim.market.metal = 1.0   # индекс цены металла (1.8) — здесь проверяем только поставщика
	check(sim.material_price("bar45") < 260.0, "оптовый поставщик дешевле (%d ₽)" % int(sim.material_price("bar45")))
	sim.refresh_candidates()
	check(sim.candidates.size() == 6, "кадровик: 6 кандидатов")
	var took := sim.sales.log.filter(func(e: Dictionary) -> bool: return bool(e["ok"])).size()
	sim.dev.done.append("plan3")   # с 1.11 «впритык» — ступень развития, её держит ПДО
	check(took > 0 and sim.sales.risk_k() > 0.85, "сбыт сам взял заказы (%d), с ПДО и ступенью «Впритык» можно брать «впритык»" % took)
	var setups := 0
	for m in sim.things_of("machine"):
		if m.setup_key != "":
			setups += 1
	check(setups > 0, "станки переналаживались под операции (%d)" % setups)
	check(not sim.office.weeks.is_empty(), "отчёт по неделям ведётся: " + str(sim.office.weeks[0]["cats"]))
	print("  заказов выполнено: %d, сорвано %d, деньги %s, долг %s" % [int(sim.stats["orders_done"]), int(sim.stats["orders_failed"]), Defs.money_str(sim.money), Defs.money_str(sim.office.debt())])
	var d := sim.to_dict()
	var s2 := Sim.from_dict(JSON.parse_string(JSON.stringify(d)))
	check(s2.office.research_done.size() == sim.office.research_done.size() and s2.office.loans.size() == 1, "сохранение и загрузка управления")
	sim.dispose()
	s2.dispose()
	print("РЕЗУЛЬТАТ: ", "OK" if fails.is_empty() else "ПРОВАЛ: " + "; ".join(fails))
	quit(0 if fails.is_empty() else 1)
