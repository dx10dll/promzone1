extends SceneTree
## Тест 1.58 «Логистика, этап 4»: данные окна «Склад и логистика», сетка потока грузов (копится и затухает), разметка пола.
## godot --headless --path . --audio-driver Dummy -s res://tests/stage158b_test.gd

const S := preload("res://tests/setups.gd")

var fails: Array[String] = []


func check(cond: bool, what: String) -> void:
	print(("  ✓ " if cond else "  ✗ ") + what)
	if not cond:
		fails.append(what)


func _initialize() -> void:
	Defs.load_all()
	var g := Scenario.new_game("garage", "mech", "calm", 1583)
	g.story.enabled = false
	g.progress.tutorial = -1
	g.bmats.enabled = false
	S.big_shop(g, false)

	print("— окно: данные")
	var ov := g.logi.overview()
	var st: Dictionary = ov["storage"]
	check(st.keys().size() == 4, "четыре типа склада")
	var cap_before := int((st["metal"] as Array)[1])
	var pr: Thing = g.place_thing("pallet_raw", Vector2i(33, 17), true, false)
	for i in 5:
		g.put_in_thing(g.new_item("mat", "bar45", "raw"), pr, 0)
	var st2: Dictionary = g.logi.storage_fill()
	check(int((st2["metal"] as Array)[1]) == cap_before + 12, "поддон заготовок добавил 12 к вместимости металла")
	check(int((st2["metal"] as Array)[0]) >= 5, "занято металла считается (%d)" % int((st2["metal"] as Array)[0]))
	var pf: Thing = g.place_thing("pallet", Vector2i(35, 17), true, false)
	g.put_in_thing(g.new_item("part", "pin", "ok"), pf, 0)
	var st3: Dictionary = g.logi.storage_fill()
	check(int((st3["finished"] as Array)[1]) >= 16 and int((st3["finished"] as Array)[0]) >= 1, "готовое: поддон учтён")
	var lab := S.hire(g, "laborer", "haul", 5)
	lab.present = true
	var hv: Dictionary = g.logi.haulers()
	check(int(hv["total"]) >= 1 and int(hv["busy"]) == 0, "носильщики: всего %d, заняты 0" % int(hv["total"]))
	var t := Task.new()
	t.kind = "haul_cell"
	lab.task = t
	check(int(g.logi.haulers()["busy"]) == 1, "разнорабочий с задачей переноски считается занятым")
	lab.task = null
	var cnt: Array = g.logi.overview()["stages"]
	check(cnt.size() == 4, "четыре звена цепочки заказов")
	for o0: Dictionary in g.orders.list.duplicate():
		g.orders.list.erase(o0)
	var o := g.orders.make_offer("pin")
	o["qty"] = 10
	o["status"] = "offer"
	g.orders.list.append(o)
	g.orders.accept(int(o["id"]), true)
	check(int(g.logi.overview()["stages"][0]) == 1, "принятый заказ — «в производстве»")
	g.logi.problems()
	check(g.logi.overview()["problems"] is Array and g.logi.overview()["schedule"] is Array, "проблемы и расписание — массивы")

	print("— проблемы: зона без прохода и полная")
	var g2 := Scenario.new_game("garage", "mech", "calm", 1584)
	g2.story.enabled = false
	check(g2.logi.problems() is Array, "на старте проблем-массив строится")

	print("— сетка потока")
	var lg := g.logi
	lg.heat_reset()
	lg.heat_add(Vector2i(10, 10), 5.0, false)
	lg.heat_add(Vector2i(11, 11), 2.0, true)   # тот же блок 2×2
	check(is_equal_approx(lg.heat_at(Vector2i(10, 10)), 7.0), "блок 2×2 копит время: %.1f" % lg.heat_at(Vector2i(10, 10)))
	check(is_equal_approx(lg.jam_at(Vector2i(10, 10)), 2.0), "ожидание копится отдельно")
	check(lg.heat_at(Vector2i(14, 10)) == 0.0, "в другом блоке пусто")
	var before := lg.heat_at(Vector2i(10, 10))
	for k in 400:
		lg.tick_traffic(1.0)
	var after := lg.heat_at(Vector2i(10, 10))
	check(after < before * 0.2 and after > 0.0, "след затухает (%.2f → %.2f)" % [before, after])
	check(lg.jam_at(Vector2i(10, 10)) < 2.0 * 0.2, "красное тоже остывает")
	# носильщик стоит на ходу — красное
	lg.heat_reset()
	var lw := S.hire(g, "laborer", "haul", 5)
	lw.present = true
	lw.pos = Vector2(20.5, 20.5)
	var tk := Task.new()
	tk.kind = "haul_cell"
	tk.add({"t": "goto", "cell": Vector2i(25, 25)})
	lw.task = tk
	for k in 6:
		lg.tick_traffic(0.5)
	check(lg.heat_at(Vector2i(20, 20)) > 2.0, "носильщик оставил след")
	check(lg.jam_at(Vector2i(20, 20)) > 1.5, "стоящий на ходу носильщик — пробка (%.1f)" % lg.jam_at(Vector2i(20, 20)))
	lw.task = null
	# сохранение на новую игру не ломается
	lg.from_dict(lg.to_dict())
	check(lg.heat.size() == 0, "после загрузки сетка пуста и пересоздаётся")

	print("— разметка пола")
	var gz := Scenario.new_game("garage", "mech", "calm", 1585)
	var dt := FloorMarks.data(gz)
	check(not (dt["unload"] as Array).is_empty(), "разметка: зона разгрузки есть (%d кл.)" % (dt["unload"] as Array).size())
	check(dt.has("ship") and dt.has("buffer"), "разметка: ключи отгрузки и буфера")
	var gm: Sim = g
	var lathe: Thing = null
	for m: Thing in gm.things_of("machine"):
		if m.def_id == "lathe":
			lathe = m
			break
	if lathe:
		lathe.product = "pin"
		lathe.enabled = true
		gm.logi.set_buffer(lathe, 6)
		var d2 := FloorMarks.data(gm)
		check((d2["buffer"] as Array).size() >= 1, "буферная клетка попала в разметку")
	g.dispose()
	g2.dispose()
	gz.dispose()

	print("— значок «Полно»: только когда забит весь склад типа")
	var gf := Scenario.new_game("garage", "mech", "calm", 1587)
	gf.story.enabled = false
	var r1: Thing = gf.place_thing("rack", Vector2i(14, 22), true, false)
	for sl in r1.slot_count():
		for i in r1.slot_cap(sl):
			gf.put_in_thing(gf.new_item("mat", "bar45", "raw"), r1, sl)
	for t0: Thing in gf.things_of("storage"):
		if t0 != r1 and t0.def().get("storage", {}).get("accept", []) == r1.def().get("storage", {}).get("accept", []):
			for sl in t0.slot_count():
				for i in t0.slot_cap(sl):
					gf.put_in_thing(gf.new_item("mat", "bar45", "raw"), t0, sl)
	check(ObjectBadges.reason(gf, r1).get("k", "") == "full", "единственный (все забиты) стеллаж — «Полно»")
	var r2: Thing = gf.place_thing("rack", Vector2i(14, 24), true, false)
	check(ObjectBadges.reason(gf, r1).get("k", "") != "full", "поставили ещё стеллаж — значок у полного пропал")
	for sl in r2.slot_count():
		for i in r2.slot_cap(sl):
			gf.put_in_thing(gf.new_item("mat", "bar45", "raw"), r2, sl)
	check(ObjectBadges.reason(gf, r2).get("k", "") == "full", "новый тоже забит — снова «Полно»")
	var pl: Thing = gf.place_thing("pallet", Vector2i(16, 22), true, false)
	check(ObjectBadges.reason(gf, r2).get("k", "") == "full", "поддон готовой продукции — другой тип, металл всё равно полон")
	gf.dispose()

	print("— грузчики водителя носят и стройматериалы (раньше стояли без дела, потом груз «появлялся» в зоне)")
	var gb := Scenario.new_game("garage", "mech", "calm", 1586)
	gb.story.enabled = false
	gb.progress.tutorial = -1
	gb.workers.clear()
	var bkey := str(Defs.build_mats.keys()[0])
	gb.bmats.orders.append({"id": gb.new_id(), "mats": {bkey: 10}, "eta": gb.minute, "spawned": false})
	var tt := 0.0
	var in_hands := 0
	var dumped := false
	var arrived := -1.0
	var done_at := -1.0
	var crew_seen := false
	while tt < 400.0 and done_at < 0.0:
		gb.tick(0.5)
		tt += 0.5
		for v: Vehicle in gb.vehicles:
			if v.kind == "delivery" and v.state == "parked":
				if arrived < 0.0:
					arrived = tt
				crew_seen = crew_seen or not gb.logi.crew_of(v).is_empty()
		for it: Item in gb.items.values():
			if it.kind == "bmat" and it.loc == Item.Loc.WORKER:
				in_hands += 1
		if arrived >= 0.0 and gb.vehicles.filter(func(x: Vehicle) -> bool: return x.kind == "delivery").is_empty():
			done_at = tt
	var on_floor := 0
	for gid in gb.ground_items:
		var it2: Item = gb.items.get(gid)
		if it2 and it2.kind == "bmat" and gb.logi.in_zone(it2.cell):
			on_floor += 1
	check(crew_seen, "у стройматериалов вышли грузчики водителя")
	check(in_hands > 0, "поддоны видно в руках грузчиков (%d кадров), а не телепортом" % in_hands)
	check(on_floor == 10, "все 10 единиц стройматериала легли в зону разгрузки (%d)" % on_floor)
	check(done_at > 0.0 and done_at - arrived < 200.0, "машина уехала без «водитель не дождался» (%.0f мин на воротах)" % (done_at - arrived))
	gb.dispose()

	print("")
	if fails.is_empty():
		print("ВСЕ ПРОВЕРКИ ПРОЙДЕНЫ")
	else:
		print("ПРОВАЛЕНО: %d" % fails.size())
		for f in fails:
			print("  - " + f)
	quit(0 if fails.is_empty() else 1)
