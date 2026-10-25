extends Node
## 1.40, срез E перевода: стройка, справочник, обучение, город.
## В английском: меню «Стройка», «Объекты», «Зоны», «Сети» (все разделы, у каждой плитки — описание при наведении),
## справочник (все статьи), деревья «Развития» и «Разработок» (каждая ступень), окно «Город» (все вкладки),
## все шаги обучения — ни одной надписи с кириллицей, ничего не вылезает за экран. Надписи на карте и в городе —
## латиницей. По-русски всё как было.
## godot --headless --path . --audio-driver Dummy res://tests/stage14e_test.tscn

var fails: Array[String] = []
var gm: GameMain
var hud: Hud


func check(cond: bool, what: String) -> void:
	print(("  ✓ " if cond else "  ✗ ") + what)
	if not cond:
		fails.append(what)


func _wait(n: int) -> void:
	for i in n:
		await get_tree().process_frame


## [узел, текст] видимых надписей под root (как в stage140; поля ввода — имена, их вводит игрок — не проверяем).
func _texts(root: Node, tips: bool = true) -> Array:
	var out: Array = []
	for n: Node in [root] + root.find_children("*", "Control", true, false):
		var c := n as Control
		if c == null or not c.is_visible_in_tree() or c is LineEdit:
			continue
		if c is Label and (c as Label).auto_translate_mode == Node.AUTO_TRANSLATE_MODE_DISABLED:
			continue
		if c is Label:
			out.append([c, c.atr((c as Label).text)])
		elif c is RichTextLabel:
			out.append([c, (c as RichTextLabel).get_parsed_text()])
		elif c is Button:
			out.append([c, c.atr((c as Button).text)])
			if c is OptionButton:
				var ob := c as OptionButton
				for i in ob.item_count:
					out.append([c, ob.atr(ob.get_item_text(i))])
		if tips and c.tooltip_text != "":
			out.append([c, c.atr(c.tooltip_text)])
	return out


func _bad_of(root: Node, tips: bool = true) -> Array[String]:
	var bad: Array[String] = []
	for e: Array in _texts(root, tips):
		if L.has_cyr(str(e[1])):
			bad.append("«%s» (%s)" % [str(e[1]).replace("\n", " ").left(70), (e[0] as Node).get_class()])
	return bad


func _report(bad: Array[String], n: int, what: String) -> void:
	check(n > 0 and bad.is_empty(), "%s: %d надписей, без кириллицы%s" % [what, n, "" if bad.is_empty() else ": " + "; ".join(bad.slice(0, 6)) + (" …ещё %d" % (bad.size() - 6) if bad.size() > 6 else "")])


## Строки, которые собирают другие срезы перевода (sim/progress — названия этапов, sim/office — «кабинет: …»):
## не наша кириллица — печатаем заметкой, а не ошибкой.
func _split_foreign(bad: Array[String], what: String) -> Array[String]:
	var own: Array[String] = []
	var other: Array[String] = []
	for b in bad:
		if b.begins_with("«stage ") or b.begins_with("«office: ") or b.begins_with("«специалист") or b.begins_with("«engineer: "):
			if not other.has(b):
				other.append(b)
		else:
			own.append(b)
	if not other.is_empty():
		print("  · %s — заметка, строки других срезов (%d): %s" % [what, other.size(), "; ".join(other.slice(0, 4))])
	return own


func _no_cyr(root: Node, what: String, tips: bool = true) -> void:
	_report(_bad_of(root, tips), _texts(root, tips).size(), what)


func _fits(c: Control, what: String) -> void:
	var vr := c.get_viewport_rect().size
	var mw := c.get_combined_minimum_size()
	var r := c.get_global_rect()
	check(mw.x <= vr.x + 0.5 and r.end.x <= vr.x + 1.0 and r.position.x >= -1.0 and r.end.y <= vr.y + 1.0,
		"%s умещается: %.0f×%.0f из %.0f×%.0f" % [what, maxf(mw.x, r.end.x), maxf(mw.y, r.end.y), vr.x, vr.y])


