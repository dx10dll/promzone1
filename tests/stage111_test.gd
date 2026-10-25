extends SceneTree
## Тест версии 1.11 «Развитие»: восемь веток по три ступени, кабинет директора, ступени держат люди,
## ступени закрывают лизинг, страхование, контракты, экспорт, тендеры, ISO, ПТУ, иногородних,
## «впритык», соцсферу и шефство; цели этапа на выбор; сохранение и перенос старых сохранений.
## godot --headless --path . -s res://tests/stage111_test.gd

const S := preload("res://tests/setups.gd")

var fails: Array[String] = []


func check(cond: bool, what: String) -> void:
	print(("  ✓ " if cond else "  ✗ ") + what)
	if not cond:
		fails.append(what)


func _director(sim: Sim) -> void:
	S._box(sim, Rect2i(2, 20, 6, 5), 3, Vector2i(4, 24))
	sim.world.refresh_all()
	sim.place_thing("director_desk", Vector2i(3, 21), true, false)
	sim.rooms.update()
	sim.rooms.assign(sim.rooms.room_at(Vector2i(4, 22)), "director_office")
	sim.rooms.update()


func _days(sim: Sim, d: float) -> void:
	var until := sim.minute + d * 1440.0
	while sim.minute < until:
		sim.tick(5.0)


