extends Node
## 1.39: интро и английский язык (первый срез перевода).
## 1) В тестах интро не запускается (Game.is_test_run, IntroPlayer.should_play), язык тестов — русский.
## 2) Ролики на месте и грузятся (VideoStreamTheora), IntroPlayer пропускается клавишей и сообщает done.
## 3) Переключаем язык на английский выбором в настройках: в главном меню, настройках, окне «Новая игра»
##    (все сценарии и профили, шаг 2 — «ваш завод»), «Создать рабочего», в верхней и нижней панели игры
##    (с подсказками), в меню паузы, настройках и сохранении — ни одной надписи с кириллицей. Ничего не вылезает
##    за экран: панели не шире окна, пункты меню умещаются.
## godot --headless --path . --audio-driver Dummy res://tests/stage140_i18n_test.tscn

var fails: Array[String] = []
var _cfg_backup := PackedByteArray()
var _had_cfg := false


func check(cond: bool, what: String) -> void:
	print(("  ✓ " if cond else "  ✗ ") + what)
	if not cond:
		fails.append(what)


func _wait(n: int) -> void:
	for i in n:
		await get_tree().process_frame


## Что видно на экране под узлом root: [путь, текст] для надписей, кнопок, флажков, списков и подсказок.
## Поля ввода (имена людей и завода вводит игрок по-русски) и выбор языка (там «Русский» нарочно) — не проверяем.
func _texts(root: Node, tips: bool = true) -> Array:
	var out: Array = []
	for n: Node in [root] + root.find_children("*", "Control", true, false):
		var c := n as Control
		if c == null or not c.is_visible_in_tree() or c is LineEdit:
			continue
		if c.name == "LangSelect" or (c is Label and (c as Label).auto_translate_mode == Node.AUTO_TRANSLATE_MODE_DISABLED):
			continue
		if c is Label:
			out.append([c, c.atr((c as Label).text)])
		elif c is Button:
			out.append([c, c.atr((c as Button).text)])
			if c is OptionButton:
				var ob := c as OptionButton
				for i in ob.item_count:
					out.append([c, ob.atr(ob.get_item_text(i))])
		if c.get_script() != null and c.get("title") is String and c.get("hint") is String:   # пункт главного меню (рисует сам)
			out.append([c, str(c.get("title"))])
			if not bool(c.get("primary")):   # у «Продолжить» подпись — название завода из сохранения
				out.append([c, str(c.get("hint"))])
		if tips and c.tooltip_text != "":
			out.append([c, c.atr(c.tooltip_text)])
	return out


func _no_cyr(root: Node, what: String, tips: bool = true) -> void:
	var bad: Array[String] = []
	var n := 0
	for e: Array in _texts(root, tips):
		n += 1
		if L.has_cyr(str(e[1])):
			bad.append("«%s» (%s)" % [str(e[1]).replace("\n", " ").left(70), (e[0] as Node).get_class()])
	check(n > 0 and bad.is_empty(), "%s: %d надписей, без кириллицы%s" % [what, n, "" if bad.is_empty() else ": " + "; ".join(bad.slice(0, 8)) + (" …ещё %d" % (bad.size() - 8) if bad.size() > 8 else "")])


## Ничего не шире окна: минимальная ширина корневой панели и правый край надписей.
func _fits(c: Control, what: String) -> void:
	var vw := c.get_viewport_rect().size.x
	var mw := c.get_combined_minimum_size().x
	check(mw <= vw + 0.5 and c.get_global_rect().end.x <= vw + 1.0, "%s умещается по ширине: %.0f из %.0f px" % [what, maxf(mw, c.get_global_rect().end.x), vw])