func _ready() -> void:
	get_tree().create_timer(800.0).timeout.connect(func() -> void:
		print("РЕЗУЛЬТАТ: ОШИБКИ: тест не уложился во время")
		get_tree().quit(2))
	get_tree().root.size = Vector2i(1600, 900)   # как в игре: ширина окна по умолчанию, проверяем вылезание
	Game.pending = "new"
	Game.pending_scn = "garage"
	Game.pending_profile = "mech"
	Game.pending_opts = {"tutorial": true}
	Game.pending_seed = 1400
	Game.settings["tutorial_done"] = false
	gm = load("res://scenes/game.tscn").instantiate()
	add_child(gm)
	await _wait(8)
	hud = gm.hud
	var sim := gm.sim
	check(L.lang() == "ru", "язык тестов — русский")

	print("— русский: тексты прежние")
	hud.show_help(false, "welcome")
	await _wait(3)
	_fits((hud.modal as Control).get_child(0) as Control, "справочник (русский)")
	hud.close_modal()
	await _wait(2)
	check(L.t("Стройка в приоритете") == "Стройка в приоритете" and HelpBook.title_of("welcome") == "Добро пожаловать в «Промзону»", "по-русски ключи остаются русскими")
	check(BuildMenu._per_cell(1200.0) == Defs.money_str(1200.0) + "/кл.", "цена за клетку по-русски — «… ₽/кл.»")
	check(CityBackdrop._tx("ул. Мичуринская") == "ул. Мичуринская", "вывески города по-русски — как были")

	L.apply("en")
	await _wait(2)
	print("— английский: данные и вывески")
	check(L.t("Токарный 1К62") == "Lathe 1K62" and L.t("Цех") == "Workshop" and L.t("Бетонный пол") == "Concrete floor", "названия из данных: Lathe 1K62, Workshop, Concrete floor")
	var miss: Array[String] = []
	for k in Defs.objects.keys():
		var od: Dictionary = Defs.objects[k]
		for f in ["name", "desc", "cat"]:
			if od.has(f) and L.has_cyr(L.t(str(od[f]))):
				miss.append("%s.%s" % [k, f])
	for k2 in Defs.rooms.keys():
		var rd: Dictionary = Defs.rooms[k2]
		for f2 in ["name", "desc", "short"]:
			if rd.has(f2) and L.has_cyr(L.t(str(rd[f2]))):
				miss.append("room %s.%s" % [k2, f2])
		for nd: Dictionary in rd.get("needs", []):
			if L.has_cyr(L.t(str(nd.get("text", "")))):
				miss.append("room %s.needs" % k2)
	for k3 in Defs.research.keys():
		for f3 in ["name", "desc", "short", "branch"]:
			if (Defs.research[k3] as Dictionary).has(f3) and L.has_cyr(L.t(str(Defs.research[k3][f3]))):
				miss.append("research %s.%s" % [k3, f3])
	for dd: Dictionary in [Defs.floors, Defs.walls, Defs.templates]:
		for k4 in dd.keys():
			for f4 in ["name", "desc"]:
				if (dd[k4] as Dictionary).has(f4) and L.has_cyr(L.t(str(dd[k4][f4]))):
					miss.append("%s.%s" % [k4, f4])
	check(miss.is_empty(), "все объекты, помещения, разработки, полы, стены и шаблоны переведены %s" % str(miss.slice(0, 8)))
	var street := CityBackdrop._tx("ул. Мичуринская")
	check(street == "Michurinskaya St." and CityBackdrop._tx("Моршанское ш.") == "Morshanskoe Hwy" and CityBackdrop._tx("р. Цна") == "Tsna River", "улицы латиницей: %s, %s" % [street, CityBackdrop._tx("Моршанское ш.")])
	var nm_bad: Array[String] = []
	for kind in CityBackdrop.NAMES.keys():
		for s: String in CityBackdrop.NAMES[kind]:
			if L.has_cyr(CityBackdrop._tx(s)):
				nm_bad.append(s)
	check(nm_bad.is_empty(), "вывески зданий в городе без кириллицы %s" % str(nm_bad))
	check(Links.target("Workers complain: wages delayed for 3 days") == "finance:summary" and Links.target("Order failed: bolt ×10") == "orders:active", "уведомления на английском ведут в нужное окно")

	print("— меню стройки")
	sim.progress.all_open = true
	var tile_bad: Array[String] = []
	var trunc: Array[String] = []
	var n_tiles := 0
	var kinds := {"build": ["frame", "floor", "wall", "open", "yard"], "objects": Hud.OBJ_CATS, "rooms": (Defs.rooms.get("_groups", {}) as Dictionary).keys(), "power": ["power", "light", "water", "vent", "air"]}
	for kind: String in kinds.keys():
		hud.toggle_sub(kind)
		await _wait(2)
		for c: Variant in kinds[kind]:
			match kind:
				"build":
					BuildMenu.build_cat = str(c)
				"objects":
					hud.obj_cat = str(c)
				"rooms":
					BuildMenu.zone_cat = str(c)
				"power":
					hud.net_kind = str(c)
			hud._fill_sub()
			await _wait(1)
			var bad := _bad_of(hud.sub_panel)
			_report(bad, _texts(hud.sub_panel).size(), "меню %s · %s" % [kind, str(c)])
			# описание плиток при наведении
			for b: Node in hud.sub_panel.find_children("*", "Button", true, false):
				if not (b as Button).has_meta("arg"):
					continue
				n_tiles += 1
				(b as Button).mouse_entered.emit()
				var info := BuildMenu._info.text
				var arg: Variant = (b as Button).get_meta("arg")
				if kind == "rooms" and Defs.rooms.has(str(arg)):
					info = info.replace(Rooms.req_text(str(arg)), "")   # «что нужно» собирает rooms.gd (срез D2)
				if L.has_cyr(info):
					tile_bad.append("%s: %s" % [str(arg), info.left(60)])
				for l: Node in b.find_children("*", "Label", true, false):
					if (l as Label).text.ends_with("…"):
						trunc.append((l as Label).text.replace("\n", " "))
				(b as Button).mouse_exited.emit()
			if str(c) == str((kinds[kind] as Array)[0]):
				_fits(hud.sub_panel, "меню %s · %s" % [kind, str(c)])
	check(n_tiles > 150 and tile_bad.is_empty(), "описания %d плиток при наведении без кириллицы %s" % [n_tiles, str(tile_bad.slice(0, 5))])
	check(trunc.size() <= 3, "подписи плиток умещаются (с многоточием: %d) %s" % [trunc.size(), str(trunc.slice(0, 6))])
	hud.close_sub()
	await _wait(2)

	print("— справочник")
	hud.show_help(false, "welcome")
	await _wait(3)
	var hb: HelpBook = hud.modal as HelpBook
	check(hb != null, "справочник открыт")
	var hbad: Array[String] = []
	var n_art := 0
	for id in HelpBook.article_ids():
		hb.open(id)
		await _wait(1)
		n_art += 1
		hbad.append_array(_bad_of(hb))
	_report(hbad, n_art, "справочник: %d статей" % n_art)
	_fits(hb.get_child(0) as Control, "справочник")
	hb._search.text = "pallet"
	hb._fill_list()
	check(not HelpBook.search("pallet").is_empty() and HelpBook.search("поддон").is_empty(), "поиск в справочнике — по-английски (pallet: %d)" % HelpBook.search("pallet").size())
	_no_cyr(hb, "справочник: поиск")
	hud.close_modal()
	await _wait(2)

	print("— «Развитие» и «Разработки»")
	hud.open_window("develop")
	await _wait(3)
	var dbad: Array[String] = []
	var nd := 0
	for id2 in ["root"] + Develop.all_ids():
		DevTree.sel = str(id2)
		hud.win.rebuild(true)
		await _wait(1)
		nd += 1
		dbad.append_array(_bad_of(hud.win.content))
	_report(_split_foreign(dbad, "Развитие"), nd, "дерево «Развития»: %d ступеней" % nd)
	_fits(hud.win, "окно «Развитие»")
	hud.open_window("research")
	await _wait(3)
	var rbad: Array[String] = []
	var nr := 0
	for id3 in ["root"] + Defs.research.keys():
		ResearchTree.sel = str(id3)
		hud.win.rebuild(true)
		await _wait(1)
		nr += 1
		rbad.append_array(_bad_of(hud.win.content))
	_report(_split_foreign(rbad, "Разработки"), nr, "дерево «Разработок»: %d узлов" % nr)
	_fits(hud.win, "окно «Разработки»")

	print("— «Город»")
	hud.open_window("town")
	await _wait(3)
	for tab in ["overview", "dorm", "canteen", "kg", "radio", "cat"]:
		hud.win.select_tab(tab)
		await _wait(2)
		_no_cyr(hud.win.content, "город · %s" % tab)
	_fits(hud.win, "окно «Город»")
	hud.win.closed.emit()
	await _wait(2)

	print("— обучение")
	var tut: TutorialPanel = hud.tutorial
	var tbad: Array[String] = []
	var tall: Array[String] = []
	for i in TutorialPanel.STEPS.size():
		sim.progress.tutorial = i
		tut._show()
		await _wait(2)
		tbad.append_array(_bad_of(tut))
		var r := tut.get_global_rect()
		if r.end.y > tut.get_viewport_rect().size.y + 1.0 or r.end.x > tut.get_viewport_rect().size.x + 1.0:
			tall.append("%s %.0f×%.0f" % [str(TutorialPanel.STEPS[i]["id"]), r.size.x, r.size.y])
	_report(tbad, TutorialPanel.STEPS.size(), "обучение: %d шагов" % TutorialPanel.STEPS.size())
	check(tall.is_empty(), "панель обучения в окне на всех шагах %s" % str(tall))
	sim.progress.tutorial = -1
	tut._show()

	print("— надписи на карте")
	check(L.t("РАЗГРУЗКА") == "UNLOADING" and L.t("ПРОДАЁТСЯ") == "FOR SALE" and L.t("ВЫБИТ АВТОМАТ") == "BREAKER TRIPPED", "зоны, продажа участка, автомат — по-английски")
	var ov := ["Освещение: жёлтым — светят лампы, голубым — свет из окон днём, синим — темно", "Значки в углу объекта — что ему нужно; красный — этого нет"]
	check(not L.has_cyr(L.t(ov[0])) and not L.has_cyr(L.t(ov[1])), "легенды слоёв переведены")

	L.apply("ru")
	await _wait(2)
	check(BuildMenu._per_cell(1200.0).ends_with("/кл.") and HelpBook.title_of("welcome") == "Добро пожаловать в «Промзону»", "обратно на русский")
	gm.queue_free()
	await _wait(3)
	Game.settings["lang"] = ""
	if fails.is_empty():
		print("РЕЗУЛЬТАТ: OK")
		get_tree().quit(0)
	else:
		print("РЕЗУЛЬТАТ: ОШИБКИ (%d): %s" % [fails.size(), "; ".join(fails)])
		get_tree().quit(1)
