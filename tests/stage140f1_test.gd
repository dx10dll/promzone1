extends Node
## 1.40 (f1): поиск в меню, подсветка нужного помещению, меню постоянной высоты, надписи плиток в рамках,
## вкладки стройки, режим плана, ☰ всегда на месте, табличка «Продаётся» ведёт в «Развитие».
## xvfb-run -a godot --path . --rendering-driver opengl3 --resolution 1600x900 res://tests/stage140f1_test.tscn

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


func _tiles() -> Array[Button]:
	var out: Array[Button] = []
	for b: Node in hud.sub_panel.find_children("*", "Button", true, false):
		if b.has_meta("arg") and not b.is_queued_for_deletion():
			out.append(b as Button)
	return out


## Все надписи плиток — внутри рамки плитки.
func _labels_inside(what: String) -> void:
	var bad: Array[String] = []
	for b in _tiles():
		var br := b.get_global_rect().grow(0.5)
		for l: Node in b.find_children("*", "Label", true, false):
			var lr := (l as Control).get_global_rect()
			var tw := (l as Label).get_theme_font("font").get_string_size((l as Label).text.split("\n")[0], HORIZONTAL_ALIGNMENT_LEFT, -1, (l as Label).get_theme_font_size("font_size")).x
			if not br.encloses(lr) or (l.has_meta("price") and tw > lr.size.x + 0.5):
				bad.append("%s «%s»" % [str(b.get_meta("arg")), (l as Label).text.replace("\n", " ")])
	check(bad.is_empty(), "%s: цена, подпись и «есть N» внутри плиток %s" % [what, str(bad.slice(0, 4))])


