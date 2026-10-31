extends SceneTree
## Тест 1.61 «Разгрузка: охрана труда и газета»: три уровня «Охраны труда» включают старые флаги и стоят денег в месяц,
## старый сейв выводит уровень из флагов, газета выходит только по понедельникам, а срочное сообщается сразу.
## Окно игры в режиме -s не собрать (автозагрузки), поэтому карточка проверяется в stage161_ui.tscn — этот файл запускает её отдельно.
## godot --headless --path . --audio-driver Dummy -s res://tests/stage161_test.gd

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


func _keys(sim: Sim) -> Array[String]:
	var out: Array[String] = []
	for v: Dictionary in sim.inspect.violations("labor"):
		if Safety.KEYS.has(str(v["key"])):
			out.append(str(v["key"]))
	return out


## Завод с шестью рабочими, фрезерным станком (вредное место) и фрезеровщиком на нём.
func _plant(seed_v: int) -> Dictionary:
	var sim := _game(seed_v)
	S.big_shop(sim, false)
	for w0: Worker in sim.workers.duplicate():
		sim.workers.erase(w0)
	var mill: Thing = null
	for m: Thing in sim.things_of("machine"):
		if m.def_id == "mill":
			mill = m
	for i in 5:
		S.hire(sim, "laborer", "haul", 4)
	var miller := S.hire(sim, "miller", "milling", 6)
	miller.workplace = mill.id
	for w: Worker in sim.workers:
		w.days_worked = 5
		w.ppe = 0.0
	sim.eng.sout[str(mill.id)] = {"cls": 2, "day": sim.day(), "f": []}
	return {"sim": sim, "mill": mill, "miller": miller}


