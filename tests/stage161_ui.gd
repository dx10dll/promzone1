extends Node
## Тест 1.61: окно «Люди → Охрана труда» — одна карточка с тремя уровнями, старых кнопок нет; «Карьера» держит ПТУ и класс.
## godot --headless --path . --audio-driver Dummy res://tests/stage161_ui.tscn

var fails: Array[String] = []


func check(cond: bool, what: String) -> void:
	print(("  ✓ " if cond else "  ✗ ") + what)
	if not cond:
		fails.append(what)


func _wait(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _texts(root: Node, cls: String) -> Array[String]:
	var out: Array[String] = []
	for b: Node in root.find_children("*", cls, true, false):
		if not b.is_queued_for_deletion():
			out.append(str(b.get("text")))
	return out


func _ready() -> void:
	var Game: Node = get_node("/root/Game")
	Game.pending = "new"
	Game.pending_scn = "field"
	Game.pending_profile = "mech"
	Game.pending_opts = {"tutorial": false}
	Game.pending_seed = 1610
	Game.settings["tutorial_done"] = true
	var gm: GameMain = load("res://scenes/game.tscn").instantiate()
	add_child(gm)
	await _wait(30)
	var hud := gm.hud
	var sim := gm.sim
	sim.progress.all_open = true

	print("— карточка «Охрана труда»")
	hud.open_window("people:safety")
	await _wait(6)
	var win := hud.win
	check(win != null and win.tab == "safety", "окно открыто на разделе «Охрана труда»")
	var btns := _texts(win.content, "Button")
	check(btns.count("Выбрать") == 3, "три уровня — три кнопки «Выбрать» (%d)" % btns.count("Выбрать"))
	var labs := _texts(win.content, "Label")
	check(labs.has("Минимум") and labs.has("По закону") and labs.has("Образцово"), "названия уровней на карточке")
	check(labs.any(func(t: String) -> bool: return t.begins_with("бесплатно")), "у «Минимума» цена «бесплатно»")
	check(labs.any(func(t: String) -> bool: return t.contains("в месяц") and t.contains("₽")), "у остальных — цена в месяц")
	for old in ["Спецоценка (СОУТ)", "Молоко за вредность", "Выдавать молоко", "Купить 5", "Все заново"]:
		check(not labs.has(old) and not btns.any(func(t: String) -> bool: return t.begins_with(old)) and not _texts(win.content, "CheckBox").has(old), "старого элемента «%s» нет" % old)
	check(win.content.find_children("*", "CheckBox", true, false).is_empty(), "переключателей-галочек нет")
	for b: Node in win.content.find_children("*", "Button", true, false):
		if (b as Button).text == "Выбрать" and not (b as Button).disabled:
			(b as Button).pressed.emit()
			break
	await _wait(6)
	check(sim.safety.level == 1, "кнопка на карточке выбирает уровень (%d)" % sim.safety.level)
	await _wait(4)
	labs = _texts(hud.win.content, "Label")
	check(labs.has("выбран"), "выбранный уровень помечен")
	sim.safety.set_level(2)
	await _wait(6)
	check(sim.eng.milk_on, "уровни держат старый флаг молока")

	print("— «Карьера»: класс и практиканты, без инструктажа")
	hud.open_window("people:train")
	await _wait(6)
	win = hud.win
	labs = _texts(win.content, "Label")
	check(labs.has("Практиканты ПТУ") and labs.has("Учебный класс"), "практиканты и класс в «Карьере»")
	check(not labs.has("Инструктаж по ОТ"), "отдельной карточки инструктажа нет")
	var secs: Array[String] = []
	for s: Array in GameWindow.GROUPS["people"]["secs"]:
		secs.append(str(s[1]))
	check(secs.has("Карьера") and not secs.has("Обучение"), "раздел называется «Карьера»")

	print("— английский")
	L.apply("en")
	check(tr("Минимум") == "Minimum" and tr("По закону") == "By the law" and tr("Образцово") == "Exemplary", "уровни переведены")
	check(tr("Что сейчас") == "Right now" and tr("выбран") == "selected", "карточка переведена")
	L.apply("ru")

	print("РЕЗУЛЬТАТ: " + ("ВСЁ ВЕРНО" if fails.is_empty() else "ОШИБКИ: %d" % fails.size()))
	get_tree().quit(0 if fails.is_empty() else 1)
