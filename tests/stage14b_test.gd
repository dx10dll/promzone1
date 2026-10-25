extends Node
## 1.40 (часть B перевода): карточки и люди на английском.
## Личная карточка (все вкладки), карточки объектов, клеток и помещений, меню над человеком,
## «Под управлением», «Что делать», разделы «Бригады / График / Охрана / Профсоюз», письмо-событие,
## «Начать раньше», паспорт завода, новый этап, сценарий пройден, конец игры, долги, увольнение,
## «Как исправить», планировка и подсказки инструментов, чертёж, подписи графиков.
## Текст, который создаёт симуляция (имена занятий, мысли, письма, нарушения…), переводят другие части —
## поэтому ошибкой считаем только кириллицу, совпавшую с нашим шаблоном из strings_b.csv.
## godot --headless --path . --audio-driver Dummy res://tests/stage14b_test.tscn

var fails: Array[String] = []
var _res: Array = []          ## [RegEx, ключ] — наши русские шаблоны
var _plain: Dictionary = {}   ## короткие ключи — только точное совпадение
var _foreign := 0
var _foreign_list: Dictionary = {}


func check(cond: bool, what: String) -> void:
	print(("  ✓ " if cond else "  ✗ ") + what)
	if not cond:
		fails.append(what)


func _wait(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _load_keys() -> void:
	var f := FileAccess.open("res://assets/i18n/strings_b.csv", FileAccess.READ)
	f.get_csv_line()
	while not f.eof_reached():
		var row := f.get_csv_line()
		if row.size() < 2 or row[0] == "":
			continue
		var k := row[0]
		var stat := RegEx.create_from_string("%[-+0-9.]*[dsf%]").sub(k, "", true)
		var ncyr := 0
		for i in stat.length():
			if L.has_cyr(stat[i]):
				ncyr += 1
		if ncyr == 0:
			continue
		if ncyr < 6 or not k.contains("%"):
			_plain[k] = true
			if ncyr < 8:
				continue
		var pat := ""
		var parts := RegEx.create_from_string("(%[-+0-9.]*[dsf%])").search_all(k)
		var pos := 0
		for m: RegExMatch in parts:
			pat += _esc(k.substr(pos, m.get_start() - pos))
			var spec := m.get_string()
			pat += "%" if spec == "%%" else ("(.*?)" if spec.ends_with("s") else "([-−+0-9.,]+)")
			pos = m.get_end()
		pat += _esc(k.substr(pos))
		var re := RegEx.create_from_string(pat)
		if re.is_valid():
			_res.append([re, k])


func _esc(s: String) -> String:
	var out := ""
	for ch in s:
		out += ("\\" + ch) if "\\^$.|?*+()[]{}".contains(ch) else ch
	return out


## Наша ли это непереведённая строка (а не текст симуляции).
func _mine(t: String) -> String:
	if _plain.has(t):
		return t
	for e: Array in _res:
		if (e[0] as RegEx).search(t) != null:
			return str(e[1])
	return ""


func _texts(root: Node, tips: bool = true) -> Array:
	var out: Array = []
	for n: Node in [root] + root.find_children("*", "Control", true, false):
		var c := n as Control
		if c == null or not c.is_visible_in_tree() or c is LineEdit:
			continue
		if c is Label:
			out.append([c, c.atr((c as Label).text)])
		elif c is Button:
			out.append([c, c.atr((c as Button).text)])
			if c is OptionButton:
				var ob := c as OptionButton
				for i in ob.item_count:
					out.append([c, ob.atr(ob.get_item_text(i))])
					if ob.get_item_tooltip(i) != "":
						out.append([c, ob.atr(ob.get_item_tooltip(i))])
		if tips and c.tooltip_text != "":
			out.append([c, c.atr(c.tooltip_text)])
	return out


func _no_cyr(root: Node, what: String, tips: bool = true) -> void:
	var bad: Array[String] = []
	var n := 0
	for e: Array in _texts(root, tips):
		n += 1
		var t := str(e[1])
		if not L.has_cyr(t):
			continue
		var k := _mine(t)
		if k != "":
			bad.append("«%s» ← «%s»" % [t.replace("\n", " ").left(60), k.replace("\n", " ").left(40)])
		else:
			_foreign += 1
			_foreign_list[t.replace("\n", " ").left(80)] = true
	check(n > 0 and bad.is_empty(), "%s: %d надписей, наших без перевода нет%s" % [what, n, "" if bad.is_empty() else ": " + "; ".join(bad.slice(0, 6)) + (" …ещё %d" % (bad.size() - 6) if bad.size() > 6 else "")])


func _fits(c: Control, what: String) -> void:
	var vs := c.get_viewport_rect().size
	var r := c.get_global_rect()
	var mw := c.get_combined_minimum_size()
	check(mw.x <= vs.x + 0.5 and r.end.x <= vs.x + 1.0 and r.position.x >= -1.0 and mw.y <= vs.y + 0.5, "%s умещается: %.0f×%.0f в %.0f×%.0f" % [what, maxf(mw.x, r.size.x), maxf(mw.y, r.size.y), vs.x, vs.y])


func _ready() -> void:
	get_tree().create_timer(600.0).timeout.connect(func() -> void:
		print("РЕЗУЛЬТАТ: ОШИБКИ: тест не уложился во время")
		get_tree().quit(2))
	_load_keys()
	check(_res.size() > 300, "шаблонов из strings_b.csv: %d (+ %d коротких)" % [_res.size(), _plain.size()])
	L.apply("en")
	check(tr("ЛИЧНАЯ КАРТОЧКА РАБОТНИКА") == "PERSONNEL RECORD CARD" and L.pl(3, "день|дня|дней") == "days", "перевод части B подключён")
	Game.pending = "new"
	Game.pending_scn = "field"
	Game.pending_profile = "mech"
	Game.pending_opts = {"tutorial": false, "money": 3000000}
	Game.pending_seed = 1402
	Game.settings["tutorial_done"] = true
	var gm: GameMain = load("res://scenes/game.tscn").instantiate()
	add_child(gm)
	await _wait(10)
	var sim: Sim = gm.sim
	var hud: Hud = gm.hud
	sim.story.letters.clear()
	for i in 600:
		sim.tick(1.0)
	sim.story.letters.clear()
	await _wait(3)
	var ws: Array[Worker] = []
	for w in sim.workers:
		if not w.visitor:
			ws.append(w)
	check(ws.size() >= 2, "на заводе есть люди: %d" % ws.size())

	print("— личная карточка")
	var w0: Worker = ws[0]
	for w in ws.slice(0, 4):
		for tab: String in ["main", "skills", "rel", "hist"]:
			InfoPanel.w_tab = tab
			hud.info.show_worker(sim, w)
			await _wait(3)
			hud.info.refresh()
			_no_cyr(hud.info, "карточка %s · %s" % [L.name(w.full_name()), tab])
		_fits(hud.info, "карточка %s" % L.name(w.full_name()))
	InfoPanel.w_tab = "main"

	print("— карточки объектов, клеток, помещений")
	var seen := {}
	for t: Thing in sim.things.values():
		if seen.has(t.def_id) or seen.size() >= 40:
			continue
		seen[t.def_id] = true
		hud.info.show_thing(sim, t)
		await _wait(2)
		hud.info.refresh()
		_no_cyr(hud.info, "объект %s" % t.def_id)
	_fits(hud.info, "карточка объекта")
	var cells: Array[Vector2i] = []
	var wd := sim.world
	var got_wall := false
	var got_floor := false
	for y in wd.h:
		for x in wd.w:
			var i := wd.idx(Vector2i(x, y))
			if not got_wall and int(wd.wall[i]) != World.W_NONE:
				cells.append(Vector2i(x, y))
				got_wall = true
			elif not got_floor and int(wd.flr[i]) > 0 and int(wd.wall[i]) == World.W_NONE:
				cells.append(Vector2i(x, y))
				got_floor = true
	for c in cells:
		hud.info.show_cell(sim, c)
		await _wait(2)
		_no_cyr(hud.info, "клетка %s" % str(c))
	for ri in sim.rooms.list.size():
		hud.info.show_room(sim, ri)
		await _wait(2)
		hud.info.refresh()
		_no_cyr(hud.info, "помещение %d «%s»" % [ri, sim.rooms.list[ri].title()])
	_fits(hud.info, "карточка помещения")
	hud.info.visible = false

	print("— меню над человеком и «Под управлением»")
	hud.worker_pop.show_for(w0)
	await _wait(3)
	_no_cyr(hud.worker_pop, "меню над человеком")
	_fits(hud.worker_pop, "меню над человеком")
	hud.worker_pop.close()
	hud.ctl.take(w0)
	await _wait(4)
	if w0.controlled:
		_no_cyr(hud.ctl.banner, "плашка «Под управлением»")
		_fits(hud.ctl.banner, "плашка «Под управлением»")
		hud.ctl.on_map_click(w0.cell() + Vector2i(1, 0), Vector2(600, 400))
		await _wait(2)
		if hud.ctl.menu_open():
			_no_cyr(hud.ctl.menu, "меню «Сделать сейчас»")
		hud.ctl.release()
	await _wait(2)

	print("— «Что делать»")
	if hud.todo:
		hud.todo.set("_sig", "")
		hud.todo.call("_refresh")
		await _wait(2)
		_no_cyr(hud.todo, "список «Что делать»")
		_fits(hud.todo, "список «Что делать»")

	print("— бригады, график, охрана, профсоюз")
	sim.office.all_depts = true   # разделы не закрыты отделами
	sim.crew.auto_form()
	for tab: String in ["brig", "sched", "sec", "union", "union"]:
		hud.open_window("people:" + tab)
		await _wait(4)
		var win: GameWindow = hud.win
		check(win != null and win.tab == tab, "открыт раздел %s" % tab)
		if win:
			if tab == "union":
				CrewUI.n1_section(win)
				await _wait(2)
			_no_cyr(win.content, "раздел %s" % tab)
			check(not L.has_cyr(_mine(win.sec_info.atr(win.sec_info.text))) and _mine(win.help_btn.atr(win.help_btn.tooltip_text)) == "", "раздел %s: строка состояния и «?» переведены" % tab)
			_fits(win, "окно с разделом %s" % tab)
		hud.close_window()
		await _wait(2)
		if tab == "union" and not sim.crew.union_on():
			sim.crew.union = {"on": true, "stance": "angry", "lead": w0.id, "since": 1, "offer": Crew.CLAUSES.keys().slice(0, 3), "clauses": {}}

	print("— письмо, окна и диалоги")
	sim.story.letter("test", "Тест", "Текст письма.", "letter", 1, [{"text": "Вариант 1", "hint": "Подсказка"}, {"text": "Вариант 2"}], 1, {"cx": 5, "cy": 5})
	hud.show_letter(sim.story.letters[0])
	await _wait(3)
	_no_cyr(hud.letter_box, "письмо-событие")
	_fits(hud.letter_box.get_child(0) as Control, "письмо-событие")
	hud.call("_close_letter")
	sim.story.letters.clear()
	var dialogs := {
		"«Начать раньше?»": func() -> void: hud.confirm_start_early(),
		"паспорт завода": func() -> void: hud.show_passport(),
		"новый этап": func() -> void: hud.show_stage_up(2),
		"сценарий пройден": func() -> void: hud.show_scenario_done(),
		"долги растут": func() -> void: hud.show_bankrupt(),
		"увольнение": func() -> void: hud.show_fire_dialog(w0),
		"конец игры": func() -> void: hud.show_game_over(),
	}
	for nm: String in dialogs.keys():
		(dialogs[nm] as Callable).call()
		await _wait(3)
		check(hud.modal != null, "открыто: %s" % nm)
		if hud.modal:
			# в паспорте — редактор эмблемы из 1-го этапа (там свои проверки)
			_no_cyr(hud.modal, nm, nm != "паспорт завода")
			_fits(hud.modal.get_child(0) as Control, nm)
		hud.close_modal()
		await _wait(2)
	hud.show_fix("Нет стеллажа", "")
	await _wait(2)
	_no_cyr(hud.fix_box, "«Как исправить»")
	(hud.fix_box as Control).queue_free()
	var o := {"product": str(Defs.products.keys()[0]), "id": 17, "qty": 40, "client": "ООО «Ромашка»"}
	hud.show_drawing(o)
	await _wait(3)
	_no_cyr(hud.modal, "чертёж (рамка)")
	_fits(hud.modal.get_child(0) as Control, "чертёж")
	var dv := DrawingView.new()
	check(not L.has_cyr(dv.tr("Сборочный чертёж")) and not L.has_cyr(dv.tr("Круг 40 ГОСТ 2590-2006")) and not L.has_cyr(dv.tr("Заказ № %d · %s · %d шт.")), "надписи чертежа переводятся")
	dv.free()
	hud.close_modal()
	check(not L.has_cyr(ChartView.fmt_val(2500000.0, "money")) and not L.has_cyr(ChartView.fmt_val(25000.0, "money")), "подписи графиков: %s, %s" % [ChartView.fmt_val(2500000.0, "money"), ChartView.fmt_val(25000.0, "money")])

	print("— планировка и подсказки инструментов")
	hud.toggle_plan()
	await _wait(3)
	_no_cyr(hud.plan_panel, "панель планировки")
	_fits(hud.plan_panel, "панель планировки")
	hud.toggle_plan()
	var modes: Array = [["wall", null], ["demolish", null], ["cancel", null], ["room", ""], ["room", "_erase"], ["room", "workshop"], ["cable", null],
		["uncable", null], ["pipe", null], ["unpipe", null], ["duct", null], ["unduct", null], ["air", null], ["unair", null], ["zone", 0], ["zone", 1], ["zone", 2]]
	modes.append(["object", str(Defs.objects.keys()[0])])
	modes.append(["floor", int(Defs.floor_by_id.keys()[0])])
	var bad_h: Array[String] = []
	for md: Array in modes:
		gm.tool.set_mode(str(md[0]), md[1])
		hud.call("_refresh_hint")
		var ht: String = hud.hint_l.text
		if _mine(ht) != "":
			bad_h.append(ht)
	gm.tool.set_mode("select")
	check(bad_h.is_empty(), "подсказки инструментов переведены %s" % str(bad_h))
	print("  (текст симуляции с кириллицей пропущен: %d надписей — его переводят другие части)" % _foreign)
	for ft: String in _foreign_list.keys().slice(0, 80):
		print("    · ", ft)

	L.apply("ru")
	check(hud.tr("ЛИЧНАЯ КАРТОЧКА РАБОТНИКА") == "ЛИЧНАЯ КАРТОЧКА РАБОТНИКА", "русский остаётся русским")
	gm.queue_free()
	await _wait(3)
	Game.settings["lang"] = ""
	if fails.is_empty():
		print("РЕЗУЛЬТАТ: OK")
		get_tree().quit(0)
	else:
		print("РЕЗУЛЬТАТ: ОШИБКИ (%d): %s" % [fails.size(), "; ".join(fails)])
		get_tree().quit(1)
