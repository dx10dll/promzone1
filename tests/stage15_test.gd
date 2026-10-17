extends SceneTree
## Тест версии 1.5 «Оснащение и чистота»: стружка от станков, уборщица и контейнер, ломовоз,
## ленточная пила и заготовки, наладчик, уровень обустройства помещений, помещение рамкой.
## godot --headless --path . -s res://tests/stage15_test.gd

const S := preload("res://tests/setups.gd")

var fails: Array[String] = []


func check(cond: bool, what: String) -> void:
	print(("  ✓ " if cond else "  ✗ ") + what)
	if not cond:
		fails.append(what)


func _days(sim: Sim, n: float) -> void:
	var end := sim.minute + n * 1440.0
	while sim.minute < end:
		sim.tick(0.5)


func _init() -> void:
	Defs.load_all()
	print("— стружка и уборка")
	var sim := Scenario.new_game("garage", "mech", "calm", 31)
	sim.story.enabled = false
	sim.money = 800000.0
	var lathe := sim.things_of("machine")[0]
	var op := sim.workers[0]
	op.present = true
	var lsp: Dictionary = lathe.spots()[0]
	op.pos = Vector2(lsp["cell"]) + Vector2(0.5, 0.5)
	var d0 := sim.upkeep.dirt_at(op.cell())
	for i in 8:
		sim.upkeep.on_operation(lathe, op)
	check(sim.upkeep.dirt_at(op.cell()) > d0 + 60, "токарный сыплет стружку у рабочего места: %d" % sim.upkeep.dirt_at(op.cell()))
	var shop := sim.rooms.room_at(lathe.cell + Vector2i(1, 1))
	check(shop != null and sim.upkeep.room_dirt(shop) > 0.0, "грязь в цеху: %.1f, чистота %d%%" % [sim.upkeep.room_dirt(shop), sim.upkeep.cleanliness(shop)])
	# сильно загрязнить пол в цеху
	for c in shop.cells:
		sim.upkeep.add_dirt(c, 200)
	check(sim.upkeep.room_dirt(shop) > Upkeep.VERY_DIRTY, "цех завален стружкой")
	var lv_dirty := sim.upkeep.level(shop)
	sim.upkeep._thoughts()
	check(op.thoughts.any(func(t: Dictionary) -> bool: return str(t["id"]) == "very_dirty"), "людям неприятно: «грязища»")
	check(sim.upkeep.injury_k(op) > 1.0, "на стружке травм больше")
	var viol: Array = sim.inspect.violations("sanitary")
	check(viol.any(func(v: Dictionary) -> bool: return str(v["key"]) == "dirty_room"), "санитарный надзор видит грязь")
	var bin := sim.place_thing("chip_bin", Vector2i(26, 12), true, false)
	var cl := S.hire(sim, "cleaner", "clean", 6)
	check(cl.prof_name() in ["Уборщик", "Уборщица"] and cl.wage < 3000, "уборщица наняты: %s, %s" % [cl.prof_name(), Defs.money_str(cl.wage)])
	_days(sim, 2.0)
	var after := sim.upkeep.room_dirt(shop)
	check(after < Upkeep.DIRTY, "уборщица вычистила цех: средняя грязь %.0f" % after)
	check(sim.upkeep.bin_total() > 10.0 or sim.upkeep.pickups > 0, "стружка в контейнере: %.0f кг" % sim.upkeep.bin_total())
	check(sim.upkeep.level(shop) >= lv_dirty, "чистый цех обустроен не хуже грязного")

	print("— ломовоз")
	sim.upkeep.bin_kg[bin.id] = 200.0
	var scrap := sim.new_item("part", "bushing", "scrap")
	var sbins: Array = sim.things.values().filter(func(x: Thing) -> bool: return x.def_id == "scrap_bin")
	if sbins.is_empty():
		sbins.append(sim.place_thing("scrap_bin", Vector2i(25, 16), true, false))
	sim.put_in_thing(scrap, sbins[0], 0)
	var m0 := sim.money
	var got := sim.upkeep.pickup()
	check(got > 2000.0 and sim.money > m0 and not sim.items.has(scrap.id), "ломовоз заплатил %s за стружку и брак, брак увезли" % Defs.money_str(got))
	check(sim.upkeep.bin_total() == 0.0, "контейнеры опустели")

	print("— ленточная пила и заготовки")
	sim.progress.stage = maxi(sim.progress.stage, 2)
	var saw := sim.place_thing("band_saw", Vector2i(16, 16), true, false)
	Scenario.autowire(sim)
	sim.power.tick(0.1)
	check(sim.power.powered(saw), "пила под напряжением")
	var mat := sim.upkeep.saw_material()
	check(mat != "", "есть что резать: %s" % Defs.material_name(mat))
	S.hire(sim, "laborer", "haul", 6)
	_days(sim, 1.0)
	check(sim.upkeep.blanks_total() > 0, "нарезано заготовок: %d" % sim.upkeep.blanks_total())
	var w2 := sim.workers[0]
	lathe.product = "bushing"
	lathe.job_step = 0
	sim.upkeep.blanks["bar45"] = 5
	var t_with := sim.brain._op_time(w2, lathe)
	sim.upkeep.blanks["bar45"] = 0
	var t_without := sim.brain._op_time(w2, lathe)
	check(t_with < t_without * 0.85, "из готовой заготовки быстрее: %.1f против %.1f мин" % [t_with, t_without])

	print("— наладчик")
	var st := S.hire(sim, "setter", "setup", 7)
	check(st.prof_name() == "Наладчик" and st.skill("setup") == 7, "наладчик нанят")
	st.present = true
	var lsp2: Dictionary = lathe.spots()[0]
	st.pos = Vector2(lsp2["cell"]) + Vector2(0.5, 0.5)
	lathe.product = "shaft"
	lathe.setup_key = ""
	lathe.user = -1
	var sp0: Dictionary = lathe.spots()[0]
	var t := sim.brain._make_task(st, {"k": "presetup", "t": lathe, "spot": sp0, "key": "shaft:0"})
	check(t != null and t.kind == "presetup", "наладчик берётся наладить станок заранее")

	print("— обустройство помещений")
	var off := Scenario.new_game("garage", "mech", "calm", 5)
	S._box(off, Rect2i(2, 3, 6, 5), 3, Vector2i(7, 5))
	off.rooms.update()
	var r := off.rooms.room_at(Vector2i(4, 5))
	off.rooms.assign(r, "restroom")
	off.place_thing("bench", Vector2i(3, 4), true, false)
	off.place_thing("cooler", Vector2i(5, 4), true, false)
	off.rooms.update()
	r = off.rooms.room_at(Vector2i(4, 5))
	var l1 := off.upkeep.level(r)
	for c in [Vector2i(3, 6), Vector2i(4, 6), Vector2i(6, 4)]:
		off.place_thing(["palm", "bookcase", "pennant"][[Vector2i(3, 6), Vector2i(4, 6), Vector2i(6, 4)].find(c)], c, true, false)
	off.place_thing("aquarium", Vector2i(5, 6), true, false)
	off.rooms.update()
	r = off.rooms.room_at(Vector2i(4, 5))
	var l2 := off.upkeep.level(r)
	check(l2 > l1, "декор поднимает уровень: %d → %d" % [l1, l2])
	var wk := off.workers[0]
	wk.present = true
	wk.pos = Vector2(4.5, 5.5)
	off.upkeep._thoughts()
	check(wk.thoughts.any(func(x: Dictionary) -> bool: return str(x["id"]).begins_with("room_l")), "человек в комнате замечает обустройство")
	off.dispose()

	print("— помещение рамкой")
	var g := Scenario.new_game("garage", "mech", "calm", 6)
	g.money = 500000.0
	var m1 := g.money
	check(g.place_room_bp(Rect2i(3, 3, 6, 5), 3) == "", "рамка принята")
	var walls := 0
	var floors := 0
	for y in range(3, 8):
		for x in range(3, 9):
			var i := g.world.idx(Vector2i(x, y))
			if g.world.bp_wall[i] != World.BP_NONE:
				walls += 1
			if g.world.bp_floor[i] == 3:
				floors += 1
	var door := g.room_door_cell(Rect2i(3, 3, 6, 5))
	check(walls == 18 and floors == 30, "чертёж: %d стен, %d клеток линолеума" % [walls, floors])
	check(g.world.bp_wall[g.world.idx(door)] == World.W_DOOR, "дверь посередине нижней стены")
	check(m1 - g.money > 0.0, "оплачено %s" % Defs.money_str(m1 - g.money))
	check(g.place_room_bp(Rect2i(3, 3, 2, 5), 3) != "", "узкую рамку не принимает")
	g.dispose()

	print("— сохранение")
	sim.upkeep.blanks["bar45"] = 7
	sim.upkeep.add_dirt(Vector2i(20, 12), 99)
	var dd := Sim.from_dict(JSON.parse_string(JSON.stringify(sim.to_dict())))
	check(int(dd.upkeep.blanks.get("bar45", 0)) == 7 and dd.upkeep.dirt_at(Vector2i(20, 12)) == sim.upkeep.dirt_at(Vector2i(20, 12)), "грязь и заготовки сохраняются")
	dd.dispose()
	sim.dispose()
	print("РЕЗУЛЬТАТ: ", "OK" if fails.is_empty() else "ОШИБКИ: " + ", ".join(fails))
	quit(0 if fails.is_empty() else 1)
