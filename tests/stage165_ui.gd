extends Node
## Тест 1.65 (окна): слитые разделы — «Динамика» в «Финансах», «Журнал» с фильтром, «Простой» колонкой в «Станках», склад оборудования внутри «Склада и логистики»,
## радио и кот в «Обзоре» города, «Рейтинг» внутри «Этапа роста», «График смены» внутри «Бригад»; звук «Окружение/Интерфейс» под кнопкой.
## godot --path . --audio-driver Dummy res://tests/stage165_ui.tscn  (под xvfb)

var fails: Array[String] = []


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
		if t.to_lower().contains(part.to_lower()):
			return true
	return false


func _open(hud: Hud, key: String) -> void:
	hud.close_window()
	hud.open_window(key)
	await _wait(4)


func _ready() -> void:
	var gm_game: Node = get_node("/root/Game")
	gm_game.pending = "new"
	gm_game.pending_scn = "garage"
	gm_game.pending_profile = "mech"
	gm_game.pending_opts = {"tutorial": false}
	gm_game.pending_seed = 1650
	gm_game.settings["tutorial_done"] = true
	var gm: GameMain = load("res://scenes/game.tscn").instantiate()
	add_child(gm)
	await _wait(30)
	var hud := gm.hud
	var sim := gm.sim
	sim.progress.all_open = true

	print("— разделы окон (GROUPS)")
	var G := GameWindow.GROUPS
	var fin: Array = []
	for e: Array in G["finance"]["secs"]:
		fin.append(str(e[0]))
	check(fin.has("dyn") and not fin.has("charts") and not fin.has("stats") and not fin.has("weeks"), "Финансы: «Динамика» вместо трёх вкладок %s" % str(fin))
	var evk: Array = []
	for e2: Array in G["events"]["secs"]:
		evk.append(str(e2[0]))
	check(not evk.has("hist") and not evk.has("cal") and evk.has("log") and evk.has("insp"), "События: нет «Хроники» и «Календаря» %s" % str(evk))
	var prod: Array = []
	for e3: Array in G["prod"]["secs"]:
		prod.append(str(e3[0]))
	check(not prod.has("stall") and not prod.has("stash") and prod.has("machines") and prod.has("logi"), "Производство: нет «Простоя» и «Склада оборудования» %s" % str(prod))
	var town: Array = []
	for e4: Array in G["town"]["secs"]:
		town.append(str(e4[0]))
	check(not town.has("cat") and not town.has("radio") and town.has("overview"), "Город: нет «Кота» и «Радио» %s" % str(town))
	var goals: Array = []
	for e5: Array in G["goals"]["secs"]:
		goals.append(str(e5[0]))
	check(not goals.has("rating") and goals.has("stage"), "Цели: «Рейтинг» слит с «Этапом роста» %s" % str(goals))
	var ppl: Array = []
	for e6: Array in G["people"]["secs"]:
		ppl.append(str(e6[0]))
	check(not ppl.has("sched") and ppl.has("brig") and ppl.has("sec"), "Люди: «График смены» слит с «Бригадами» %s" % str(ppl))

	print("— Финансы → Динамика")
	await _open(hud, "finance:charts")
	check(hud.win != null and hud.win.sec == "dyn" and hud.win.sub == "chart", "старый ключ «charts» открывает «Динамику» в режиме графика")
	check(not hud.win.find_children("*", "ChartView", true, false).is_empty(), "в режиме «График» есть графики")
	hud.win.select_tab("stats")
	await _wait(3)
	check(hud.win.sec == "dyn" and hud.win.sub == "day", "«stats» → режим «Сутки»")
	hud.win.select_tab("weeks")
	await _wait(3)
	check(hud.win.sec == "dyn" and hud.win.sub == "week", "«weeks» → режим «Неделя»")
	check(_has_text(hud.win.content, "Неделя") or _has_text(hud.win.content, "бухгалтер"), "переключатель режимов или подсказка видны")

	print("— События → Журнал с фильтром")
	sim.notify("Проверочное событие журнала", Sim.LVL_INFO)
	sim.story.info("Проверка хроники", "Подробный текст события.", "letter", Sim.LVL_INFO)
	await _open(hud, "events:hist")
	check(hud.win.sec == "log" and hud.win.sub == "events", "«hist» открывает «Журнал» с фильтром «События»")
	check(_has_text(hud.win.content, "Проверка хроники"), "в фильтре «События» видна хроника")
	hud.win.sub = "all"
	hud.win.rebuild(true)
	check(_has_text(hud.win.content, "Проверочное событие журнала"), "в фильтре «Все» видно уведомление")
	hud.win.sub = "money"
	hud.win.rebuild(true)
	check(hud.win.sec == "log", "фильтр «Деньги» строится")
	await _open(hud, "events:cal")
	check(hud.win.sec == "insp", "«cal» ведёт в «Проверки»")

	print("— Производство: простой — колонкой; склад оборудования внутри логистики")
	await _open(hud, "prod:stall")
	check(hud.win.sec == "machines" and not hud.win._badges.has("stall"), "«stall» ведёт в «Станки», отдельного значка нет")
	await _open(hud, "prod:stash")
	check(hud.win.sec == "logi" and _has_text(hud.win.content, "Склад оборудования"), "«stash» ведёт в «Склад и логистику», карточка склада оборудования внизу")

	print("— Город: радио и кот в «Обзоре»")
	await _open(hud, "town:radio")
	check(hud.win.sec == "overview" and _has_text(hud.win.content, "Заводская волна"), "радио — карточка в «Обзоре»")
	sim.town.cat = Cat.new(sim)
	sim.town.cat.pos = Vector2(10.5, 10.5)
	await _open(hud, "town:cat")
	hud.win.rebuild(true)
	check(hud.win.sec == "overview" and _has_text(hud.win.content, "Заводской кот"), "кот — карточка в «Обзоре»")

	print("— Цели: рейтинг внутри этапа роста")
	await _open(hud, "goals:rating")
	check(hud.win.sec == "stage" and _has_text(hud.win.content, "Рейтинг завода"), "«Рейтинг» внутри «Этапа роста»")

	print("— Люди: график смены внутри бригад")
	await _open(hud, "people:sched")
	check(hud.win.sec == "brig", "«sched» ведёт в «Бригады и график смены»")

	print("— настройки: звук")
	check(SettingsUI.HIDDEN_VOLUMES == ["vol_env", "vol_ui"], "ползунки «Окружение» и «Интерфейс» спрятаны")
	var box := VBoxContainer.new()
	add_child(box)
	SettingsUI.build(box)
	var more: Control = box.find_child("MoreVolumes", true, false)
	check(more != null and not more.visible, "спрятанные ползунки под кнопкой, свёрнуты")
	var bt: Button = box.find_child("MoreVolumesBtn", true, false)
	check(bt != null, "кнопка «Звук ▸» есть")
	if bt:
		bt.pressed.emit()
		check(more.visible, "кнопка раскрывает ползунки")
	check(box.find_children("*", "HSlider", true, false).size() == 5, "все пять ползунков на месте")
	box.queue_free()

	print("— английский")
	L.apply("en")
	check(tr("Динамика") == "Trends" and tr("Рейтинг завода") == "Plant rating" and tr("Бригады и график смены") == "Crews & shift schedule", "переводы разделов на месте")
	L.apply("ru")

	print("РЕЗУЛЬТАТ: " + ("ВСЁ ВЕРНО" if fails.is_empty() else "ОШИБКИ: %d" % fails.size()))
	get_tree().quit(0 if fails.is_empty() else 1)
