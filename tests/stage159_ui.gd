extends Node
## Тест 1.59 «Разгрузка интерфейса»: пять слоёв карты с подвкладками, совет в «Что делать» не дублируется уведомлением,
## «План» (калька) — кнопка внутри «Стройки», а не отдельное меню нижней панели.
## godot --headless --path . --audio-driver Dummy res://tests/stage159_ui.tscn

var fails: Array[String] = []


func check(cond: bool, what: String) -> void:
	print(("  ✓ " if cond else "  ✗ ") + what)
	if not cond:
		fails.append(what)


func _wait(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _toasts(hud: Hud) -> int:
	return hud.toasts.get_child_count()


func _ready() -> void:
	var Game: Node = get_node("/root/Game")
	Game.pending = "new"
	Game.pending_scn = "field"
	Game.pending_profile = "mech"
	Game.pending_opts = {"tutorial": false}
	Game.pending_seed = 1590
	Game.settings["tutorial_done"] = true
	var gm: GameMain = load("res://scenes/game.tscn").instantiate()
	add_child(gm)
	await _wait(30)
	var hud := gm.hud
	var sim := gm.sim
	var tool := gm.tool

	print("— слои карты")
	check(hud.ov_btns.size() == 5, "на панели слоёв 5 кнопок (%d)" % hud.ov_btns.size())
	check(hud.ov_btns.keys() == ["rooms", "nets", "load", "logistics", "dirt"], "Зоны, Сети, Загрузка, Логистика, Чистота")
	check(not hud.sub_ov_panel.visible, "подвкладок нет, пока слой не включён")
	hud.on_layer_button("nets")
	await _wait(3)
	check(gm.overlay.mode == "nets" and hud.sub_ov_panel.visible, "«Сети» включены, подвкладки видны")
	check(hud.sub_ov_btns.keys() == ["nets", "light", "temp"], "у «Сетей»: Сети, Свет, Температура")
	hud.pick_sublayer("light")
	await _wait(3)
	check(gm.overlay.mode == "light", "подвкладка «Свет» переключает оверлей")
	check((hud.ov_btns["nets"] as Button).button_pressed, "кнопка «Сети» горит и на подвкладке")
	hud.pick_sublayer("temp")
	await _wait(3)
	check(gm.overlay.mode == "temp", "подвкладка «Температура»")
	hud.on_layer_button("nets")
	await _wait(3)
	check(gm.overlay.mode == "" and not hud.sub_ov_panel.visible, "щелчок по горящему слою выключает его вместе с подвкладками")
	hud.on_layer_button("logistics")
	await _wait(3)
	check(tool.mode == "logistics" and gm.overlay.mode == "logistics", "«Логистика»: первая подвкладка — линии")
	check(hud.sub_ov_btns.keys() == ["logistics", "traffic", "crew"], "у «Логистики»: Линии, Потоки людей, Бригады")
	hud.pick_sublayer("traffic")
	await _wait(3)
	check(gm.overlay.mode == "traffic" and tool.mode == "select", "«Потоки людей» — оверлей, инструмент линий снят")
	check((hud.ov_btns["logistics"] as Button).button_pressed and hud.sub_ov_panel.visible, "«Логистика» горит, подвкладки на месте")
	hud.pick_sublayer("crew")
	await _wait(3)
	check(gm.overlay.mode == "crew", "«Бригады»")
	hud.pick_sublayer("logistics")
	await _wait(3)
	check(tool.mode == "logistics" and gm.overlay.mode == "logistics", "обратно в линии логистики")
	hud.on_layer_button("logistics")
	await _wait(3)
	check(tool.mode == "select" and gm.overlay.mode == "", "повторный щелчок выключает логистику")
	hud.on_layer_button("dirt")
	await _wait(3)
	check(gm.overlay.mode == "dirt" and not hud.sub_ov_panel.visible, "«Чистота» — без подвкладок")
	hud.on_layer_button("dirt")
	await _wait(3)

	print("— уведомление и «Что делать»")
	sim.money = 50000.0
	await _wait(3)
	var before := _toasts(hud)
	var txt := "Кассовый разрыв! Денег нет — срочно выполняйте заказы."
	hud.on_notified(txt, Sim.LVL_BAD, Vector2i(-1, -1))
	check(_toasts(hud) == before + 1, "без совета в списке уведомление приходит")
	sim.money = -500.0
	check(hud.todo.covers(txt), "совет «Кассовый разрыв» висит в «Что делать»")
	var log0 := hud.unread_log
	var b2 := _toasts(hud)
	hud.on_notified(txt + " ", Sim.LVL_BAD, Vector2i(-1, -1))
	check(_toasts(hud) == b2 and hud.unread_log == log0 + 1, "то же самое отдельным уведомлением не дублируется")
	hud.on_notified("Станок сломался: токарный", Sim.LVL_BAD, Vector2i(-1, -1))
	check(_toasts(hud) == b2 + 1, "другое уведомление проходит")

	print("— «План» и «Стройка»")
	check(not hud.bottom_btns.has("plan"), "в нижней панели нет «План»")
	for k: String in hud.bottom_btns.keys():
		check((hud.bottom_btns[k] as Button).text != "План", "кнопка %s не называется «План»" % k)
	hud.bottom_btns["build"].pressed.emit()
	await _wait(5)
	var cq: Button = hud.sub_root.find_child("CalqueBtn", true, false)
	check(cq != null, "в меню «Стройка» есть кнопка «Калька (план)»")
	check(not tool.plan_mode, "калька выключена")
	if cq != null:
		cq.pressed.emit()
		await _wait(5)
		check(tool.plan_mode and hud.sub_panel.visible, "кнопка включает планировку")
		check(hud.bottom_btns["build"].button_pressed, "горит «Стройка»")
		cq = hud.sub_root.find_child("CalqueBtn", true, false)
		check(cq != null and cq.button_pressed, "кнопка в меню горит в плане")
		cq.pressed.emit()
		await _wait(5)
		check(not tool.plan_mode, "та же кнопка выключает планировку")

	print("РЕЗУЛЬТАТ: " + ("ВСЁ ВЕРНО" if fails.is_empty() else "ОШИБКИ: " + str(fails)))
	get_tree().quit(0 if fails.is_empty() else 1)
