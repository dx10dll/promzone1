extends SceneTree
## Тест этапа 6: все сценарии и профили заводов строятся и играются, этапы роста и открытие
## объектов, рейтинг в звёздах, цели сценариев, ООО, экспорт и госзаказ, сохранения 0.5.
## godot --headless --path . -s res://tests/stage6_test.gd

var fails: Array[String] = []


func check(cond: bool, what: String) -> void:
	print(("  ✓ " if cond else "  ✗ ") + what)
	if not cond:
		fails.append(what)


func run(sim: Sim, minutes: float) -> void:
	var t := 0.0
	while t < minutes:
		sim.tick(0.5)
		t += 0.5


func accept_some(sim: Sim, n: int) -> void:
	for o: Dictionary in sim.orders.list:
		if n <= 0:
			return
		if str(o["status"]) == "offer" and sim.prod.can_make(str(o["product"])):
			if sim.orders.accept(int(o["id"]), true) == "":
				n -= 1


func _init() -> void:
	print("— сценарии и профили")
	var combos := [["garage", "mech"], ["garage", "agri"], ["field", "steel"], ["field", "pumps"], ["field", "mech"], ["sandbox", "pumps"], ["sandbox", "secret"]]
	for cb in combos:
		var sim := Scenario.new_game(str(cb[0]), str(cb[1]), "market", 1000 + combos.find(cb))
		var procs := Scenario.profile_processes(sim)
		run(sim, 1440.0)
		accept_some(sim, 2)
		run(sim, 1440.0 * 2)
		var present := 0
		for w in sim.workers:
			if w.days_worked > 0:
				present += 1
		var machines := sim.things_of("machine").size()
		print("    %s/%s: людей %d (выходили %d), станков %d, процессы %s, этап «%s», %s, деньги %s, заказов в работе %d, сделано %d" % [cb[0], cb[1], sim.workers.size(), present, machines, procs, sim.progress.stage_name(), sim.progress.stars_text(), Defs.money_str(sim.money), sim.orders.active_count(), int(sim.stats.get("made", 0))])
		check(present == sim.workers.size() or present >= sim.workers.size() - 2, "%s/%s: люди ходят на работу" % [cb[0], cb[1]])
		# предложения — только изделия профиля
		var bad := 0
		for o: Dictionary in sim.orders.list:
			if not sim.progress.products().has(str(o["product"])):
				bad += 1
		check(bad == 0, "%s/%s: заказы только по профилю" % [cb[0], cb[1]])
		var builders := sim.workers.filter(func(x: Worker) -> bool: return x.prof == "builder").size()
		match str(cb[0]):
			"field":
				check(sim.office.loans.is_empty() and sim.progress.ooo and not sim.grants.offers().is_empty(), "чистое поле: без кредита, ООО, доступны гранты")
				check(builders == sim.workers.size() and builders >= 3, "чистое поле: только строители (%d из %d)" % [builders, sim.workers.size()])
			"sandbox":
				var walls := 0
				for i in sim.world.w * sim.world.h:
					if WallKinds.is_room_wall(sim.world.wall[i]):
						walls += 1
				check(walls <= 20, "песочница: пустой участок, только техпомещение у ворот (стен %d)" % walls)   # 1.29
				check(builders == sim.workers.size(), "песочница: бригада строителей")
		var d := sim.to_dict()
		var s2 := Sim.from_dict(JSON.parse_string(JSON.stringify(d)))
		check(s2.world.w == sim.world.w and s2.world.plot == sim.world.plot and s2.progress.profile == sim.progress.profile, "%s/%s: сохранение и загрузка" % [cb[0], cb[1]])
		s2.dispose()
		sim.dispose()

	print("— этапы роста и открытие объектов")
	var g := Scenario.new_game("garage", "mech", "calm", 77, {"tutorial": true})
	check(g.progress.stage == 1 and g.progress.tutorial == 0, "гараж: этап 1, обучение включено")
	check(g.can_place("mill", Vector2i(36, 20)) != "", "фрезерный закрыт на этапе «Гараж»: " + g.can_place("mill", Vector2i(36, 20)))
	check(not g.progress.dept_open("accounting"), "бухгалтерия закрыта на этапе 1")
	g.stats["orders_done"] = 10
	g.stats["earned"] = 1000000.0
	g.progress._check_goals()
	check(g.progress.stage == 2 and g.progress.stage_up == 2, "переход на этап «Мастерская»")
	check(g.progress.locked_reason("mill") == "", "фрезерный открылся")
	check(g.progress.dept_open("accounting") and not g.progress.dept_open("pdo"), "бухгалтерия открылась, ПДО ещё нет")
	var e := g.progress.register_ooo()
	check(e == "" and g.progress.ooo, "ООО оформлено")
	var ag := Scenario.new_game("garage", "agri", "market", 5)
	check(ag.progress.locked_reason("weld_post") == "", "сельхозмаш: сварка открыта сразу")
	print("— рейтинг")
	run(g, 1440.0 * 3)
	print("    ", g.progress.rating, " → ", g.progress.stars_text())
	check(g.progress.stars >= 1 and g.progress.stars <= 5 and g.progress.rating.size() == 5, "звёзды посчитаны: %d" % g.progress.stars)
	print("— тендеры")
	var m := Scenario.new_game("sandbox", "secret", "market", 9, {"all_open": true})
	m.progress.stage = 3
	m.office.all_depts = true   # с 1.10 госзаказ ведёт юрист
	var cp := Scenario.put(m, "checkpoint", Vector2i(10, 30))
	check(cp != null and m.story.has_checkpoint(), "проходная с вахтой поставлена")
	var st := 0
	for i in 30:
		m.orders._special_offers()
	for o2: Dictionary in m.orders.list:
		if str(o2.get("kind", "")) == "state":
			st += 1
	check(st >= 1, "режимный завод получает госзаказ (%d)" % st)
	var money0 := m.money
	for o3: Dictionary in m.orders.list:
		if str(o3.get("kind", "")) == "state" and str(o3["status"]) == "offer":
			m.orders.accept(int(o3["id"]), false)
			break
	check(m.money > money0, "аванс по госзаказу получен")
	m.progress.stage = 4
	m.reputation = 80.0
	var ex := 0
	for i2 in 30:
		m.orders._special_offers()
	for o4: Dictionary in m.orders.list:
		if str(o4.get("kind", "")) == "export":
			ex += 1
	check(ex >= 1, "экспортные заказы на этапе 4 (%d)" % ex)
	check(m.inspect._applicable("military"), "военная приёмка для режимного завода")
	print("— старое сохранение (0.5)")
	var old := g.to_dict()
	old.erase("progress")
	old["version"] = 5
	var s5 := Sim.from_dict(JSON.parse_string(JSON.stringify(old)))
	run(s5, 600.0)
	check(s5.progress.profile == "mech" and s5.progress.stage >= 1, "сохранение 0.5 загружено, этап «%s»" % s5.progress.stage_name())
	s5.dispose()
	m.dispose()
	g.dispose()
	ag.dispose()
	print("РЕЗУЛЬТАТ: ", "OK" if fails.is_empty() else "ОШИБКИ: " + ", ".join(fails))
	quit(0 if fails.is_empty() else 1)
