extends Node
## 1.39, фаза 2, кусок A: окна управления на английском (windows.gd + данные: изделия, металл, расходники,
## поставщики, переделы, отделы, гранты).
## 1) Русский текст не изменился: изделие, металл, отдел, грант — те же русские строки.
## 2) В английском: данные по стабильным ключам (product.*, material.*, department.*, grant.* …) переведены.
## 3) Каждый раздел каждой группы окна (кроме чужих кусков: бригады, развитие, разработки, город) — без кириллицы
##    в надписях и подсказках, кроме текста, который приходит из чужих кусков (имена, журнал, сводки сима — они
##    перечислены как «чужие» и только печатаются). Окно не шире экрана.
## godot --headless --path . --audio-driver Dummy res://tests/stage14a_test.tscn

var fails: Array[String] = []
var foreign_seen: Dictionary = {}
const SKIP_KINDS := ["crew", "develop", "research", "town"]


func check(cond: bool, what: String) -> void:
	print(("  ✓ " if cond else "  ✗ ") + what)
	if not cond:
		fails.append(what)


func _wait(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _texts(root: Node) -> Array:
	var out: Array = []
	for n: Node in [root] + root.find_children("*", "Control", true, false):
		var c := n as Control
		if c == null or not c.is_visible_in_tree() or c is LineEdit:
			continue
		if c is Label:
			out.append(c.atr((c as Label).text))
		elif c is Button:
			out.append(c.atr((c as Button).text))
			if c is OptionButton:
				for i in (c as OptionButton).item_count:
					out.append(c.atr((c as OptionButton).get_item_text(i)))
			if c is MenuButton:
				var pm := (c as MenuButton).get_popup()
				for i in pm.item_count:
					out.append(pm.get_item_text(i))
		elif c is Stamp:
			out.append(" ".join((c as Stamp).lines) + " " + (c as Stamp).ring)
		elif c is ChartView:
			for s: Dictionary in (c as ChartView).series:
				out.append(str(s.get("name", "")))
		if c.tooltip_text != "":
			out.append(c.atr(c.tooltip_text))
	return out


## Строки, которые приходят из чужих кусков (имена людей, журнал, сводки симуляции): их кириллицу
## не засчитываем как ошибку куска A, только печатаем.
func _foreign(sim: Sim) -> Array[String]:
	var f: Array[String] = []
	var ws: Array = sim.workers.duplicate()
	for cd: Dictionary in sim.candidates:
		ws.append(Worker.from_dict(cd))
	for w: Worker in ws:
		for s: String in [w.full_name(), w.formal_name(), w.call_name(), w.last, w.first, w.patronymic, w.prof_name(), w.rank_text(), w.prof_rank(), w.title(), w.title_lc(), w.activity]:
			if s != "":
				f.append(s)
	for e: Dictionary in sim.events:
		f.append(str(e["text"]))
	for e2: Dictionary in sim.ledger:
		f.append(str(e2["text"]))
	for o: Dictionary in sim.orders.list:
		f.append(sim.orders.short(o))
		f.append(sim.orders.deadline_str(o))
	for t: Thing in sim.things.values():
		f.append(t.title())
	for rm in sim.rooms.list:
		f.append(rm.title())
	for d: String in Defs.departments.keys():
		f.append(sim.progress.dept_lock_text(d))
		f.append(str(sim.office.room_status(d)[1]))
	for b: Dictionary in Develop.branches():
		for st: Dictionary in b.get("steps", []):
			f.append(sim.dev.block_reason(str(st["id"])))
	for s2: Dictionary in sim.supply:
		f.append(sim._eta_str(float(s2["eta"])))
	for s3: Dictionary in sim.cons_supply:
		f.append(sim._eta_str(float(s3["eta"])))
	for r: Dictionary in Stall.list(sim):
		f.append(str(r["why"]))
		f.append(str(r["hint"]))
	var it := sim.market.iso_text()
	f.append(it.substr(0, 1).to_upper() + it.substr(1))
	f.append(it)
	for rq: Array in sim.market.iso_reqs():
		f.append(str(rq[0]))
	Achievements.load_all()
	for a: Dictionary in Achievements.defs:
		f.append(L.dt("achievement.%s.name" % str(a["id"]), str(a["name"])))
		f.append(L.dt("achievement.%s.desc" % str(a["id"]), str(a["desc"])))
	for sd: Dictionary in Defs.stages.get("stages", []):
		f.append(str(sd.get("opens", "")))
		for g: Dictionary in (sd.get("goals", []) as Array) + ((sd.get("choice", {}) as Dictionary).get("list", []) as Array):
			f.append(str(g.get("text", "")))
			f.append(str(g.get("route", "")))
			f.append(str(sim.progress.goal_state(g)[1]))
	for h: Dictionary in Defs.seasons.get("holidays", []):
		f.append(str(h["name"]))
	for e3: Dictionary in sim.sales.log:
		f.append(str(e3["why"]))
	f.sort_custom(func(a: String, b: String) -> bool: return a.length() > b.length())
	return f


func _no_cyr(root: Node, what: String, foreign: Array[String]) -> void:
	var bad: Array[String] = []
	var n := 0
	for t0: Variant in _texts(root):
		var t := str(t0)
		n += 1
		if not L.has_cyr(t):
			continue
		var rest := t
		for s in foreign:
			if s.length() > 1 and rest.contains(s):
				rest = rest.replace(s, "")
		if L.has_cyr(rest):
			bad.append("«%s»" % t.replace("\n", " ").left(80))
		else:
			foreign_seen[t.replace("\n", " ").left(60)] = true
	check(n > 0 and bad.is_empty(), "%s: %d надписей, без кириллицы%s" % [what, n, "" if bad.is_empty() else ": " + "; ".join(bad.slice(0, 8)) + (" …ещё %d" % (bad.size() - 8) if bad.size() > 8 else "")])


func _fits(c: Control, what: String) -> void:
	var vw := c.get_viewport_rect().size.x
	var mw := c.get_combined_minimum_size().x
	check(mw <= vw + 0.5 and c.get_global_rect().end.x <= vw + 1.0, "%s умещается по ширине: %.0f из %.0f px" % [what, maxf(mw, c.get_global_rect().end.x), vw])


func _ready() -> void:
	get_tree().create_timer(600.0).timeout.connect(func() -> void:
		print("РЕЗУЛЬТАТ: ОШИБКИ: тест не уложился во время")
		get_tree().quit(2))
	print("— русский не изменился")
	check(L.lang() == "ru", "язык тестов — русский")
	check(Defs.product_name("bushing") == "Втулка" and Defs.material_name("bar45") == "Круг Ст45" and Defs.process_name("turning") == "Токарная" and Defs.process_name("qc") == "ОТК", "изделие, металл, передел — по-русски")
	check(GameWindow.dept_name("pdo") == "ПДО" and GameWindow.cons_text("tools") == "Режущий инструмент" and GameWindow.supplier_text("base") == "Металлобаза №3", "отдел, расходник, поставщик — по-русски")
	check(Grants.text(Grants.def("canteen"), "title") == "Горячее питание на производстве" and Grants.goal_text(Grants.def("wc_locker"), 1) == "оборудованная бытовка", "грант и условие — по-русски")
	L.apply("en")
	print("— данные по-английски")
	check(Defs.product_name("bushing") == "Bushing" and Defs.material_name("bar45") == "Round Bar St45" and Defs.process_name("turning") == "Turning" and Defs.process_name("qc") == "QC", "изделие, металл, передел: Bushing, Round Bar St45, Turning, QC")
	check(GameWindow.dept_name("pdo") == "Planning Office" and GameWindow.cons_text("tools", "pack") == "a set of cutters, mills and drills" and GameWindow.supplier_text("opt") == "ProkatOpt LLC", "отдел, расходник, поставщик")
	check(Grants.text(Grants.def("canteen"), "title") == "Hot Meals at Work" and Grants.goal_text(Grants.def("wc_locker"), 1) == "an equipped locker room", "грант и условие")
	var miss: Array[String] = []
	for p: String in Defs.products.keys():
		for f in ["name", "desc"]:
			if L.has_cyr(L.dt("product.%s.%s" % [p, f], str(Defs.products[p].get(f, "")))):
				miss.append("product.%s.%s" % [p, f])
	for m: String in Defs.materials.keys():
		if L.has_cyr(Defs.material_name(m)) or L.has_cyr(L.dt("material.%s.desc" % m, str(Defs.materials[m]["desc"]))):
			miss.append("material." + m)
	for c: String in Defs.consumables.keys():
		for f in ["name", "short", "pack", "desc"]:
			if L.has_cyr(GameWindow.cons_text(c, f)):
				miss.append("consumable.%s.%s" % [c, f])
	for s: String in Defs.suppliers.keys():
		if L.has_cyr(GameWindow.supplier_text(s)) or L.has_cyr(GameWindow.supplier_text(s, "desc")):
			miss.append("supplier." + s)
	for pr: String in Defs.processes.keys():
		if L.has_cyr(Defs.process_name(pr)):
			miss.append("process." + pr)
	for d: String in Defs.departments.keys():
		var dd: Dictionary = Defs.departments[d]
		if L.has_cyr(GameWindow.dept_name(d)) or L.has_cyr(L.dt("department.%s.desc" % d, str(dd["desc"]))):
			miss.append("department." + d)
		for gi in (dd.get("gives", []) as Array).size():
			if L.has_cyr(L.dt("department.%s.gives%d" % [d, gi], str(dd["gives"][gi]))):
				miss.append("department.%s.gives%d" % [d, gi])
	for g: Dictionary in Defs.grants:
		for f in ["title", "org", "desc"]:
			if L.has_cyr(Grants.text(g, f)):
				miss.append("grant.%s.%s" % [str(g["id"]), f])
		for gi in (g.get("goals", []) as Array).size():
			if L.has_cyr(Grants.goal_text(g, gi)):
				miss.append("grant.%s.goal%d" % [str(g["id"]), gi])
	check(miss.is_empty(), "все тексты данных куска A переведены %s" % str(miss.slice(0, 10)))
	check(L.pl(3, "день|дня|дней") == "days" and Defs.plural(1, "неделя", "недели", "недель") == "week", "склонение: days, week")

	for scn: String in ["garage", "sandbox"]:
		print("— окна, сценарий %s" % scn)
		Game.pending = "new"
		Game.pending_scn = scn
		Game.pending_profile = "mech"
		Game.pending_opts = {"tutorial": false}
		Game.pending_seed = 141
		Game.settings["tutorial_done"] = true
		var gm: GameMain = load("res://scenes/game.tscn").instantiate()
		add_child(gm)
		await _wait(8)
		var sim: Sim = gm.sim
		sim.money = maxf(sim.money, 900000.0)
		for i in 3:
			sim.post_ad("turner")
		if not sim.candidates.is_empty():
			sim.hire(0)
		await _wait(2)
		var hud: Node = gm.hud
		var foreign := _foreign(sim)
		for grp: String in GameWindow.GROUPS.keys():
			hud.call("close_window")
			hud.call("open_window", grp)
			await _wait(3)
			var win: GameWindow = hud.get("win")
			if win == null:
				check(false, "окно %s открылось" % grp)
				continue
			for sdef: Array in GameWindow.GROUPS[grp]["secs"]:
				if SKIP_KINDS.has(str(sdef[3])):
					continue
				win.call("_open_sec", str(sdef[0]))
				await _wait(3)
				foreign = _foreign(sim)
				_no_cyr(win, "%s · %s → %s" % [scn, grp, str(sdef[0])], foreign)
				_fits(win, "%s · %s → %s" % [scn, grp, str(sdef[0])])
		hud.call("close_window")
		gm.queue_free()
		await _wait(4)
	print("— чужие строки с кириллицей (переводят другие куски): %d" % foreign_seen.size())
	for k: String in foreign_seen.keys().slice(0, 30):
		print("    · " + k)
	L.apply("ru")
	check(Defs.product_name("bushing") == "Втулка", "обратно на русский: «Втулка»")
	Game.settings["lang"] = ""
	if fails.is_empty():
		print("РЕЗУЛЬТАТ: OK")
		get_tree().quit(0)
	else:
		print("РЕЗУЛЬТАТ: ОШИБКИ (%d): %s" % [fails.size(), "; ".join(fails)])
		get_tree().quit(1)
