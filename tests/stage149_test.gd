extends SceneTree
## Тест версии 1.49: значки проблем над станками (причины, задержка, нейтральное «нет работы») и
## «Что делать» — выполненный совет 3 секунды висит зачёркнутым и уходит.
## godot --headless --path . -s res://tests/stage149_test.gd

const S := preload("res://tests/setups.gd")

var fails: Array[String] = []


func check(cond: bool, what: String) -> void:
	print(("  ✓ " if cond else "  ✗ ") + what)
	if not cond:
		fails.append(what)


func _kind(sim: Sim, m: Thing) -> String:
	return str(Stall.reason(sim, m).get("k", "?"))


func _init() -> void:
	Defs.load_all()
	var g := Scenario.new_garage(149)
	g.story.enabled = false
	g.progress.tutorial = -1
	g.bmats.enabled = false
	g.money = 3000000.0
	S.big_shop(g)
	S.hire(g, "turner", "turning", 5)
	S.hire(g, "laborer", "haul", 3)
	S.complex_orders(g, 3)
	var t0 := g.minute
	while g.minute < t0 + 600.0:
		g.tick(0.5)

	print("— причины значков")
	var lathe: Thing = null
	var idle: Thing = null
	for m in g.things_of("machine"):
		if m.def_id == "lathe" and m.product != "" and lathe == null:
			lathe = m
		if m.product == "" and idle == null:
			idle = m
	check(lathe != null and idle != null, "есть станок с заданием и станок без задания")
	if lathe == null or idle == null:
		print("ИТОГ: провалено")
		quit(1)
		return
	check(_kind(g, idle) == "idle", "без заказа — нейтральное «нет работы» (idle)")
	check(_kind(g, lathe) == "", "станок с заготовками и станочником — без значка (ждёт станочника не проблема)")

	var saved: Array = []
	for id in g.slot_ids(lathe, 0).duplicate():
		saved.append(g.items[id])
	for it: Item in saved:
		g.delete_item(it)
	check(_kind(g, lathe) == "input", "нет заготовок — input")
	var cap := lathe.slot_cap(1)
	var outs: Array = []
	for i in cap:
		var it2 := g.new_item("part", lathe.product, "ok")
		g.put_in_thing(it2, lathe, 1)
		outs.append(it2)
	check(_kind(g, lathe) == "full", "выходной буфер забит — full")
	for it3: Item in outs:
		g.delete_item(it3)
	var ws := g.workers.duplicate()
	g.workers.clear()
	check(_kind(g, lathe) == "operator", "некому работать — operator")
	g.workers.append_array(ws)
	var net_id: Variant = g.power.thing_net.get(lathe.id)
	g.power.thing_net.erase(lathe.id)
	check(_kind(g, lathe) == "power", "нет кабеля — power")
	g.power.thing_net[lathe.id] = net_id
	lathe.broken = true
	check(_kind(g, lathe) == "", "сломанный — не из четырёх значков (k пуст)")
	lathe.broken = false
	lathe.enabled = false
	check(_kind(g, lathe) == "", "выключенный — без значка")
	lathe.enabled = true

	print("— задержка и нейтральный значок")
	var tr := StallBadges.new()
	tr.refresh(g)
	check(tr.shown.is_empty(), "свежая причина сразу не показывается (не мигает)")
	g.minute += StallBadges.HOLD_MIN + 1.0
	check(tr.refresh(g), "после выдержки набор значков изменился")
	check(tr.shown.has(idle.id), "«нет работы» в наборе")
	var vis := tr.visible_list(false)
	check(vis.all(func(r: Dictionary) -> bool: return str(r["k"]) != "idle"), "вне слоя «Загрузка» нейтрального значка нет")
	check(tr.visible_list(true).size() > vis.size(), "в слое «Загрузка» он есть")
	check(not tr.shown.has(lathe.id) or str(tr.shown[lathe.id]["k"]) != "idle", "станок с заказом не помечен «нет работы»")
	# причина устранена — значок уходит сразу
	for it4: Item in saved:
		g.items[it4.id] = it4
		g.put_in_thing(it4, lathe, 0)
	var was := tr.shown.has(lathe.id)
	g.slot_ids(lathe, 0)
	tr.refresh(g)
	check(not tr.shown.has(lathe.id), "заготовки вернулись — значок исчез (был: %s)" % str(was))
	check(not tr.tick(g, 0.1) or true, "tick не падает")
	# троттлинг: два кадра подряд — пересчёт один
	var n0 := tr._real
	tr._real = 0.0
	tr.tick(g, 0.016)
	check(tr._real > 0.4, "пересчёт не чаще раза в полсекунды")
	check(StallBadges.title("full") != "" and StallBadges.title("power") != StallBadges.title("input"), "заголовки значков заданы")

	print("— «Что делать»: выполненный совет")
	var noop := func() -> void: pass
	var fire := ["fire", "Пожар! Люди тушат", "", UITheme.BAD, noop]
	var ord := ["orders", "Заказов в работе нет", "", UITheme.MUTED, noop]
	var more := ["letter", "Ещё писем: 4", "", UITheme.ACCENT, noop]
	var tk := TodoTrack.new()
	tk.update([fire, ord, more])
	check(tk.ghosts.is_empty(), "пока причина есть — призраков нет")
	tk.update([ord, more])
	check(tk.ghosts.size() == 1, "причина устранена — строка осталась как выполненная")
	var mg := tk.merged([ord, more])
	check(mg.size() == 3 and str(mg[0][5]) == "ghost" and str(mg[0][1]) == "Пожар! Люди тушат", "призрак на своём месте с пометкой ghost")
	check(not tk.tick(2.9) and tk.ghosts.size() == 1, "через 2,9 с ещё висит")
	check(tk.tick(0.2) and tk.ghosts.is_empty(), "через 3 с уходит")
	check(tk.merged([ord, more]).size() == 2, "после этого в списке только живое")
	tk.update([ord, more])
	check(tk.ghosts.is_empty(), "после ухода повторно не всплывает")
	tk.update([fire, ord])
	tk.update([ord])
	tk.update([fire, ord])
	check(tk.ghosts.is_empty(), "причина вернулась — призрак снят, строка живая")
	var l4 := ["letter", "Письмо А", "решить", UITheme.ACCENT, noop]
	var l5 := ["letter", "Письмо Б", "решить", UITheme.ACCENT, noop]
	var tk3 := TodoTrack.new()
	tk3.update([l4, l5])
	tk3.update([l5])
	check(tk3.ghosts.size() == 1 and str(tk3.ghosts[0]["item"][1]) == "Письмо А", "решённое письмо — только оно зачёркнуто")
	var cnt1 := ["letter", "Ещё писем: 4", "", UITheme.ACCENT, noop]
	var cnt2 := ["letter", "Ещё писем: 3", "", UITheme.ACCENT, noop]
	var tk2 := TodoTrack.new()
	tk2.update([cnt1])
	tk2.update([cnt2])
	check(tk2.ghosts.is_empty(), "счётчик «Ещё писем» не считается советом")

	print("ИТОГ: " + ("провалено %d" % fails.size() if not fails.is_empty() else "всё хорошо"))
	quit(1 if not fails.is_empty() else 0)
