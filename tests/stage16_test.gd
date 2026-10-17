extends SceneTree
## Тест версии 1.6 «Инженерные сети»: дым от сварки и вентиляция, вытяжной зонт, сжатый воздух,
## своя котельная и авария на теплотрассе, СОУТ с доплатами и молоком, СИЗ, проверки, сохранение.
## godot --headless --path . -s res://tests/stage16_test.gd

const S := preload("res://tests/setups.gd")

var fails: Array[String] = []


func check(cond: bool, what: String) -> void:
	print(("  ✓ " if cond else "  ✗ ") + what)
	if not cond:
		fails.append(what)


func _run(sim: Sim, minutes: float) -> void:
	var end := sim.minute + minutes
	while sim.minute < end:
		sim.tick(0.5)


## Сварочный участок: отдельное помещение с постом, окном и дверью.
func _weld_room(sim: Sim) -> Rooms.Room:
	S._box(sim, Rect2i(2, 3, 9, 7), 1, Vector2i(10, 6))
	sim.world.wall[sim.world.idx(Vector2i(5, 3))] = World.W_WINDOW
	sim.world.refresh_all()
	sim.place_thing("weld_post", Vector2i(4, 5), true, false)
	Scenario.autowire(sim)
	sim.rooms.update()
	var r := sim.rooms.room_at(Vector2i(6, 7))
	sim.rooms.assign(r, "workshop")
	sim.rooms.update()
	return sim.rooms.room_at(Vector2i(6, 7))