func _ready() -> void:
	get_tree().create_timer(300.0).timeout.connect(func() -> void:
		print("РЕЗУЛЬТАТ: ОШИБКИ: тест не уложился во время")
		get_tree().quit(2))
	get_tree().root.size = Vector2i(1600, 900)
	Game.pending = "new"
	Game.pending_scn = "garage"
	Game.pending_profile = "mech"
	Game.pending_opts = {"tutorial": false}
	Game.pending_seed = 1401
	Game.settings["tutorial_done"] = true
	gm = load("res://scenes/game.tscn").instantiate()
	add_child(gm)
	await get_tree().create_timer(2.0).timeout
	hud = gm.hud
	var sim := gm.sim
	sim.progress.all_open = true

	print("— вкладки стройки")
	hud.toggle_sub("build")
	await _wait(3)
	var cats: Array[String] = []
	for b: Node in hud.sub_panel.find_children("*", "Button", true, false):
		if b.has_meta("cat"):
			cats.append(str(b.get_meta("cat")))
	check(cats == ["Стены", "Полы", "Окна и двери", "Зоны на улице", "Готовые помещения"], "порядок: стены, полы, двери, улица, готовые помещения %s" % str(cats))
	var hs: Array[float] = []
	for c: String in BuildMenu.BUILD_CATS:
		BuildMenu.build_cat = c
		hud._fill_sub()
		await _wait(2)
		hs.append(hud.sub_panel.size.y)
		if c == "frame":
			var rf := 0
			for t in _tiles():
				if not Defs.templates.has(str(t.get_meta("arg"))):
					rf += 1
			check(rf == 0 and _tiles().size() == Defs.templates.size(), "в готовых помещениях нет «… рамкой»")
	check(hs.max() - hs.min() < 0.5, "меню стройки одной высоты во всех разделах %s" % str(hs))

	print("— обучение: шаг «Стройка → Готовые помещения → Склад»")
	var tut: TutorialPanel = hud.tutorial
	BuildMenu.build_cat = "wall"
	hud._fill_sub()
	await _wait(2)
	var chip: Button = null
	for b: Node in hud.sub_panel.find_children("*", "Button", true, false):
		if b.has_meta("cat") and str(b.get_meta("cat")) == "Готовые помещения" and not b.is_queued_for_deletion():
			chip = b
	check(chip != null and tut._menu_target("build", "Готовые помещения", "storage").is_equal_approx(chip.get_global_rect()), "обучение подсвечивает вкладку «Готовые помещения»")
	if chip:
		chip.pressed.emit()
		await _wait(2)
		var st: Control = tut._find(hud.sub_panel, "arg", "storage")
		check(st != null and tut._menu_target("build", "Готовые помещения", "storage").is_equal_approx(st.get_global_rect()), "затем — плитку «Склад 6×4»")
	check(TutorialPanel.STEPS.any(func(x: Dictionary) -> bool: return str(x.get("do", "")).contains("«Готовые помещения»")), "текст шага обучения называет новую вкладку")

	print("— меню объектов: высота и надписи")
	hud.toggle_sub("objects")
	await _wait(2)
	hs.clear()
	var ws: Array[float] = []
	for lang: String in ["ru", "en"]:
		L.apply(lang)
		for c: String in Hud.OBJ_CATS:
			hud.obj_cat = c
			hud._fill_sub()
			await _wait(2)
			hs.append(hud.sub_panel.size.y)
			ws.append(hud.sub_panel.size.x)
			_labels_inside("%s · %s" % [lang, c])
	L.apply("ru")
	var hr := hs.slice(0, Hud.OBJ_CATS.size())
	check(hr.max() - hr.min() < 0.5 and ws.max() - ws.min() < 0.5, "меню объектов не прыгает: высота %s–%s, ширина %s–%s" % [hr.min(), hr.max(), ws.min(), ws.max()])
	check(BuildMenu.short_money("1 600 000 ₽") == "1.6 млн ₽" and BuildMenu.short_money("115 000 ₽") == "115 тыс. ₽", "короткая цена: %s" % BuildMenu.short_money("1 600 000 ₽"))

	print("— поиск")
	BuildMenu.query["objects"] = "токарн"
	hud._fill_sub()
	await _wait(2)
	var ok := _tiles().size() >= 3
	for t in _tiles():
		ok = ok and str(Defs.objects[str(t.get_meta("arg"))]["name"]).to_lower().contains("токарн")
	check(ok, "поиск «токарн» — только токарные станки (%d)" % _tiles().size())
	L.apply("en")
	BuildMenu.query["objects"] = "lathe"
	hud._fill_sub()
	await _wait(2)
	var en_ok := _tiles().size() >= 3
	for t in _tiles():
		en_ok = en_ok and L.t(str(Defs.objects[str(t.get_meta("arg"))]["name"])).to_lower().contains("lathe")
	check(en_ok, "в английском ищем по английским названиям: lathe (%d)" % _tiles().size())
	L.apply("ru")
	BuildMenu.query["objects"] = "zzzqq"
	hud._fill_sub()
	await _wait(2)
	check(_tiles().is_empty() and hud.sub_panel.size.y > 100.0, "ничего не нашлось — меню той же высоты")
	BuildMenu.query["build"] = "дверь"
	hud.toggle_sub("build")
	await _wait(2)
	BuildMenu.query["build"] = "дверь"
	hud._fill_sub()
	await _wait(2)
	check(_tiles().size() >= 2, "поиск по стройке: двери из «Окна и двери» (%d)" % _tiles().size())
	var le: LineEdit = null
	for n: Node in hud.sub_panel.find_children("*", "LineEdit", true, false):
		if not n.is_queued_for_deletion():
			le = n
	check(le != null and le.text == "дверь", "поле поиска в шапке меню")
	if le:
		le.grab_focus()
		le.text = "кирп"
		le.text_changed.emit("кирп")
		await _wait(3)
		var f := get_viewport().gui_get_focus_owner()
		check(f is LineEdit and (f as LineEdit).text == "кирп", "после пересборки фокус остаётся в поиске — можно печатать дальше")
	hud.close_sub()
	check(str(BuildMenu.query["build"]) == "", "закрыли меню — поиск сброшен")

	print("— подсветка нужного помещению")
	var room: Rooms.Room = null
	for r: Rooms.Room in sim.rooms.list:
		if r.type == "canteen":
			room = r
	check(room != null, "в гараже есть столовая")
	if room:
		var cc := Vector2.ZERO
		for c in room.cells:
			cc += Vector2(c)
		cc /= float(room.cells.size())
		var center: Vector2i = room.cells[0]
		for c in room.cells:
			if Vector2(c).distance_to(cc) < Vector2(center).distance_to(cc):
				center = c
		gm.cam.zoom = Vector2(1.8, 1.8)
		gm.cam.position = (Vector2(center) + Vector2(0.5, 0.5)) * World.T
		await _wait(3)
		hud.obj_cat = "Быт"
		hud.toggle_sub("objects")
		await get_tree().create_timer(0.5).timeout
		var lit: Array[String] = []
		for t in _tiles():
			if t.has_meta("need"):
				lit.append(str(t.get_meta("arg")))
		check(BuildMenu.focus_type == "canteen" and lit.has("dining_table") and lit.has("chair"), "камера над столовой — подсвечены стол и стулья %s" % str(lit))
		gm.cam.zoom = Vector2(0.6, 0.6)
		await get_tree().create_timer(0.5).timeout
		var lit2 := 0
		for t in _tiles():
			if t.has_meta("need"):
				lit2 += 1
		check(BuildMenu.focus_type == "" and lit2 == 0, "камера отдалилась — подсветка снята")
		hud.close_sub()

	print("— режим плана")
	hud.toggle_plan()
	await _wait(3)
	var secs := 0
	for n: Node in hud.sub_panel.find_children("*", "ScrollContainer", true, false):
		if not n.is_queued_for_deletion() and n.has_meta("tile_rows"):
			secs += 1
	check(gm.tool.plan_mode and hud.sub_panel.visible and secs == 2, "план: меню стройки и меню объектов разом (%d)" % secs)
	var objt := 0
	for t in _tiles():
		if Defs.objects.has(str(t.get_meta("arg"))):
			objt += 1
	check(objt > 0, "в плане видны объекты")
	check(hud.sub_panel.get_global_rect().position.y > 50.0, "меню плана не залезает под верхнюю панель")
	hud.bottom_btns["objects"].pressed.emit()
	await _wait(2)
	check(not gm.tool.plan_mode and hud.sub_kind == "objects", "кнопка «Объекты» выводит из плана и открывает объекты")
	hud.toggle_plan()
	await _wait(2)
	hud.bottom_btns["demolish"].pressed.emit()
	await _wait(2)
	check(not gm.tool.plan_mode and gm.tool.mode == "demolish", "«Снос» выводит из плана")
	gm.tool.set_mode("select")
	hud.toggle_plan()
	await _wait(2)
	hud.bottom_btns["people"].pressed.emit()
	await _wait(2)
	check(not gm.tool.plan_mode and hud.win != null, "окно с нижней панели выводит из плана")
	hud.close_window()
	hud.toggle_plan()
	await _wait(2)
	hud.toggle_plan()
	await _wait(2)
	check(not gm.tool.plan_mode and not hud.sub_panel.visible, "повторное «План» выключает план и закрывает меню")

	print("— ☰ в правом верхнем углу")
	var vw := get_viewport().get_visible_rect().size.x
	var mb0 := hud.menu_btn.get_global_rect()
	check(mb0.end.x <= vw + 0.5 and mb0.position.x > vw - 80.0, "☰ у правого края: %s" % str(mb0))
	hud.company_l.text = "Очень длинное название завода, которое никак не помещается в строку" .repeat(2)
	hud.people_l.text = "123 / 456 at the plant and a very long text"
	hud.fast_l.text = "fast-forward"
	await _wait(3)
	var mb1 := hud.menu_btn.get_global_rect()
	check(mb1.is_equal_approx(mb0) and hud.menu_btn.is_visible_in_tree(), "длинные надписи не сдвигают ☰: %s" % str(mb1))
	var tmin := (hud.top_left.get_parent() as Control).get_combined_minimum_size().x
	check(tmin < 720.0, "верхняя панель не требует ширины больше %.0f px — в узком окне ☰ не уезжает за край" % tmin)

	print("— табличка «Продаётся»")
	Scenario.add_lots(sim)
	if sim.world.lots.is_empty():
		check(true, "на карте нет участков — пропуск")
	else:
		var k := -1
		for i in sim.world.lots.size():
			if not sim.world.lot_bought(i):
				k = i
				break
		if k >= 0:
			gm.open_lot(k)
			await _wait(3)
			check(hud.win != null and hud.win.sec == "develop" and Develop.step_def(DevTree.sel).get("lot", -1) == k, "щелчок по табличке — «Развитие» на ступени участка %d (%s)" % [k, DevTree.sel])
			gm.open_lot(k)
			await _wait(3)
			check(hud.win != null and hud.win.sec == "develop", "повторный щелчок не закрывает окно")
			hud.close_window()
			# щелчок мышью: табличка не на клетке пола — раньше щелчок до неё не доходил
			var sr := FxLayer.sign_rect(sim, k)
			gm.cam.zoom = Vector2(1.0, 1.0)
			gm.cam.position = sr.get_center()
			await _wait(30)   # камера доезжает плавно — ждём, пока встанет
			var scr := gm.fx.get_global_transform_with_canvas() * sr.get_center()
			Input.warp_mouse(scr)
			await _wait(3)
			gm.tool._select_at()
			await _wait(3)
			check(hud.win != null and hud.win.sec == "develop", "щелчок по табличке в режиме выбора открывает «Развитие»")
			hud.close_window()

	print("РЕЗУЛЬТАТ: " + ("ВСЁ ХОРОШО" if fails.is_empty() else "ОШИБКИ: %d — %s" % [fails.size(), "; ".join(fails)]))
	get_tree().quit(0 if fails.is_empty() else 1)
