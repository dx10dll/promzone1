extends SceneTree
## Тест 1.66: «Ваша задача» и «Первые шаги» — этап в верхней панели (текст, полоска, чего не хватает), цепочка из семи заданий
## (шаги по состоянию завода, награда один раз, реплика советника), старое сохранение, песочница, настройки, переводы.
## godot --headless --path . --audio-driver Dummy -s res://tests/stage166_test.gd

var fails: Array[String] = []


func check(cond: bool, what: String) -> void:
	print(("  ✓ " if cond else "  ✗ ") + what)
	if not cond:
		fails.append(what)


func _garage(seed_v: int = 1660) -> Sim:
	return Scenario.new_game("garage", "mech", "market", seed_v, {"tutorial": false})


func _old_save() -> Sim:
	return Sim.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://tests/saves/save_1.23.json")) as Dictionary)


func _init() -> void:
	Defs.load_all()
	L.apply("ru")
	_stage_indicator()
	_chain()
	_old_saves()
	_modes()
	_i18n()
	print("РЕЗУЛЬТАТ: ", "ВСЕ ПРОШЛИ" if fails.is_empty() else "ПРОВАЛЕНО %d: %s" % [fails.size(), str(fails)])
	quit(0 if fails.is_empty() else 1)


func _stage_indicator() -> void:
	print("— этап в верхней панели")
	var sim := _garage()
	var pg := sim.progress
	var arr: Array = Defs.stages["stages"]
	check(arr.size() == Progress.STAGE_COUNT, "в данных шесть этапов")
	for i in arr.size():
		pg.stage = i + 1
		var want := "Этап %d из 6: %s" % [i + 1, str(arr[i]["name"])]
		check(pg.stage_label() == want, "текст этапа «%s»" % want)
	pg.stage = 1
	check(pg.stage_fraction() == 0.0, "полоска пуста, пока цели не выполнены")
	var miss := pg.missing_lines()
	var unmet := 0
	for g: Dictionary in pg.stage_goals():
		if not bool(pg.goal_state(g)[0]):
			unmet += 1
	check(miss.size() == unmet and unmet == 2, "не хватает двух целей этапа «Гараж» (%d)" % miss.size())
	check(miss[0].contains("Выполнить 10 заказов") and miss[0].contains("0/10"), "строка про заказы с прогрессом: %s" % miss[0])
	check(miss[1].contains("Оборот") and miss[1].contains("тыс"), "строка про оборот: %s" % miss[1])
	sim.stats["orders_done"] = 10
	check(absf(pg.stage_fraction() - 0.5) < 0.001, "10 заказов — полоска наполовину")
	check(pg.missing_lines().size() == 1 and pg.missing_lines()[0].contains("Оборот"), "осталась одна цель — оборот")
	var tip := pg.stage_tip()
	check(tip.contains("Этап 1 из 6: Гараж") and tip.contains("Мастерская") and tip.contains("Оборот") and not tip.contains("Выполнить 10 заказов"), "подсказка: этап, следующий этап, только то, чего не хватает")
	sim.stats["earned"] = 1000000.0
	pg._check_goals()
	check(pg.stage == 2 and pg.stage_label() == "Этап 2 из 6: Мастерская", "цели выполнены — этап 2, текст сменился")
	var m2 := pg.missing_lines()
	var unmet2 := 0
	for g2: Dictionary in pg.stage_goals():
		if not bool(pg.goal_state(g2)[0]):
			unmet2 += 1
	var routes_left := 0
	for g3: Dictionary in pg.stage_choice().get("list", []):
		if not bool(pg.goal_state(g3)[0]):
			routes_left += 1
	check(unmet2 == 1 and pg.choice_need() == 2, "этап 2: цех 140 клеток уже есть, не хватает ООО; на выбор две дороги из четырёх")
	check(m2.size() == unmet2 + 1 + routes_left, "строки: цели + «ещё N дорог» + невыполненные дороги (%d)" % m2.size())
	check(m2.any(func(s: String) -> bool: return s.contains("Ещё %d из 4" % (pg.choice_need() - pg.choice_done()))), "сказано, сколько дорог на выбор осталось")
	check(m2.any(func(s: String) -> bool: return s.contains("ООО")) and not m2.any(func(s: String) -> bool: return s.contains("60 клеток")), "ООО названо, готовый цех не перечисляется")
	check(m2.any(func(s: String) -> bool: return s.contains("Оборот 2 млн")) or pg.goal_state(pg.stage_choice()["list"][0])[0], "дорога «объём» названа, если не выполнена")
	pg.stage = 6
	check(pg.stage_fraction() == 1.0 and pg.missing_lines().is_empty() and pg.stage_tip().contains("высший"), "последний этап: полоска полная, недостающего нет")
	# реальные требования следующих этапов видны в подсказке
	pg.stage = 3
	pg.flags["big_order"] = false
	var t3 := pg.stage_tip()
	check(t3.contains("крупный контракт") and t3.contains("15 человек"), "этап 3: крупный контракт и 15 человек в списке")