func _initialize() -> void:
	print("— уровни и старые флаги")
	var d := _plant(1610)
	var sim: Sim = d["sim"]
	var miller: Worker = d["miller"]
	check(sim.safety.level == 0, "новая игра: уровень «Минимум»")
	check(Safety.level_name(0) == "Минимум" and Safety.level_name(1) == "По закону" and Safety.level_name(2) == "Образцово", "названия уровней")
	var k0 := _keys(sim)
	check(k0.has("no_tb") and k0.has("no_sout") and k0.has("no_milk") and k0.has("ppe_worn"), "«Минимум»: инспекция находит все четыре пункта: %s" % str(k0))
	check(not sim.eng.milk_on and not sim.training.tb_valid(), "«Минимум»: молока и инструктажа нет")

	print("— стоимость в месяц")
	var n := sim.safety.staff_n()
	check(n == 6, "рабочих: %d" % n)
	check(sim.safety.monthly_cost(0) == 0.0, "«Минимум» — 0 ₽")
	check(sim.safety.monthly_cost(1) == 3000.0 + 2000.0 * n, "«По закону»: %s" % Defs.money_str(sim.safety.monthly_cost(1)))
	check(sim.safety.monthly_cost(2) == 9000.0 + 4000.0 * n and sim.safety.monthly_cost(2) > sim.safety.monthly_cost(1), "«Образцово»: %s" % Defs.money_str(sim.safety.monthly_cost(2)))
	var m0 := sim.money
	for i in 3:
		sim.safety.morning()
	check(sim.money == m0, "«Минимум» ничего не списывает")

	sim.safety.set_level(1)
	check(sim.safety.level == 1 and sim.eng.milk_on, "«По закону» включает молоко")
	check(sim.training.tb_valid() and sim.training.injury_k() == 0.7, "«По закону»: журнал инструктажа в порядке, травм на 30% меньше")
	check(sim.eng.unassessed() == 0 or sim.eng.sout_busy(), "«По закону»: замеры СОУТ идут сами")
	var mm := sim.money
	_run(sim, 3.0 * 1440.0)
	check(not sim.eng.sout_busy() and sim.eng.unassessed() == 0, "СОУТ проведена сама, без отдельной оплаты")
	for w: Worker in sim.workers:
		sim.eng.on_spawn(w)
	check(sim.eng.without_ppe().is_empty(), "СИЗ выданы всем без шкафа и склада")
	check(_keys(sim).is_empty(), "«По закону»: все четыре пункта инспекции закрыты")
	check(miller.thoughts.any(func(t: Dictionary) -> bool: return str(t["id"]) == "milk"), "молоко выдали — людям приятно")
	var spent := mm - sim.money
	var days := int(sim.season.dpm())
	var m1 := sim.money
	for i in days:
		sim.safety.morning()
	var fee := m1 - sim.money
	check(absf(fee - sim.safety.monthly_cost(1)) <= float(days), "за игровой месяц списано %s при ставке %s" % [Defs.money_str(fee), Defs.money_str(sim.safety.monthly_cost(1))])
	check(spent > 0.0, "ставка списывается ежедневно (за 3 дня: %s)" % Defs.money_str(spent))
	var bare0 := sim.eng.injury_k(miller)
	check(bare0 == 1.0, "«По закону»: риск травм обычный с СИЗ")

	sim.safety.set_level(2)
	check(sim.safety.level == 2, "«Образцово» выбран")
	check(sim.eng.injury_k(miller) < bare0 and absf(sim.eng.injury_k(miller) - 0.85) < 0.001, "«Образцово»: комиссия с профкомом, травм ещё меньше (×%.2f)" % sim.eng.injury_k(miller))
	miller.ppe = 20.0
	miller.thoughts.clear()
	sim.eng.on_spawn(miller)
	check(miller.ppe >= 50.0 and miller.thoughts.any(func(t: Dictionary) -> bool: return str(t["id"]) == "safe_model"), "«Образцово»: свежие СИЗ и довольные люди")
	var m2 := sim.money
	sim.safety.morning()
	check(m2 - sim.money >= roundf(sim.safety.cost_per_day(2)) - 1.0, "день на «Образцово» списан: %s" % Defs.money_str(m2 - sim.money))
	check(sim.safety.paid_total > 0.0, "учтено уплаченное: %s" % Defs.money_str(sim.safety.paid_total))
	sim.safety.set_level(0)
	check(sim.safety.level == 0 and not sim.eng.milk_on, "возврат на «Минимум» выключает молоко")
	check(sim.eng.injury_k(miller) == 1.0, "на «Минимуме» нет бонуса к травмам")

	print("— сейв")
	sim.safety.set_level(2)
	var dd := Sim.from_dict(JSON.parse_string(JSON.stringify(sim.to_dict())))
	check(dd.safety.level == 2 and absf(dd.safety.paid_total - sim.safety.paid_total) < 1.0, "уровень и сумма сохраняются")
	dd.dispose()

	print("— старый сейв: уровень из старых флагов")
	var o := _plant(1611)
	var os: Sim = o["sim"]
	os.eng.milk_on = true
	os.training.tb_day = os.day()
	os.eng.sout_ids = os.eng.workplaces().map(func(t: Thing) -> int: return t.id)
	os.eng._finish_sout()
	var old := os.to_dict()
	old.erase("safety")
	var ol := Sim.from_dict(JSON.parse_string(JSON.stringify(old)))
	check(ol.safety.level == -1, "в старом сейве уровня нет")
	ol.safety.ensure()
	check(ol.safety.level == 1, "молоко, СОУТ и инструктаж в порядке — «По закону»: %d" % ol.safety.level)
	ol.dispose()
	var old2 := _plant(1612)
	var s2: Sim = old2["sim"]
	var d2 := s2.to_dict()
	d2.erase("safety")
	var l2 := Sim.from_dict(JSON.parse_string(JSON.stringify(d2)))
	l2.safety.ensure()
	check(l2.safety.level == 0, "ничего не делали — «Минимум»")
	l2.dispose()
	var old3 := _plant(1613)
	var s3: Sim = old3["sim"]
	s3.eng.milk_on = true
	s3.training.tb_day = s3.day()
	s3.eng.sout_ids = s3.eng.workplaces().map(func(t: Thing) -> int: return t.id)
	s3.eng._finish_sout()
	s3.place_thing("ppe_cabinet", Vector2i(30, 16), true, false)
	for w: Worker in s3.workers:
		w.ppe = 80.0
	var d3 := s3.to_dict()
	d3.erase("safety")
	var l3 := Sim.from_dict(JSON.parse_string(JSON.stringify(d3)))
	l3.safety.ensure()
	check(l3.safety.level == 2, "всё сделано, и шкаф СИЗ есть — «Образцово»: %d" % l3.safety.level)
	l3.dispose()

	print("— чек-лист инспектора ссылается на карточку")
	var fc := sim.inspect.forecast("labor")
	var carded := (fc["items"] as Array).filter(func(it: Dictionary) -> bool: return bool(it.get("card", false)))
	check(carded.size() == Safety.KEYS.size(), "четыре пункта чек-листа ведут в карточку: %d" % carded.size())
	for key in Safety.KEYS:
		check(Inspections.fix_text(key).contains("Охран"), "подсказка «%s» называет карточку" % key)
	sim.dispose()

	print("— газета: выпуск по понедельникам, срочное сразу")
	var g := _game(1614)
	var paper := g.paper
	var last_issues := paper.issues.size()
	var issue_days: Array[int] = []
	var urgent_checked := false
	for day_i in 30:
		var today := g.day()
		_run(g, 1440.0 - fmod(g.minute, 1440.0) + 400.0)   # до утра следующего дня
		if paper.issues.size() > last_issues:
			issue_days.append(g.day())
			check(g.weekday() == 0, "номер вышел в понедельник (день %d)" % g.day())
		last_issues = paper.issues.size()
		if not urgent_checked and g.weekday() == 2:
			urgent_checked = true
			var ev0 := g.events.size()
			var pend0 := paper.pending.size()
			g.story.ignite((g.things_of("machine")[0] as Thing).cell, "Короткое замыкание")
			check(g.events.size() > ev0 and str(g.events[0]["text"]).contains("Пожар"), "пожар сообщён уведомлением сразу, не ждёт понедельника")
			check(paper.issues.size() == last_issues, "внеочередного номера нет")
			check(paper.pending.size() > pend0, "заметка о пожаре ждёт воскресного номера понедельника")
		if today > 28:
			break
	check(issue_days.size() >= 3, "за месяц вышло %d номера, дни %s" % [issue_days.size(), str(issue_days)])
	var wd_ok := true
	for i in range(1, issue_days.size()):
		if issue_days[i] - issue_days[i - 1] != 7:
			wd_ok = false
	check(wd_ok, "между номерами ровно неделя")
	var fire_in_paper := false
	for iss: Dictionary in paper.issues:
		for it: Dictionary in iss["items"]:
			if str(it.get("title", "")) == "Пожар на заводе":
				fire_in_paper = true
	check(fire_in_paper, "в понедельничном номере есть итог про пожар")
	g.dispose()

	print("— окно: карточка, «Карьера»")
	var out: Array = []
	var code := OS.execute(OS.get_executable_path(), ["--headless", "--path", ProjectSettings.globalize_path("res://"),
		"--audio-driver", "Dummy", "res://tests/stage161_ui.tscn"], out, true)
	var text := "\n".join(PackedStringArray(out))
	for ln in text.split("\n"):
		if ln.contains("✓") or ln.contains("✗") or ln.contains("—") or ln.contains("ERROR"):
			print(ln)
	check(code == 0 and text.contains("ВСЁ ВЕРНО"), "окно «Охрана труда» и «Карьера» (код %d)" % code)

	print("РЕЗУЛЬТАТ: " + ("ВСЁ ВЕРНО" if fails.is_empty() else "ОШИБКИ: %d" % fails.size()))
	quit(0 if fails.is_empty() else 1)
