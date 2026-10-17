extends SceneTree
## Тест версии 1.18 «Сети»: подстанция 2×2 и аккумуляторы, насосная, техпомещение на старте,
## кабель и труба — в клетку прибора, аварии (обрыв провода, прорыв водопровода), штабели поставок,
## дымка и редкий лес на чужих участках, размеры помещений «Ш×Г».
## godot --headless --path . -s res://tests/stage118_test.gd

var fails: Array[String] = []


func check(cond: bool, what: String) -> void:
	print(("  ✓ " if cond else "  ✗ ") + what)
	if not cond:
		fails.append(what)


func run(sim: Sim, minutes: float, until: Callable = Callable()) -> float:
	var t := 0.0
	while t < minutes:
		sim.tick(0.5)
		t += 0.5
		if until.is_valid() and bool(until.call()):
			break
	return t


func _init() -> void:
	Defs.load_all()

	print("— техпомещение на старте")
	for scn in ["garage", "field"]:
		var s := Scenario.new_game(scn, "mech", "calm", 181)
		s.story.enabled = false
		var subs := s.things.values().filter(func(t: Thing) -> bool: return t.def_id == "substation")
		var pumps := s.things.values().filter(func(t: Thing) -> bool: return t.def_id == "pump_house")
		check(subs.size() == 1 and pumps.size() == 1, "%s: одна подстанция и одна насосная" % scn)
		if subs.is_empty() or pumps.is_empty():
			continue
		var sub: Thing = subs[0]
		var pump: Thing = pumps[0]
		var tr := s.rooms.room_of_thing(sub)
		check(tr != null and tr.type == "tech_room" and tr.valid, "%s: техпомещение оборудовано" % scn)
		check(s.power.source_capacity(sub) == 40.0, "%s: подстанция даёт %d кВт" % [scn, int(s.power.source_capacity(sub))])
		check(s.water.pump_running(pump), "%s: насосная качает с первой минуты" % scn)
		var wcs := s.rooms.of_type("wc")
		check(not wcs.is_empty() and (wcs[0] as Rooms.Room).valid, "%s: туалет с водой с первой минуты" % scn)
		var legacy := s.things.values().filter(func(t: Thing) -> bool: return t.def_id in ["cabinet", "water_inlet", "ktp", "pump_station"])
		check(legacy.is_empty(), "%s: старых трансформаторов и скважин нет" % scn)
		s.dispose()

	print("— аккумуляторы у подстанции")
	var g := Scenario.new_game("garage", "mech", "calm", 182)
	g.story.enabled = false
	var sub2: Thing = g.things.get(g.power.grid_input_id())
	check(sub2 != null and sub2.def_id == "substation", "ввод — подстанция")
	var placed := 0
	for y in range(sub2.cell.y - 1, sub2.cell.y + 3):
		for x in range(sub2.cell.x - 1, sub2.cell.x + 3):
			var cc := Vector2i(x, y)
			if placed < 2 and g.can_place("battery", cc) == "":
				g.place_thing("battery", cc, true, false)
				placed += 1
	g.rooms.update()
	check(placed == 2 and g.power.source_capacity(sub2) == 80.0, "два шкафа: %d кВт (40 + 2×20)" % int(g.power.source_capacity(sub2)))
	check(g.can_place("battery", Vector2i(sub2.cell.x + 6, sub2.cell.y)) != "", "вдали от подстанции аккумулятор не ставится")
	check(Defs.objects.has("substation") and not bool(Defs.objects["cabinet"].get("stage", 0)) and bool(Defs.objects["cabinet"].get("legacy", false)), "малый трансформатор — только в старых сохранениях")

	print("— кабель и труба в клетку прибора")
	var lathe: Thing = g.things_of("machine")[0]
	g.power.tick(0.1)
	check(g.power.powered(lathe), "станок под током")
	var inl := lathe.inlet_cell()
	check(g.world.cable[g.world.idx(inl)] == 1, "кабель заведён в розетку станка")
	g.world.cable[g.world.idx(inl)] = 0
	var nb_cable := false
	for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		if g.world.net_at("cable", inl + d) == 1:
			nb_cable = true
	g.world.cable_rev += 1
	g.power.tick(0.1)
	check(nb_cable and not g.power.powered(lathe), "кабель рядом, но не в клетке — станок без тока")
	Scenario.migrate_v10(g)
	g.power.tick(0.1)
	check(g.power.powered(lathe), "старое сохранение: кабель дотянут в клетку автоматически")

	print("— обрыв провода")
	check(g.faults.make("cable", inl), "авария в клетке розетки")
	g.power.tick(0.1)
	check(not g.power.powered(lathe) and g.world.net_at("cable", inl) == 2, "оборвало — станок встал, клетка ждёт ремонта")
	check(g.net_plans().any(func(p: Array) -> bool: return str(p[0]) == "cable" and int(p[1]) == g.world.idx(inl)), "ремонт — в чертежах сетей")
	var d1: Dictionary = JSON.parse_string(JSON.stringify(g.to_dict()))
	var g2 := Sim.from_dict(d1)
	check(g2.faults.at("cable", inl), "авария сохраняется")
	g2.dispose()
	# рабочие чинят сами
	g.minute = maxf(g.minute, float(g.day()) * 1440.0 + 8.0 * 60.0)
	for w in g.workers:
		w.shift_anchor = -1.0
	var t1 := run(g, 8.0 * 60.0, func() -> bool: return g.faults.count() == 0)
	g.power.tick(0.1)
	check(g.faults.count() == 0 and g.power.powered(lathe), "рабочие заменили кусок кабеля за %d мин" % int(t1))

	print("— событие: аварийная бригада")
	g.story.enabled = true
	check(g.story._can("wire_break"), "событие «Обрыв провода» возможно")
	var n_letters := g.story.letters.size()
	g.story._start("wire_break", false)
	check(g.faults.count("cable") == 1 and g.story.letters.size() == n_letters + 1, "письмо с выбором")
	var lt: Dictionary = g.story.letters[-1]
	var money0 := g.money
	g.story.resolve(int(lt["id"]), 0)
	check(absf(money0 - g.money - 9000.0) < 1.0, "бригада стоит 9 000 ₽")
	run(g, 62.0)
	check(g.faults.count("cable") == 0, "бригада починила за час")

	print("— прорыв водопровода")
	var toilet: Thing = g.things_of("toilet")[0]
	check(g.water.has_water(toilet), "у туалета вода")
	var tin := toilet.inlet_cell()
	check(g.faults.make("pipe", tin), "прорыв в клетке туалета")
	check(not g.water.has_water(toilet), "туалет сухой")
	g.story._start("leak", false)
	check(g.faults.count("pipe") >= 1, "событие «Прорыв водопровода» создаёт аварию")
	var t2 := run(g, 10.0 * 60.0, func() -> bool: return g.faults.count("pipe") == 0)
	check(g.faults.count("pipe") == 0 and g.water.has_water(toilet), "трубу заменили за %d мин — вода есть" % int(t2))
	g.dispose()

	print("— поставка штабелями, а не рядком до края карты")
	var h := Scenario.new_game("field", "mech", "calm", 183)
	h.story.enabled = false
	var v := h.spawn_vehicle("delivery")
	for k in 70:
		h.put_in_vehicle(h.new_item("bmat", "bm_brick", "bmat"), v)
	for k2 in 12:
		h.put_in_vehicle(h.new_item("mat", "bar45", "raw"), v)
	h._dump_cargo(v)
	var cells := {}
	var far := 0
	for gid in h.ground_items:
		var it: Item = h.items.get(gid)
		cells[it.cell] = true
		if it.cell.y < h.world.plot.end.y - 10 or not h.world.in_plot(it.cell):
			far += 1
	check(cells.size() <= 8, "82 единицы легли на %d клеток (штабели по 16)" % cells.size())
	check(far == 0, "всё у ворот, на своём участке")
	var pile := h.logi.ground_on(h.items.get(h.ground_items[0]).cell)
	check(pile.size() >= 2, "в штабеле %d шт. — число видно на значке и в карточке" % pile.size())
	h.dispose()

	print("— чужие участки: реже лес")
	var l := Scenario.new_game("garage", "mech", "calm", 184, {"lots": true})
	var area := 0
	var trees := 0
	for k3 in l.world.lots.size():
		var lr := l.world.lot_rect(k3)
		area += lr.get_area()
		for y2 in range(lr.position.y, lr.end.y):
			for x2 in range(lr.position.x, lr.end.x):
				if l.world.flora[l.world.idx(Vector2i(x2, y2))] != 0:
					trees += 1
	check(area > 0 and float(trees) / float(area) < 0.09, "деревьев и кустов: %d на %d клеток (%.1f%%)" % [trees, area, 100.0 * trees / maxf(1.0, area)])
	l.dispose()

	print("— размеры помещений понятные")
	check(Rooms.req_text("workshop").begins_with("помещение от 4×3"), "цех: %s" % Rooms.req_text("workshop"))
	check(Rooms.min_dims("canteen") == Vector2i(3, 3), "столовая от 3×3")
	for t in Rooms.TYPES:
		var md := Rooms.min_dims(t)
		if md.x * md.y < int(Defs.rooms[t].get("min_area", 1)):
			check(false, "%s: %d×%d меньше площади" % [t, md.x, md.y])

	print("РЕЗУЛЬТАТ: " + ("OK" if fails.is_empty() else "ОШИБКИ: " + ", ".join(fails)))
	quit(0 if fails.is_empty() else 1)