func _ready() -> void:
	get_tree().create_timer(600.0).timeout.connect(func() -> void:
		print("РЕЗУЛЬТАТ: ОШИБКИ: тест не уложился во время")
		get_tree().quit(2))
	_had_cfg = FileAccess.file_exists(Game.SETTINGS_PATH)
	if _had_cfg:
		_cfg_backup = FileAccess.get_file_as_bytes(Game.SETTINGS_PATH)
	CustomWorkers.path = "user://test140_custom_workers.json"
	if FileAccess.file_exists(CustomWorkers.path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(CustomWorkers.path))

	print("— интро: в тестах не идёт")
	check(Game.is_test_run(), "запуск из tests/ — служебный (без интро)")
	check(L.lang() == "ru", "язык тестов — русский: %s" % TranslationServer.get_locale())
	Game.settings["intro"] = true
	var mm: Node = load("res://scenes/main_menu.tscn").instantiate()
	add_child(mm)
	await _wait(5)
	check(mm.get("intro") == null and mm.find_children("*", "IntroPlayer", true, false).is_empty(), "главное меню в тесте — без интро")
	check(not IntroPlayer.should_play(mm), "IntroPlayer.should_play — нет")
	check(Game.intro_seen, "отмечено: интро в этом запуске уже было (в меню из игры — без ролика)")
	for lg in ["ru", "en"]:
		var st: Variant = load(IntroPlayer.path_for(lg))
		check(st is VideoStreamTheora, "ролик %s: %s" % [lg, IntroPlayer.path_for(lg)])
	var ip := IntroPlayer.new()
	var got := [false]
	ip.done.connect(func() -> void: got[0] = true)
	add_child(ip)
	await _wait(3)
	check(ip.player != null and ip.player.stream != null and ip.player.bus == "Music", "плеер интро: ролик загружен, звук — через шину «Музыка»")
	var ke := InputEventKey.new()
	ke.keycode = KEY_ESCAPE
	ke.pressed = true
	Input.parse_input_event(ke)
	await _wait(4)
	check(bool(got[0]), "Esc пропускает интро (done)")
	await get_tree().create_timer(0.6).timeout
	check(not is_instance_valid(ip), "после пропуска интро гаснет и убирается")

	print("— выбор языка в настройках → английский")
	mm.call("_show_settings")
	await _wait(2)
	var sub: Control = mm.get("sub")
	var sel := sub.find_child("LangSelect", true, false) as OptionButton
	check(sel != null and sel.item_count == 2 and sel.get_item_text(0) == "Русский" and sel.get_item_text(1) == "English", "в настройках есть «Язык / Language: Русский / English»")
	sel.select(1)
	sel.item_selected.emit(1)
	await _wait(3)
	check(L.lang() == "en" and str(Game.settings.get("lang", "")) == "en", "язык — английский, сохранён в настройках")
	var cf := ConfigFile.new()
	check(cf.load(Game.SETTINGS_PATH) == OK and str(cf.get_value("game", "lang", "")) == "en", "settings.cfg: lang = en")
	sub = mm.get("sub")
	check(sub != null and is_instance_valid(sub), "окно настроек снова открыто после смены языка")
	_no_cyr(sub, "настройки")
	var cbi: CheckBox = null
	for c: Node in sub.find_children("*", "CheckBox", true, false):
		if (c as CheckBox).atr((c as CheckBox).text) == "Show intro":
			cbi = c
	check(cbi != null and cbi.button_pressed, "флажок «Show intro» есть и включён")
	_no_cyr(mm.get("ui"), "главное меню с настройками")
	(mm.get("sub") as Control).queue_free()
	mm.set("sub", null)
	await _wait(2)
	_no_cyr(mm.get("ui"), "главное меню")
	var box: VBoxContainer = mm.get("menu_box")
	var tight: Array[String] = []
	for it: Control in box.get_children():
		var w := UITheme.f_semi.get_string_size(str(it.get("title")), HORIZONTAL_ALIGNMENT_LEFT, -1, 19).x
		if w + 70.0 > it.size.x:
			tight.append(str(it.get("title")))
	check(tight.is_empty(), "пункты меню умещаются %s" % str(tight))
	await _wait(2)
	for card: Control in mm.get("_cards"):
		_fits(card, "карточка меню «%s»" % card.atr(str((card.find_children("*", "Label", true, false)[0] as Label).text)))

	print("— «Новая игра»")
	mm.call("_show_new_game")
	await _wait(2)
	var ng: Dictionary = mm.get("ng")
	for sk: String in Defs.scenarios.keys():
		ng["scn"] = sk
		var al: Array = Defs.scenarios[sk].get("profiles", [])
		var profs: Array = al if not al.is_empty() else Defs.profiles.keys()
		for pk: Variant in profs:
			ng["profile"] = str(pk)
			mm.call("_fill_new_game")
			await _wait(1)
			_no_cyr(mm.get("ng_root"), "новая игра · %s · %s" % [sk, str(pk)])
	_fits(mm.get("ng_root"), "окно «Новая игра»")
	for md: String in Story.MODES:
		ng["story"] = md
		mm.call("_fill_new_game")
		await _wait(1)
		_no_cyr(mm.get("ng_root"), "новая игра · сложность %s" % md)
	ng["page"] = 2
	mm.call("_fill_new_game")
	await _wait(2)
	_no_cyr(mm.get("ng_root"), "новая игра · шаг 2 «ваш завод»")
	(mm.get("ng_root") as Control).queue_free()
	mm.set("ng_root", null)
	await _wait(2)

	print("— «Создать рабочего»")
	mm.call("_show_custom")
	await _wait(6)
	var ed: Control = mm.get("ng_root")
	_no_cyr(ed, "«Создать рабочего» (новая запись)")
	_fits(ed, "«Создать рабочего»")
	for i in 3:
		ed.call("_save")
		await _wait(2)
		ed.call("_new_draft")
		await _wait(3)
	ed.call("_open", 0)
	await _wait(3)
	_no_cyr(ed, "«Создать рабочего» (запись из списка)")
	ed.call("close")
	await _wait(3)
	mm.queue_free()
	await _wait(3)

	print("— игра: верхняя и нижняя панели, пауза")
	Game.pending = "new"
	Game.pending_scn = "garage"
	Game.pending_profile = "mech"
	Game.pending_opts = {"tutorial": false}
	Game.pending_seed = 140
	Game.settings["tutorial_done"] = true
	var gm: GameMain = load("res://scenes/game.tscn").instantiate()
	add_child(gm)
	await _wait(8)
	var hud: Control = gm.hud
	var top: Control = (hud.get("_chips") as Dictionary)["money"]
	while top.get_parent() != hud:
		top = top.get_parent()
	var bottom: Control = (hud.get("bottom_btns") as Dictionary)["build"]
	while bottom.get_parent() != hud:
		bottom = bottom.get_parent()
	_no_cyr(top, "верхняя панель (надписи)", false)
	# подсказки чипов «Деньги», «Цели», «Погода» собраны из журнала, целей этапа и названий помещений — это 2-й этап
	var tip_bad: Array[String] = []
	for k: String in ["rep", "people", "power", "date", "company"]:
		var tt := ((hud.get("_chips") as Dictionary)[k] as Control).tooltip_text
		if L.has_cyr(tt) or tt == "":
			tip_bad.append("%s: %s" % [k, tt.replace("\n", " ").left(60)])
	for b: Button in hud.get("speed_btns"):
		if L.has_cyr(b.atr(b.tooltip_text)):
			tip_bad.append(b.tooltip_text)
	check(tip_bad.is_empty(), "подсказки верхней панели (репутация, люди, сеть, дата, завод, скорость) без кириллицы %s" % str(tip_bad))
	_no_cyr(bottom, "нижняя панель (с подсказками)")
	_fits(top, "верхняя панель")
	_fits(bottom, "нижняя панель")
	gm.sim.money = -50000.0
	gm.sim.crisis.debt_days = 2
	await _wait(3)
	var cb: Control = hud.get("crisis_bar")
	if cb and cb.visible:
		_no_cyr(cb, "красная плашка «в долгах»")
	hud.call("show_pause_menu")
	await _wait(2)
	_no_cyr(hud.get("modal"), "меню паузы")
	hud.call("show_settings")
	await _wait(2)
	_no_cyr(hud.get("modal"), "настройки в игре")
	hud.call("show_save_dialog")
	await _wait(2)
	_no_cyr(hud.get("modal"), "сохранение игры", false)
	hud.call("close_modal")

	print("— обратно на русский")
	L.apply("ru")
	await _wait(2)
	check(atr("Стройка") == "Стройка" and tr("Новая игра") == "Новая игра", "русский: ключи остаются русскими (запасной язык — ru)")
	L.apply("en")
	check(tr("Новая игра") == "New Game" and L.pl(1, "год|года|лет") == "year" and L.pl(5, "год|года|лет") == "years", "английский: перевод и число (year/years)")
	L.apply("ru")
	check(L.pl(3, "год|года|лет") == "года" and Defs.plural(5, "год", "года", "лет") == "лет", "русский: склонение по числу")
	check(L.translit("Тамбов, ул. Мичуринская") == "Tambov, ul. Michurinskaya" and L.translit("Красный") == "Krasny", "латиница: Тамбов → Tambov")

	gm.queue_free()
	await _wait(3)
	_restore()
	if fails.is_empty():
		print("РЕЗУЛЬТАТ: OK")
		get_tree().quit(0)
	else:
		print("РЕЗУЛЬТАТ: ОШИБКИ (%d): %s" % [fails.size(), "; ".join(fails)])
		get_tree().quit(1)


func _restore() -> void:
	if _had_cfg:
		var f := FileAccess.open(Game.SETTINGS_PATH, FileAccess.WRITE)
		f.store_buffer(_cfg_backup)
		f.close()
	elif FileAccess.file_exists(Game.SETTINGS_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Game.SETTINGS_PATH))
	Game.settings["lang"] = ""
	if FileAccess.file_exists(CustomWorkers.path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(CustomWorkers.path))
