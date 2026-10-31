extends Node
## Тест 1.63: окна — «Заказы → Рынок»: у группы закрытые изделия с условиями «откроется: …»;
## «Управление → ISO 9001»: одна карточка-чек-лист из 6 условий, «Показать», «Что делать» при 4+ условиях.
## godot --headless --path . --audio-driver Dummy res://tests/stage163_ui.tscn

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
	Game.pending_scn = "garage"
	Game.pending_profile = "mech"
	Game.pending_opts = {"tutorial": false}
	Game.pending_seed = 1630
	Game.settings["tutorial_done"] = true
	var gm: GameMain = load("res://scenes/game.tscn").instantiate()
	add_child(gm)
	await _wait(30)
	var hud := gm.hud
	var sim := gm.sim
	sim.story.enabled = false

	print("— «Рынок»: закрытые изделия")
	GameWindow.mk_open.clear()
	hud.open_window("orders:market")
	await _wait(6)
	check(_texts(hud.win.content, "Label").any(func(t: String) -> bool: return t.contains("закрыто:")), "в шапке группы счётчик «закрыто: N»")
	check(_click_row(hud.win.content, "изделий:"), "раскрыли группу")
	await _wait(6)
	var labs := _texts(hud.win.content, "Label")
	check(labs.any(func(t: String) -> bool: return t.to_lower() == "откроются позже"), "подпись «Откроются позже»")
	check(labs.any(func(t: String) -> bool: return t.begins_with("откроется: ") and t.contains("этап")), "у закрытого изделия условие: " + str(labs.filter(func(t: String) -> bool: return t.begins_with("откроется"))))
	check(labs.has("Палец") and labs.has("Вал"), "открытое и закрытое изделие в одной группе")

	print("— «ISO 9001»: чек-лист")
	sim.office.all_depts = true
	hud.open_window("office:iso")
	await _wait(6)
	var win := hud.win
	var card: Node = win.content.find_child("IsoChecklist", true, false)
	check(card != null, "карточка-чек-лист на месте")
	var ls := _texts(card, "Label")
	check(ls.filter(func(t: String) -> bool: return t == "✓" or t == "✗").size() == 6, "шесть строк ✓/✗")
	check(ls.any(func(t: String) -> bool: return t.begins_with("сейчас: ") and t.contains("нужно:")), "значение против требования")
	var shows := _texts(card, "Button").filter(func(t: String) -> bool: return t == "Показать")
	check(shows.size() == 6 - sim.market.iso_ready() and shows.size() >= 1, "кнопки «Показать» у невыполненных: %d" % shows.size())
	check(ls.any(func(t: String) -> bool: return t.contains("Чек-лист ISO 9001: выполнено")), "заголовок со счётом")
	var btn: Button = card.find_child("Show_tb", true, false)
	btn.pressed.emit()
	await _wait(6)
	check(hud.win != null and hud.win.group == "people" and hud.win.sec == "safety", "«Показать» у инструктажа ведёт в «Люди → Охрана труда»")

	print("— «Что делать»")
	sim.training.tb_day = sim.day()
	sim.eng.sout_ids = sim.eng.workplaces().map(func(t: Thing) -> int: return t.id)
	sim.eng._finish_sout()
	sim.progress.rating["quality"] = 0.9
	sim.market.last_reclam = -100
	check(sim.market.iso_ready() >= 4, "условий выполнено: %d" % sim.market.iso_ready())
	hud.close_window()
	hud.todo.visible = true
	await _wait(10)
	var tl := _texts(hud.todo, "Label")
	check(tl.any(func(t: String) -> bool: return t.begins_with("ISO 9001: выполнено")), "в «Что делать» строка ISO 9001")

	print("РЕЗУЛЬТАТ: " + ("ВСЁ ВЕРНО" if fails.is_empty() else "ОШИБКИ: %d" % fails.size()))
	get_tree().quit(0 if fails.is_empty() else 1)