func _chain() -> void:
	print("— цепочка «Первые шаги»")
	var sim := _garage()
	var st := sim.progress.starter
	check(st.mode == FirstSteps.MODE_NONE and not st.active(), "в тестовом заводе цепочка молчит, пока игровая сцена её не включила")
	var m0 := sim.money
	sim.stats["orders_done"] = 5
	st.update()
	check(sim.money == m0 and st.done.is_empty(), "без запуска наград нет")
	sim.stats["orders_done"] = 0
	st.begin()
	check(st.active() and st.done.is_empty() and FirstSteps.STEPS.size() == 7, "запуск: семь заданий, ни одно не выполнено")
	check(st.current()["id"] == "order", "первое задание — взять заказ")
	st.update()
	check(st.done.is_empty(), "стартовые заказы не засчитываются")
	var rep0 := sim.reputation
	# 1. новый заказ
	var o := sim.orders.make_offer()
	sim.orders.list.append(o)
	st.update()
	check(st.done.is_empty(), "предложение без принятия — не заказ")
	var err := sim.orders.accept(int(o["id"]), false)
	check(err == "", "заказ принят (%s)" % err)
	var m1 := sim.money
	st.update()
	check(st.done == ["order"], "заказ принят — задание выполнено")
	check(sim.money == m1 + 3000.0, "награда 3 000 ₽")
	st.update()
	st.update()
	check(sim.money == m1 + 3000.0 and st.done.size() == 1, "награда выдана один раз")
	var cq := sim.calls.queue.filter(func(q: Dictionary) -> bool: return str(q["tag"]) == "first_order")
	check(cq.size() == 1 and str(cq[0]["caller"]) == "engineer", "главный инженер прокомментировал заказ")
	check(Calls.text_of(cq[0], sim).contains("Первый новый заказ"), "текст реплики читается")
	check(not sim.ledger.is_empty() and str(sim.ledger[0]["text"]) == "Награда за задание", "награда записана в журнал денег")
	# 2. деталь и ОТК: без годной детали на складе не засчитывается
	sim.stats["made"] = 1
	st.update()
	check(not st.done.has("qc"), "деталь сделана, но ОТК ещё не сдана — нет")
	for oo: Dictionary in sim.orders.by_status(["active"]):
		oo["status"] = "ready"
		break
	var m2 := sim.money
	st.update()
	check(st.done.has("qc") and sim.money == m2 + 5000.0, "деталь прошла ОТК — +5 000 ₽")
	# 3. отгрузка
	sim.stats["orders_done"] = 1
	var m3 := sim.money
	st.update()
	check(st.done.has("ship") and sim.money == m3 + 10000.0, "заказ отгружен — +10 000 ₽")
	check(not st.done.has("orders3"), "один заказ — не три")
	# 4. найм
	sim.refresh_candidates()
	var n0 := sim.workers.size()
	var herr := sim.hire(0)
	check(herr == "" and sim.workers.size() == n0 + 1, "кандидат нанят (%s)" % herr)
	check(int(sim.stats.get("hired", 0)) == 1, "найм посчитан")
	st.update()
	check(st.done.has("hire") and absf(sim.reputation - (rep0 + 1.0)) < 0.001, "нанят человек — репутация +1")
	# 5. помещение
	check(not st.done.has("build"), "помещения пока те же")
	st.base_rooms = st.valid_rooms() - 1   # как будто к старту было на одно меньше: свежепостроенное
	var m5 := sim.money
	st.update()
	check(st.done.has("build") and sim.money == m5 + 5000.0, "новое помещение — +5 000 ₽")
	# 6. три заказа
	sim.stats["orders_done"] = 3
	st.update()
	check(st.done.has("orders3") and absf(sim.reputation - (rep0 + 3.0)) < 0.001, "три заказа — репутация ещё +2")
	# 7. неделя в плюсе
	sim.office.book("Оплата: заказ", 80000.0)
	check(not st.reached("week"), "пока неделя не закончилась — нет")
	sim.minute = 8.0 * 1440.0 + 600.0
	check(sim.office.week_no() == 2, "идёт вторая неделя")
	check(st.week_in_profit(), "прошлая неделя в плюсе")
	var m7 := sim.money
	var ev0 := sim.events.size()
	st.update()
	check(st.done.size() == 7 and sim.money == m7 + 20000.0, "неделя в плюсе — +20 000 ₽, все задания готовы")
	check(st.mode == FirstSteps.MODE_DONE and not st.active() and st.current().is_empty(), "цепочка завершена, карточка уходит")
	check(sim.events.size() > ev0, "сообщение о завершении")
	var m8 := sim.money
	st.update()
	check(sim.money == m8, "после конца цепочки наград больше нет")
	# убыточная неделя
	var sim2 := _garage(1661)
	var st2 := sim2.progress.starter
	st2.begin()
	sim2.office.book("Зарплата: бригада", -500000.0)
	sim2.minute = 8.0 * 1440.0
	check(not st2.week_in_profit(), "неделя в минусе не засчитывается")
	# награда не делает неделю прибыльной
	var sim3 := _garage(1662)
	sim3.progress.starter.begin()
	sim3.office.book("Зарплата: бригада", -500000.0)
	sim3.stats["orders_done"] = 1
	sim3.progress.starter.update()
	check(sim3.office.week_total(sim3.office.weeks[0]) < 0.0, "награды не попадают в учёт недели")
	# сохранение посреди цепочки
	var sim4 := _garage(1663)
	sim4.progress.starter.begin()
	sim4.stats["orders_done"] = 1
	sim4.progress.starter.update()
	var back := Sim.from_dict(JSON.parse_string(JSON.stringify(sim4.to_dict())) as Dictionary)
	check(back.progress.starter.mode == FirstSteps.MODE_ON and back.progress.starter.done == sim4.progress.starter.done, "цепочка переживает сохранение")
	var mb := back.money
	back.progress.starter.update()
	check(back.money == mb, "после загрузки награды не повторяются")
	# выключено в настройках
	var sim5 := _garage(1664)
	var st5 := sim5.progress.starter
	st5.begin()
	st5.enabled = false
	sim5.stats["orders_done"] = 3
	var m9 := sim5.money
	st5.update()
	check(sim5.money == m9 and st5.done.is_empty() and not st5.active(), "настройка «Первые шаги» выключена — ни карточки, ни наград")