func _init() -> void:
	Defs.load_all()
	var sim := Scenario.new_game("garage", "mech", "calm", 111)
	sim.story.enabled = false
	sim.progress.tutorial = -1

	print("— дерево")
	var br := Develop.branches()
	check(br.size() == 9, "девять веток — с 1.13 и «Земля» (%d)" % br.size())
	var ok_struct := true
	for b: Dictionary in br:
		var steps: Array = b["steps"]
		if steps.size() != (2 if str(b.get("id", "")) == "tech" and not Defs.CHIEF_ENGINEER else 3):   # 1.40: без главного инженера
			ok_struct = false
		for sd: Dictionary in steps:
			if sd.has("dept"):
				if not Defs.departments.has(str(sd["dept"])):
					ok_struct = false
			elif (float(sd.get("cost", 0.0)) <= 0.0 and not sd.has("lot")) or int(sd.get("days", 0)) <= 0:
				ok_struct = false
	check(ok_struct, "в каждой ветке три ступени; у ступеней-отделов есть отдел, у остальных — цена и срок")
	check(Develop.all_ids().size() == (27 if Defs.CHIEF_ENGINEER else 26), "всего %d ступеней (1.40: без главного инженера — 26)" % Develop.all_ids().size())
	check(Defs.rooms.has("director_office") and Defs.objects.has("director_desk") and Rooms.TYPES.has("director_office"), "кабинет директора и стол директора")

	print("— ступени-отделы открывает найм")
	check(not sim.dev.on("fin1"), "без бухгалтера «Бухучёт» закрыт")
	sim.office.all_depts = true
	check(sim.dev.on("fin1") and sim.dev.on("law3"), "режим «все отделы» открывает всё (для старых тестов)")
	sim.office.all_depts = false

	print("— кабинет директора")
	sim.money = 3000000.0
	for i in 4:
		S.hire(sim, "cleaner", "haul", 3)
	check(sim.workers.size() >= 6, "в штате %d человек" % sim.workers.size())
	var dk0 := Director.desk(sim)   # 1.40: кабинет директора есть с начала игры — убираем, чтобы проверить запрет
	if dk0:
		sim.remove_thing(dk0, 0.0)
		sim.rooms.update()
	check(sim.dev.block_reason("city1") == "Нужен кабинет директора", "без кабинета директора не исследовать: %s" % sim.dev.block_reason("city1"))
	_director(sim)
	check(sim.dev.root_ok(), "кабинет директора построен")
	check(sim.dev.block_reason("city1") == "", "«Профком» можно начать")
	check(sim.dev.status("city1") == "ready", "статус — «можно»")
	var m0 := sim.money
	check(sim.dev.start("city1") == "", "начали «Профком»")
	check(absf(m0 - sim.money - 40000.0) < 1.0, "списано 40 000 ₽")
	check(sim.dev.block_reason("city2") != "", "одна ступень за раз: %s" % sim.dev.block_reason("city2"))
	_days(sim, 1.05)
	check(sim.dev.done.has("city1") and sim.dev.on("city1"), "через день «Профком» открыт")
	check(sim.crew.union_on() and str(sim.crew.union.get("stance", "")) == "support", "завод сам создал профсоюз — с поддержкой")

	print("— этап разрешает, а не дарит")
	check(sim.progress.stage == 1 and sim.dev.block_reason("city2").begins_with("Нужен этап"), "в гараже «Соцсфера» закрыта: %s" % sim.dev.block_reason("city2"))
	sim.progress.stage = 2
	check(sim.can_place("stove", Vector2i(30, 30)).contains("Соцсфера"), "плиту не поставить без «Соцсферы»: %s" % sim.can_place("stove", Vector2i(30, 30)))
	check(sim.dev.block_reason("city2") == "", "на этапе «Мастерская» — можно")
	sim.dev.start("city2")
	_days(sim, 3.05)
	check(sim.dev.on("city2") and not sim.can_place("stove", Vector2i(30, 30)).contains("Соцсфера"), "после «Соцсферы» плита ставится")
	check(sim.dev.block_reason("fin2").begins_with("Сначала"), "«Себестоимость» без бухгалтера: %s" % sim.dev.block_reason("fin2"))

	print("— ступень держит человек")
	S.offices(sim)
	var acc := S.hire(sim, "accountant", "office", 5)
	sim.office.desk_for(acc)
	check(sim.office.active("accounting") and sim.dev.on("fin1"), "бухгалтер за столом — «Бухучёт» работает")
	check(sim.dev.block_reason("fin2").begins_with("Нужен свой кабинет"), "для «Себестоимости» нужен свой кабинет: %s" % sim.dev.block_reason("fin2"))
	S._box(sim, Rect2i(14, 22, 5, 5), 3, Vector2i(16, 22))
	sim.world.refresh_all()
	sim.place_thing("office_desk", Vector2i(15, 23), true, false)
	sim.place_thing("safe", Vector2i(17, 25), true, false)
	sim.rooms.update()
	sim.rooms.assign(sim.rooms.room_at(Vector2i(16, 24)), "accounting")
	sim.rooms.update()
	check(int(sim.office.room_status("accounting")[0]) == 1, "кабинет бухгалтерии есть")
	check(sim.dev.start("fin2") == "", "начали «Себестоимость»")
	_days(sim, 3.05)
	check(sim.dev.on("fin2"), "«Себестоимость» работает")
	sim.fire(acc)
	check(not sim.dev.on("fin2") and sim.dev.status("fin2") == "idle", "уволили бухгалтера — ступень не работает")
	var acc2 := S.hire(sim, "accountant", "office", 5)
	sim.office.desk_for(acc2)
	check(acc2 != null and sim.dev.on("fin2"), "наняли нового — снова работает")

	print("— что закрывают ступени")
	sim.progress.stage = 3
	sim.market.leasing_on = true
	check(not sim.market.can_lease("lathe", 160000.0), "лизинг — только после «Банк и лизинг»")
	sim.market.toggle_insurance("property", true)
	check(not sim.market.insurance.has("property"), "страховка — тоже")
	check(not sim.office.loan_ok(3000000.0) and sim.office.loan_ok(800000.0), "кредит 3 млн — после «Банк и лизинг», 800 тыс. — сразу")
	check(sim.dev.start("fin3") == "", "начали «Банк и лизинг»")
	_days(sim, 5.05)
	check(sim.market.can_lease("lathe", 160000.0) and sim.office.loan_ok(3000000.0), "после ступени — лизинг и большой кредит")
	check(sim.office.loan_rate() < 0.17, "ставка ниже: %d%%" % int(round(sim.office.loan_rate() * 100.0)))
	var risk0 := sim.sales.risk_k()
	sim.sales.risk = 2
	check(sim.sales.risk_k() == float(Sales.RISK_K[1]), "«впритык» без ступени работает как «обычно»")
	sim.sales.risk = 1
	check(risk0 > 0.0 and sim.market.iso_apply().contains("ISO"), "ISO без ступени: %s" % sim.market.iso_apply())
	check(sim.training.ptu_sign().contains("ПТУ"), "договор с ПТУ без ступени: %s" % sim.training.ptu_sign())
	check(sim.town.away_candidates() == 0, "иногородних без «Связи с ПТУ» не зовут")
	check(sim.town.kg_upgrade().contains("Шефство") and sim.town.dk_buy().contains("Шефство"), "детсад и ДК — после «Шефства»")
	sim.reputation = 80.0
	var exp0 := 0
	for i2 in 40:
		sim.orders._special_offers()
	for o: Dictionary in sim.orders.list:
		if str(o.get("kind", "")) in ["export", "state"]:
			exp0 += 1
	check(exp0 == 0, "без «Контрактов» и «Тендеров» — ни экспорта, ни госзаказа")
	sim.dev.done.append("mkt3")
	sim.dev.done.append("law3")
	sim.office.all_depts = true
	sim.progress.ooo = true
	sim.place_thing("checkpoint", Vector2i(40, 24), true, false)
	check(sim.story.has_checkpoint(), "проходная с вахтой стоит")
	for i3 in 40:
		sim.orders._special_offers()
	var exp1 := 0
	var st1 := 0
	for o2: Dictionary in sim.orders.list:
		if str(o2.get("kind", "")) == "export":
			exp1 += 1
		if str(o2.get("kind", "")) == "state":
			st1 += 1
	check(exp1 >= 1 and st1 >= 1, "со ступенями — экспорт (%d) и госзаказ (%d) уже на этапе «Малое»" % [exp1, st1])
	sim.office.all_depts = false

	print("— отложить ступень")
	var free := ""
	for id in ["hr2", "plan2", "city3", "prod3"]:
		if sim.dev.block_reason(id) == "":
			free = id
			break
	if free == "":
		sim.office.all_depts = true
		free = "city3"
	var m1 := sim.money
	sim.dev.start(free)
	sim.dev.cancel()
	sim.office.all_depts = false
	check(sim.dev.cur == "" and absf((m1 - sim.money) - float(Develop.step_def(free)["cost"]) * 0.5) < 1.0, "отложили «%s» — вернули половину" % str(Develop.step_def(free)["name"]))

	print("— сохранение")
	sim.dev.start("city3")
	var dd: Dictionary = JSON.parse_string(JSON.stringify(sim.to_dict()))
	var s2 := Sim.from_dict(dd)
	check(s2.dev.done.has("fin2") and s2.dev.done.has("city1") and s2.dev.cur == sim.dev.cur and absf(s2.dev.cur_end - sim.dev.cur_end) < 1.0, "открытые ступени и текущая сохраняются")
	var old: Dictionary = JSON.parse_string(JSON.stringify(sim.to_dict()))
	old.erase("dev")
	old["version"] = 7
	(old["progress"] as Dictionary)["stage"] = 3
	var s3 := Sim.from_dict(old)
	check(s3.dev.done.has("fin3") and s3.dev.done.has("mkt3") and s3.dev.done.has("city3") and not s3.dev.done.has("fin1"), "старое сохранение: открытое этапом остаётся открытым")

	print("— номера помещений в сохранениях 1.10")
	var s4 := Scenario.new_game("garage", "mech", "calm", 114)
	s4.story.enabled = false
	var zi := s4.world.idx(Vector2i(30, 30))
	s4.world.zone[zi] = 20          # в 1.10 это был учебный класс
	s4.place_thing("phone_stand", Vector2i(31, 31), true, false)
	Rooms.migrate_zones_v8(s4)
	check(int(s4.world.zone[zi]) == 16 and Rooms.TYPES[15] == "classroom", "учебный класс 1.10 остался учебным классом")
	var s5 := Scenario.new_game("garage", "mech", "calm", 115)
	s5.world.zone.fill(0)   # в 1.9 не было техпомещения (с 1.18 оно в гараже с самого начала)
	var zi2 := s5.world.idx(Vector2i(30, 30))
	s5.world.zone[zi2] = 20          # в 1.9 это общежитие
	Rooms.migrate_zones_v8(s5)
	check(int(s5.world.zone[zi2]) == 20 and Rooms.TYPES[19] == "dorm", "сохранение 1.9 не трогаем")

	print("— цели этапа на выбор")
	var g := Scenario.new_game("garage", "mech", "calm", 116)
	g.story.enabled = false
	g.progress.stage = 2
	check(g.progress.choice_need() == 2 and (g.progress.stage_choice()["list"] as Array).size() == 4, "на «Мастерской»: две обязательные цели и две из четырёх на выбор")
	g.progress.ooo = true
	S._box(g, Rect2i(30, 3, 10, 10), 1, Vector2i(30, 7))
	g.world.refresh_all()
	g.place_thing("lathe", Vector2i(32, 5), true, false)
	g.rooms.update()
	g.rooms.assign(g.rooms.room_at(Vector2i(34, 7)), "workshop")
	g.rooms.update()
	g.stats["earned"] = 2500000.0
	g.town.rel = 40.0
	for w in g.workers:
		w.mood = 30.0
	g.progress._check_goals()
	check(g.progress.stage == 2, "обязательные выполнены, на выбор — одна (объём): этап не меняется")
	g.town.rel = 70.0
	g.progress._check_goals()
	check(g.progress.stage == 3, "вторая дорога — город: новый этап «%s»" % g.progress.stage_name())
	check(g.progress.stage_progress()[1] == 4, "в задачах — 4 цели (2 обязательные + 2 на выбор)")

	print("РЕЗУЛЬТАТ: " + ("OK" if fails.is_empty() else "ОШИБКИ: " + ", ".join(fails)))
	quit(0 if fails.is_empty() else 1)