func _init() -> void:
	Defs.load_all()
	print("— дым от сварки и вентиляция")
	var sim := Scenario.new_game("garage", "mech", "calm", 41)
	sim.story.enabled = false
	sim.money = 3000000.0
	sim.progress.stage = maxi(sim.progress.stage, 3)
	var r := _weld_room(sim)
	var wp: Thing = sim.things_of("machine").filter(func(m: Thing) -> bool: return m.def_id == "weld_post")[0]
	wp.working = true
	sim.eng._vent_update()
	var eq0 := sim.eng.eq_fumes(r)
	check(sim.eng.needs_vent(r), "помещению со сваркой нужна вентиляция")
	sim.eng._fumes_step(3.0)
	var f0 := sim.eng.fumes_of(r)
	check(f0 >= Eng.STUFFY, "без вентиляции за 3 часа сварки — дым: %d%% (равновесие %d%%)" % [int(f0), int(eq0)])
	var welder := S.hire(sim, "welder", "welding", 6)
	welder.present = true
	welder.dressed = true
	welder.ppe = 0.0
	welder.pos = Vector2(5.5, 7.5)
	sim.eng._thoughts()
	check(welder.thoughts.any(func(t: Dictionary) -> bool: return str(t["id"]) in ["stuffy", "fumes"]), "сварщику душно")
	check(sim.eng.speed_k(welder) < 1.0 or f0 < Eng.SMOKY, "в дыму работают медленнее")
	var viol: Array = sim.inspect.violations("sanitary")
	check(viol.any(func(v: Dictionary) -> bool: return str(v["key"]) == "no_vent"), "санитарный надзор: нет вентиляции")
	# вентилятор в помещении, под током
	var fan := sim.place_thing("vent_fan", Vector2i(9, 4), true, false)
	Scenario.autowire(sim)
	sim.power.tick(0.1)
	sim.eng._vent_update()
	check(sim.power.powered(fan) and sim.eng.fan_ok(fan), "вентилятор под напряжением")
	check(sim.eng.vent_k(r) >= 0.5, "кратность воздухообмена ×%.1f" % sim.eng.vent_k(r))
	sim.eng._fumes_step(3.0)
	var f1 := sim.eng.fumes_of(r)
	check(f1 < f0 * 0.6, "с вентиляцией дыма меньше: %d%% → %d%%" % [int(f0), int(f1)])
	# зонт над постом, воздуховод к вентилятору
	var hood := sim.place_thing("vent_hood", Vector2i(5, 4), true, false)
	Scenario.autoline(sim, "duct", fan.cell, [hood.cell])
	sim.eng._vent_update()
	check(sim.eng.hood_ok(hood), "зонт подключён к вентилятору воздуховодом")
	check(bool(sim.eng.hooded.get(wp.id, false)), "сварочный пост под зонтом")
	var eq2 := sim.eng.eq_fumes(r)
	check(eq2 < eq0 * 0.3, "зонт и вентилятор: равновесный дым %d%% → %d%%" % [int(eq0), int(eq2)])
	sim.eng._clean_air_check()
	check(int(sim.stats.get("clean_air", 0)) == 1, "достижение «Чистый воздух»")
	viol = sim.inspect.violations("sanitary")
	check(not viol.any(func(v: Dictionary) -> bool: return str(v["key"]) == "no_vent"), "к вентиляции претензий нет")
	wp.working = false

	print("— сжатый воздух")
	var pb := sim.place_thing("paint_booth", Vector2i(30, 10), true, false)
	var asm := sim.place_thing("assembly_table", Vector2i(26, 14), true, false)
	Scenario.autowire(sim)
	sim.eng._air_update()
	var painter := S.hire(sim, "painter", "paint", 5)
	var fitter := S.hire(sim, "assembler", "assembly", 5)
	pb.product = "bracket"
	asm.product = "drive_unit"
	var t_brush := sim.brain._op_time(painter, pb)
	var t_asm0 := sim.brain._op_time(fitter, asm)
	check(is_equal_approx(sim.eng.air_time_k(pb), 1.6), "без компрессора красят кистью: ×1.6")
	var comp := sim.place_thing("compressor", Vector2i(22, 16), true, false)
	Scenario.autowire(sim)
	Scenario.autoline(sim, "air", comp.cell, [pb.inlet_cell(), asm.inlet_cell()])
	sim.power.tick(0.1)
	sim.eng._air_update()
	check(sim.eng.pressure(pb) >= 0.99 and sim.eng.pressure(asm) >= 0.99, "пневмомагистраль от компрессора дошла до камеры и сборки")
	var t_spray := sim.brain._op_time(painter, pb)
	var t_asm1 := sim.brain._op_time(fitter, asm)
	check(t_spray < t_brush * 0.7, "краскопульт быстрее кисти: %.0f против %.0f мин" % [t_spray, t_brush])
	check(t_asm1 < t_asm0 * 0.85, "пневмогайковёрт ускоряет сборку: %.0f против %.0f мин" % [t_asm1, t_asm0])
	pb.working = true
	sim.eng._air_update()
	check(sim.eng.compressor_running(comp), "компрессор качает, когда камера работает")
	check(sim.season.noise_at(comp.cell + Vector2i(0, 2)) >= 80.0, "компрессор шумит: %d дБ" % int(sim.season.noise_at(comp.cell + Vector2i(0, 2))))
	pb.working = false

	print("— котельная")
	var hs := Scenario.new_game("garage", "mech", "calm", 8)
	hs.story.enabled = false
	hs.money = 3000000.0
	hs.progress.stage = maxi(hs.progress.stage, 3)
	S._box(hs, Rect2i(2, 3, 5, 5), 1, Vector2i(6, 5))
	var boiler := hs.place_thing("boiler", Vector2i(3, 4), true, false)
	hs.place_thing("water_inlet", Vector2i(2, 12), true, false)
	Scenario.autowire(hs)
	Scenario.autopipe(hs)
	hs.rooms.update()
	hs.rooms.assign(hs.rooms.room_at(Vector2i(3, 4)), "boiler_room")
	hs.rooms.update()
	var rad1 := hs.place_thing("radiator", Vector2i(17, 10), true, false)
	var rad2 := hs.place_thing("radiator", Vector2i(26, 10), true, false)
	Scenario._route_layer(hs, "pipe", [rad1.cell])
	hs.world.pipe_rev += 1
	hs.power.tick(0.1)
	hs.eng._boiler_update()
	check(hs.eng.boiler_problem(boiler) == "", "котёл в котельной, с водой и током: %s" % hs.eng.boiler_problem(boiler))
	check(hs.eng.boiler_rads.has(rad1.id) and not hs.eng.boiler_rads.has(rad2.id), "батарея на трубе котла — от котла, другая — от теплосети")
	hs.story.add_mod("heat_off", 1.0, 1440.0, "тест")
	check(hs.eng.radiator_on(rad1) and not hs.eng.radiator_on(rad2), "авария на теплотрассе: греет только своя котельная")
	hs.story.remove_mod("heat_off")
	# счёт за тепло: своя котельная дешевле
	hs.season.start_month = 0
	hs.season.temp_day = -10.0
	var m0 := hs.money
	hs.season.on_new_day()
	var bill := m0 - hs.money
	var city_only := 2.0 * Defs.sea("heat_cost_radiator_day") * clampf((18.0 - hs.season.temp_day - (hs.season.snap if hs.minute < hs.season.snap_until else 0.0)) / 18.0, 0.3, 2.2)
	check(hs.season.heating_season() and bill > 0.0 and bill < city_only * 0.85, "счёт за тепло с котельной %s вместо %s" % [Defs.money_str(bill), Defs.money_str(city_only)])
	hs.dispose()

	print("— СОУТ, доплата и молоко")
	var mill := sim.place_thing("mill", Vector2i(16, 16), true, false)
	Scenario.autowire(sim)
	sim.power.tick(0.1)
	var nm := sim.eng.unassessed()
	check(nm >= 3, "рабочих мест без СОУТ: %d" % nm)
	for i in 3:
		S.hire(sim, "laborer", "haul", 4)
	var lv: Array = sim.inspect.violations("labor")
	check(lv.any(func(v: Dictionary) -> bool: return str(v["key"]) == "no_sout"), "трудовая инспекция: нет СОУТ")
	var cost := sim.eng.sout_price(false)
	var mm := sim.money
	check(sim.eng.start_sout(false) == "" and absf(mm - sim.money - cost) < 1.0, "лаборатория вызвана за %s" % Defs.money_str(cost))
	check(sim.eng.start_sout(false) != "", "второй раз не вызвать, пока идут замеры")
	_run(sim, 3.0 * 1440.0)
	check(not sim.eng.sout_busy() and sim.eng.unassessed() == 0, "СОУТ завершена")
	check(int(sim.stats.get("sout_done", 0)) == 1, "достижение «Аттестация пройдена»")
	var mcls := sim.eng.class_of(mill)
	check(mcls >= 1, "фрезерный станок шумит — вредный класс %s" % Eng.CLASS_NAMES[maxi(0, mcls)])
	var wcls := sim.eng.class_of(wp)
	check(wcls >= 0 and wcls <= mcls + 1, "сварка под зонтом: класс %s" % Eng.CLASS_NAMES[maxi(0, wcls)])
	var miller := S.hire(sim, "miller", "milling", 6)
	miller.workplace = mill.id
	check(sim.eng.harm_bonus(miller) >= 0.04, "фрезеровщику доплата %d%%" % int(sim.eng.harm_bonus(miller) * 100.0))
	check(sim.eng.entitled_milk(miller), "фрезеровщику положено молоко")
	lv = sim.inspect.violations("labor")
	check(lv.any(func(v: Dictionary) -> bool: return str(v["key"]) == "no_milk"), "молоко не дают — нарушение")
	sim.eng.milk_on = true
	var due0: float = float(miller.get_meta("wage_due", 0.0))
	sim.brain._spawn(miller)
	var paid: float = float(miller.get_meta("wage_due", 0.0)) - due0
	check(paid > float(miller.wage) * 1.03, "за смену начислено с доплатой: %s при ставке %s" % [Defs.money_str(paid), Defs.money_str(miller.wage)])
	check(miller.thoughts.any(func(t: Dictionary) -> bool: return str(t["id"]) == "milk"), "выдали молоко")
	var mb := sim.money
	sim.eng.morning()
	check(sim.money < mb, "молоко оплачено: %s" % Defs.money_str(mb - sim.money))
	lv = sim.inspect.violations("labor")
	check(not lv.any(func(v: Dictionary) -> bool: return str(v["key"]) in ["no_milk", "no_sout"]), "СОУТ есть, молоко дают — претензий нет")

	print("— СИЗ")
	sim.candidates.clear()
	sim.refresh_candidates()
	sim.hire(0)
	var nw: Worker = sim.workers[-1]
	check(nw.ppe == 0.0 and sim.eng.injury_k(nw) > 1.0, "новичок без СИЗ: травм ×%.1f" % sim.eng.injury_k(nw))
	check(not sim.eng.wants_ppe(nw), "без шкафа СИЗ взять негде")
	var cab := sim.place_thing("ppe_cabinet", Vector2i(20, 10), true, false)
	sim.cons["ppe"] = 5.0
	check(sim.eng.wants_ppe(nw), "есть шкаф и комплекты — пойдёт за СИЗ")
	nw.present = true
	nw.dressed = true
	nw.pos = Vector2(cab.cell) + Vector2(0.5, 2.5)
	var task := sim.brain._ppe_task(nw)
	check(task != null and task.kind == "ppe", "задача: получить СИЗ")
	sim.brain.assign(nw, task)
	_run(sim, 30.0)
	check(nw.ppe >= 90.0 and float(sim.cons["ppe"]) <= 4.0, "СИЗ выданы, в шкафу осталось %d" % int(sim.cons["ppe"]))
	check(sim.eng.injury_k(nw) == 1.0, "в СИЗ риск травм обычный")
	var p0 := nw.ppe
	sim.eng.on_spawn(nw)
	check(nw.ppe < p0, "СИЗ изнашиваются за смену: %d%%" % int(nw.ppe))

	print("— сохранение")
	sim.eng.fumes[r.id] = 42.0
	var dd := Sim.from_dict(JSON.parse_string(JSON.stringify(sim.to_dict())))
	dd.rooms.update()
	dd.eng._vent_update()
	check(dd.world.has_duct(hood.cell) and dd.world.has_air(pb.inlet_cell()) or dd.world.has_air(pb.inlet_cell() + Vector2i(0, 1)) or dd.world.has_air(pb.inlet_cell() + Vector2i(1, 0)) or dd.world.has_air(pb.inlet_cell() + Vector2i(-1, 0)) or dd.world.has_air(pb.inlet_cell() + Vector2i(0, -1)), "воздуховоды и пневмомагистраль сохраняются")
	check(dd.eng.class_of(dd.things[mill.id]) == mcls and dd.eng.milk_on, "СОУТ и молоко сохраняются")
	check(absf(dd.eng.fumes_of(dd.rooms.room_at(Vector2i(6, 7))) - 42.0) < 0.1, "дым в помещении сохраняется")
	var dw: Worker = dd.get_worker(nw.id)
	check(dw != null and absf(dw.ppe - nw.ppe) < 0.01 and dd.get_worker(miller.id).workplace == mill.id, "СИЗ и рабочее место сохраняются")
	dd.dispose()
	sim.dispose()
	print("РЕЗУЛЬТАТ: ", "OK" if fails.is_empty() else "ОШИБКИ: " + ", ".join(fails))
	quit(0 if fails.is_empty() else 1)