func _old_saves() -> void:
	print("— старые сохранения")
	var sim := _old_save()
	var st := sim.progress.starter
	check(st.mode == FirstSteps.MODE_NONE and not st.slides_seen, "в старом сохранении цепочки нет")
	var m0 := sim.money
	st.adopt_old()
	check(st.done.has("ship") and st.done.has("hire") == (sim.workers.size() > sim.progress.start_staff), "пройденные вехи отмечены (%s)" % str(st.done))
	check(sim.money == m0, "за уже пройденное наград нет")
	check(st.mode == FirstSteps.MODE_DONE and not st.active(), "завод старше второго этапа: карточки нет")
	# старое сохранение на первом этапе: карточка остаётся с тем, что не пройдено
	var sim2 := _old_save()
	sim2.progress.stage = 1
	var st2 := sim2.progress.starter
	st2.adopt_old()
	check(st2.mode == FirstSteps.MODE_ON and st2.done.has("ship") and not st2.done.has("orders3"), "этап 1: сделанное отмечено, остальное осталось")
	check(st2.current()["id"] != "ship", "карточка начинается с первого невыполненного")
	var mm := sim2.money
	st2.update()
	check(sim2.money == mm, "повторно отмеченное не награждается")
	# запись без ключа не ломает загрузку, версия данных прежняя
	var d := sim2.to_dict()
	(d["progress"] as Dictionary).erase("starter")
	var sim3 := Sim.from_dict(JSON.parse_string(JSON.stringify(d)) as Dictionary)
	check(sim3.progress.starter.mode == FirstSteps.MODE_NONE, "сохранение без ключа загружается")


func _modes() -> void:
	print("— песочница и экран «Ваша задача»")
	var sb := Scenario.new_game("sandbox", "mech", "market", 1665, {"money": 1000000, "map": "large", "start": "garage"})
	sb.progress.starter.skip()
	sb.stats["orders_done"] = 3
	var m := sb.money
	sb.progress.starter.update()
	check(not sb.progress.starter.active() and sb.money == m, "песочница: цепочки нет")


func _i18n() -> void:
	print("— переводы")
	var rows := FileAccess.get_file_as_string("res://assets/i18n/strings_166.csv")
	check(rows.begins_with("\"keys\",\"en\""), "заголовок строк перевода")
	L.apply("en")
	var must: Array[String] = ["Взять новый заказ", "Нанять человека", "Закончить неделю в плюсе", "Вы — директор мастерской", "Победа: вырасти до завода",
		"Поражение: долги и банкротство", "ПЕРВЫЕ ШАГИ", "Этап %d из %d: %s", "Показывать экран «Ваша задача» в новой игре", "Награда за задание"]
	for k in must:
		check(tr(k) != k, "перевод есть: %s" % k)
	for st: Dictionary in FirstSteps.STEPS:
		for f in ["text", "tip", "say"]:
			check(tr(str(st[f])) != str(st[f]), "перевод шага %s/%s" % [st["id"], f])
	var sim := _garage()
	check(sim.progress.stage_label() == "Stage 1 of 6: Garage" or sim.progress.stage_label().begins_with("Stage 1 of 6: "), "английский текст этапа: %s" % sim.progress.stage_label())
	L.apply("ru")
