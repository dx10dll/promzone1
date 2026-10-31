extends Node
## Тест 1.62: окна — «Заказы → Рынок» одна карточка (группы со спросом и главным конкурентом, подробности по щелчку,
## отдельного раздела «Конкуренты» нет), «Финансы → Страхование» одна галочка, «Гранты» с заявками.
## godot --headless --path . --audio-driver Dummy res://tests/stage162_ui.tscn

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


func _click_row(root: Node, contains: String) -> bool:
	for p: Node in root.find_children("*", "PanelContainer", true, false):
		if p.is_queued_for_deletion() or (p as Control).mouse_filter != Control.MOUSE_FILTER_STOP or p.get_signal_connection_list("gui_input").is_empty():
			continue
		for l: Node in p.find_children("*", "Label", true, false):
			if str(l.get("text")).contains(contains):
				var ev := InputEventMouseButton.new()
				ev.button_index = MOUSE_BUTTON_LEFT
				ev.pressed = true
				p.gui_input.emit(ev)
				return true
	return false


func _ready() -> void:
	var Game: Node = get_node("/root/Game")
	Game.pending = "new"
	Game.pending_scn = "field"
	Game.pending_profile = "mech"
	Game.pending_opts = {"tutorial": false}
	Game.pending_seed = 1620
	Game.settings["tutorial_done"] = true
	var gm: GameMain = load("res://scenes/game.tscn").instantiate()
	add_child(gm)
	await _wait(30)
	var hud := gm.hud
	var sim := gm.sim
	sim.story.enabled = false
	sim.progress.all_open = true
	sim.office.all_depts = true

	print("— «Рынок»: одна карточка")
	var secs: Array[String] = []
	for s: Array in GameWindow.GROUPS["orders"]["secs"]:
		secs.append(str(s[1]))
	check(secs.has("Рынок") and not secs.has("Конкуренты"), "в «Заказах» есть «Рынок», раздела «Конкуренты» нет: %s" % str(secs))
	GameWindow.mk_open.clear()
	hud.open_window("orders:market")
	await _wait(6)
	var win := hud.win
	var rows := 0
	var labs := _texts(win.content, "Label")
	for t in labs:
		if t == "спрос растёт" or t == "спрос падает" or t == "спрос ровный":
			rows += 1
	check(rows >= 3 and rows <= 4, "в карточке 3–4 группы со спросом: %d" % rows)
	check(labs.any(func(t: String) -> bool: return t.contains("наша доля рынка")), "доля рынка в шапке карточки")
	check(labs.any(func(t: String) -> bool: return t.contains("▲") or t.contains("▼") or t.contains("►")), "у групп стрелки")
	check(not labs.has("Изделие и маршрут"), "подробности скрыты, пока не щёлкнули")
	check(_click_row(win.content, "изделий:"), "щелчок по группе")
	await _wait(6)
	labs = _texts(hud.win.content, "Label")
	check(labs.has("ИЗДЕЛИЕ И МАРШРУТ") or labs.has("Изделие и маршрут") or labs.any(func(t: String) -> bool: return t.contains("Главный конкурент")), "группа раскрылась: изделия и главный конкурент")
	check(not _texts(hud.win.content, "Button").any(func(t: String) -> bool: return t.contains("Демпинг")), "ценовая политика скрыта до раскрытия «Цены, соседние заводы и директора»")
	for b: Node in hud.win.content.find_children("*", "Button", true, false):
		if str(b.get("text")).begins_with("Цены, соседние заводы"):
			(b as Button).pressed.emit()
			break
	await _wait(8)
	labs = _texts(hud.win.content, "Label")
	check(labs.has("Директора соседних заводов") or labs.any(func(t: String) -> bool: return t.begins_with("Отношение к нам")), "внизу раскрылись соседи и их директора")
	hud.open_window("orders:compet")
	await _wait(6)
	check(hud.win.tab == "market" or hud.win.sec == "market", "старая ссылка «compet» ведёт на «Рынок»")

	print("— «Страхование»: одна галочка")
	hud.open_window("finance:insurance")
	await _wait(6)
	win = hud.win
	var cbs := _texts(win.content, "CheckBox")
	check(cbs.size() == 1 and cbs[0] == "Застраховать всё", "одна галочка «Застраховать всё»")
	check(_texts(win.content, "Label").any(func(t: String) -> bool: return t.contains("в месяц") and t.contains("₽")), "цена в месяц на карточке")
	check(not _texts(win.content, "Button").any(func(t: String) -> bool: return t == "Оформить" or t.begins_with("Расторгнуть")), "кнопок трёх полисов нет")
	sim.dev.done.append("fin3")
	var cb: CheckBox = win.content.find_children("*", "CheckBox", true, false)[0]
	cb.button_pressed = true
	await _wait(6)
	check(sim.market.insure_all and sim.market.insurance.size() == 3, "галочка включает страховку на всё")
	cb = hud.win.content.find_children("*", "CheckBox", true, false)[0]
	check(cb.button_pressed, "галочка отражает состояние")
	cb.button_pressed = false
	await _wait(6)
	check(not sim.market.insure_all, "снять галочку — расторгнуть")

	print("— «Гранты»: заявки и памятка")
	sim.grants.apply("canteen")
	hud.open_window("finance:grants")
	await _wait(6)
	labs = _texts(hud.win.content, "Label")
	check(labs.any(func(t: String) -> bool: return t.to_lower() == "заявки на рассмотрении"), "заявка на рассмотрении видна (заявок %d)" % sim.grants.pending.size())
	check(not _texts(hud.win.content, "Button").any(func(t: String) -> bool: return t == "Оформить"), "кнопки «Оформить» нет — только по памятке")
	sim.story.enabled = true
	sim.grants.next_offer = 0
	sim.grants.pending.clear()
	sim.grants._maybe_offer()
	await _wait(10)
	check(hud.modal != null or not sim.story.get_letter_by_ev("grant_offer").is_empty(), "памятка фонда пришла как карточка решения")

	print("— английский")
	L.apply("en")
	check(tr("Застраховать всё") == "Insure everything" and tr("Пропустить") == "Skip", "страховка и заявка переведены")
	check(tr("спрос растёт") == "demand rising" and tr("спрос падает") == "demand falling" and tr("спрос ровный") == "demand steady", "тренды переведены")
	L.apply("ru")

	print("РЕЗУЛЬТАТ: " + ("ВСЁ ВЕРНО" if fails.is_empty() else "ОШИБКИ: %d" % fails.size()))
	get_tree().quit(0 if fails.is_empty() else 1)
