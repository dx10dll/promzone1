extends Node
## Тест 1.66 (интерфейс): экран «Ваша задача» — один раз в новой игре, не в песочнице и не в старом сохранении, выключается настройкой,
## открывается из «?»; этап с полоской и подсказкой в верхней панели при 1600×900 и 1920×1080; карточка «Первые шаги» в «Что делать».
## godot --path . --audio-driver Dummy res://tests/stage166_ui.tscn  (под xvfb)

var fails: Array[String] = []
var gm: GameMain = null


func check(cond: bool, what: String) -> void:
	print(("  ✓ " if cond else "  ✗ ") + what)
	if not cond:
		fails.append(what)


func _wait(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _texts(root: Node) -> Array[String]:
	var out: Array[String] = []
	for l: Node in root.find_children("*", "Label", true, false):
		out.append((l as Label).text)
	return out


func _has_text(root: Node, part: String) -> bool:
	for t in _texts(root):
		if t.contains(part):
			return true
	return false


func _boot(scn: String, opts: Dictionary, load_sim: Sim = null) -> void:
	if gm != null:
		gm.queue_free()
		gm = null
		await _wait(3)
	var g: Node = get_node("/root/Game")
	g.pending = "load" if load_sim != null else "new"
	g.pending_sim = load_sim
	g.pending_scn = scn
	g.pending_profile = "mech"
	g.pending_opts = opts
	g.pending_seed = 1660
	g.settings["tutorial_done"] = true
	gm = load("res://scenes/game.tscn").instantiate()
	add_child(gm)
	await _wait(20)


func _meta(root: Node, key: String) -> Control:
	for c: Node in root.find_children("*", "Control", true, false):
		if c.has_meta(key) and not c.is_queued_for_deletion():
			return c as Control
	return null


func _slides() -> TaskSlides:
	return gm.hud.modal as TaskSlides if gm.hud.modal is TaskSlides else null


func _ready() -> void:
	var g: Node = get_node("/root/Game")
	L.apply("ru")
	g.settings["task_intro"] = true
	g.settings["first_steps"] = true

	print("— новая игра: слайды один раз")
	await _boot("garage", {"tutorial": false, "first_steps": true})
	var ts := _slides()
	check(ts != null, "в новой игре открыт экран «Ваша задача»")
	check(gm.menu_paused, "пока он открыт, игра стоит")
	check(gm.sim.progress.starter.mode == FirstSteps.MODE_ON, "цепочка «Первые шаги» включена")
	check(ts != null and ts.page == 0 and _has_text(ts, "директор мастерской"), "слайд 1: кто вы")
	ts._next.pressed.emit()
	await _wait(2)
	check(ts.page == 1 and _has_text(ts, "Отгрузка") and _has_text(ts, "Заказ"), "слайд 2: что делаете")
	ts._next.pressed.emit()
	await _wait(2)
	check(ts.page == 2 and _has_text(ts, "Победа") and _has_text(ts, "Поражение"), "слайд 3: победа и поражение")
	for i in Progress.STAGE_COUNT:
		check(_has_text(ts, gm.sim.progress.stage_name(i + 1)), "слайд 3 называет этап «%s»" % gm.sim.progress.stage_name(i + 1))
	check(_has_text(ts, "Трое уволились") or _has_text(ts, "трудовая инспекция"), "слайд 3: поражение как в игре")
	check(ts._never.visible and ts._next.text == "Начать работу", "на последнем слайде — «Начать работу» и флажок")
	ts._next.pressed.emit()
	await _wait(3)
	check(gm.hud.modal == null and not gm.menu_paused, "после слайдов игра идёт")
	check(gm.sim.progress.starter.slides_seen, "показ запомнен в игре")
	gm.hud.show_help(false)
	await _wait(3)
	var tb: Button = gm.hud.modal.find_child("TaskBtn", true, false)
	check(tb != null, "в справочнике «?» есть кнопка «Ваша задача»")
	if tb:
		tb.pressed.emit()
		await _wait(3)
		check(_slides() != null and _slides().page == 0, "кнопка открывает слайды заново")
		_slides().close()
		await _wait(2)

	print("— пропуск и настройка")
	await _boot("garage", {"tutorial": false, "first_steps": true})
	check(_slides() != null, "каждая новая игра показывает слайды")
	_slides()._skip.pressed.emit()
	await _wait(3)
	check(gm.hud.modal == null and not gm.menu_paused, "«Пропустить» закрывает экран")
	g.settings["task_intro"] = false
	await _boot("garage", {"tutorial": false, "first_steps": true})
	check(_slides() == null and not gm.menu_paused, "настройка выключена — слайдов нет")
	check(gm.sim.progress.starter.mode == FirstSteps.MODE_ON, "цепочка при этом идёт")
	g.settings["task_intro"] = true

	print("— песочница и старое сохранение")
	await _boot("sandbox", {"tutorial": false, "first_steps": true, "money": 1000000, "map": "large", "start": "garage", "all_open": true})
	check(_slides() == null, "в песочнице слайдов нет")
	check(gm.sim.progress.starter.mode == FirstSteps.MODE_DONE and not gm.sim.progress.starter.active(), "в песочнице цепочки нет")
	var old := Sim.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://tests/saves/save_1.23.json")) as Dictionary)
	await _boot("garage", {"tutorial": false, "first_steps": true}, old)
	check(_slides() == null, "старое сохранение: слайдов нет")
	check(gm.sim.progress.starter.mode == FirstSteps.MODE_DONE and gm.sim.progress.starter.done.has("ship"), "старое сохранение: пройденное отмечено, карточки нет")
	check(_meta(gm.hud.todo, "chain_card") == null, "в списке дел нет карточки")

	print("— обычный тестовый запуск без явного флага: ничего не мешает")
	await _boot("garage", {"tutorial": false})
	check(_slides() == null and gm.sim.progress.starter.mode == FirstSteps.MODE_NONE, "без opts.first_steps тесты не видят ни слайдов, ни цепочки")

	print("— верхняя панель: этап")
	await _boot("garage", {"tutorial": false, "first_steps": true})
	_slides().close()
	await _wait(3)
	var hud := gm.hud
	var sim := gm.sim
	hud._refresh_top()
	check(hud.stage_l.text == "Этап 1 из 6: Гараж", "текст: %s" % hud.stage_l.text)
	check(hud.stage_bar.value == 0.0, "полоска пуста")
	var tip := (hud._chips["goals"] as Control).tooltip_text
	check(tip.contains("Не хватает") and tip.contains("Выполнить 10 заказов") and tip.contains("Оборот") and tip.contains("Мастерская"), "подсказка перечисляет недостающее")
	sim.stats["orders_done"] = 10
	hud._refresh_top()
	check(absf(hud.stage_bar.value - 50.0) < 0.5, "10 заказов: полоска наполовину")
	tip = (hud._chips["goals"] as Control).tooltip_text
	check(not tip.contains("Выполнить 10 заказов") and tip.contains("Оборот"), "подсказка обновилась: остался оборот")
	sim.stats["orders_done"] = 0
	hud._refresh_top()
	# клик открывает «Цели»
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	(hud._chips["goals"] as Control).gui_input.emit(ev)
	await _wait(3)
	check(hud.win != null and hud.win.group == "goals", "щелчок по этапу открывает «Цели»")
	hud.close_window()
	await _wait(2)

	print("— верхняя панель не обрезает и не налезает (1600×900 и 1920×1080, ru и en, этапы 1 и 6)")
	var win := get_window()
	# окно 1920×1080 при растяжке «expand» даёт те же логические 1600×900 (см. снимок p166_topbar); здесь — окно ровно 1600×900
	for sz in [Vector2i(1600, 900)]:
		win.size = sz
		await _wait(6)
		for lang in ["ru", "en"]:
			L.apply(lang)
			for stg in [1, 4, 6]:
				sim.progress.stage = stg
				hud._refresh_top()
				await _wait(4)
				var left: Control = hud.top_left
				var inner: Control = left.get_child(0)
				var need := inner.get_combined_minimum_size().x
				var tag := "%dx%d %s этап %d" % [sz.x, sz.y, lang, stg]
				check(need <= left.size.x + 0.5, "%s: левая часть влезает (%d из %d)" % [tag, int(need), int(left.size.x)])
				var chip: Control = hud._chips["goals"]
				var chip_r := chip.get_global_rect()
				var ok_chip := chip_r.end.x <= left.get_global_rect().end.x + 0.5 and hud.stage_l.size.x + 1.0 >= hud.stage_l.custom_minimum_size.x
				check(ok_chip, "%s: плашка этапа целиком (%s)" % [tag, hud.stage_l.text])
				var prev_end := -1.0
				var seq_ok := true
				for k in ["company", "money", "goals", "rep", "people"]:
					var r: Rect2 = (hud._chips[k] as Control).get_global_rect()
					if r.position.x < prev_end - 0.5:
						seq_ok = false
					prev_end = r.end.x
				check(seq_ok, "%s: плашки слева направо без наложения" % tag)
				var rr: Rect2 = hud.top_right.get_global_rect()
				check(rr.end.x <= float(sz.x) + 0.5 and rr.position.x >= left.get_global_rect().end.x - 0.5, "%s: правая часть (скорость, ?, журнал, меню) на месте" % tag)
	L.apply("ru")
	sim.progress.stage = 1
	hud._refresh_top()

	print("— карточка «Первые шаги»")
	var st := sim.progress.starter
	await _wait(40)
	var card := _meta(hud.todo, "chain_card")
	check(card != null, "в «Что делать» есть карточка")
	if card:
		check(_has_text(card, "ПЕРВЫЕ ШАГИ") and _has_text(card, "0 из 7") and _has_text(card, "Взять новый заказ"), "заголовок, счётчик и первое задание")
		check(_has_text(card, "3 000"), "награда за первое задание видна")
		check(_has_text(card, "Нанять человека") or _has_text(card, "Сделать деталь"), "следующие задания перечислены мелко")
	var cur: Button = _meta(hud.todo, "chain_current") as Button
	if cur:
		cur.pressed.emit()
		await _wait(3)
		check(hud.win != null and hud.win.group == "orders", "щелчок по заданию открывает «Заказы»")
		hud.close_window()
		await _wait(2)
	var o := sim.orders.make_offer()
	sim.orders.list.append(o)
	sim.orders.accept(int(o["id"]), false)
	st.update()
	hud.todo._sig = ""
	hud.todo._refresh()
	await _wait(3)
	card = _meta(hud.todo, "chain_card")
	check(card != null and _has_text(card, "1 из 7") and _has_text(card, "Сделать деталь"), "после заказа: 1 из 7, дальше — деталь и ОТК")
	check(sim.calls.queue.any(func(q: Dictionary) -> bool: return str(q["tag"]) == "first_order"), "советник оставил реплику")
	g.settings["first_steps"] = true
	st.enabled = false
	hud.todo._sig = ""
	hud.todo._refresh()
	await _wait(2)
	check(_meta(hud.todo, "chain_card") == null, "настройка выключена — карточка скрыта")
	st.enabled = true
	hud.todo._sig = ""
	for s2: Dictionary in FirstSteps.STEPS:
		if not st.done.has(str(s2["id"])):
			st.done.append(str(s2["id"]))
	st.mode = FirstSteps.MODE_DONE
	hud.todo._refresh()
	await _wait(2)
	check(_meta(hud.todo, "chain_card") == null, "цепочка пройдена — карточка ушла")

	print("— обучение: слайды вместо вступительной карточки")
	await _boot("garage", {"tutorial": true, "first_steps": true})
	check(_slides() != null and not gm.hud.tutorial.visible, "обучение ждёт, пока идут слайды")
	_slides()._skip.pressed.emit()
	await _wait(3)
	check(gm.sim.progress.tutorial == 1 and gm.hud.tutorial.visible, "после слайдов обучение начинается с первого шага, без повтора вступления")
	check(_meta(gm.hud.todo, "chain_card") == null, "пока идёт обучение, карточка ждёт")

	print("РЕЗУЛЬТАТ: " + ("ВСЁ ВЕРНО" if fails.is_empty() else "ОШИБКИ: %d" % fails.size()))
	get_tree().quit(0 if fails.is_empty() else 1)
