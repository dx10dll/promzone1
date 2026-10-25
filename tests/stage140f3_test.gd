extends SceneTree
## Тест 1.40 (f3): директор — аватар игрока, свои зоны у людей, столовая для ИТР и обед из дома,
## логистика быта (какой цех к какой бытовке и т. д.), ученик ходит за наставником, путь через кабинеты «дороже».
## godot --headless --path . --audio-driver Dummy -s res://tests/stage140f3_test.gd

var fails: Array[String] = []


func check(cond: bool, what: String) -> void:
	print(("  ✓ " if cond else "  ✗ ") + what)
	if not cond:
		fails.append(what)


func _run(sim: Sim, minutes: float, each: Callable = Callable()) -> void:
	var t := 0.0
	while t < minutes:
		sim.tick(0.5)
		t += 0.5
		if each.is_valid():
			each.call()


func _initialize() -> void:
	Defs.load_all()
	# 1. директор и кабинет с первого дня во всех сценариях
	for scn: String in ["garage", "field", "sandbox"]:
		var s := Scenario.new_game(scn, "mech", "market", 5)
		var d := Director.of(s)
		check(d != null and d.is_itr() and d.wage == 0, "%s: директор в штате, без оклада" % scn)
		check(Director.desk(s) != null and s.dev.root_ok(), "%s: есть кабинет директора со столом — «Развитие» доступно" % scn)
		var ds := Director.desk(s)
		var dsi := s.rooms.space_of_thing(ds)
		check(ds != null and s.world.reachable(Vector2i(s.gate_x, s.world.sidewalk_row), ds.spots()[0]["cell"]) and dsi >= 0 and s.rooms.space_rooms(dsi).size() == 1,
			"%s: кабинет — отдельное помещение, к столу можно пройти" % scn)
		var n := 0
		for w in s.workers:
			if w.is_director():
				n += 1
		check(n == 1, "%s: директор один" % scn)
	# 2. день в гараже: директор приходит, сидит за столом, не увольняется
	var g := Scenario.new_game("garage", "mech", "market", 5)
	var dir := Director.of(g)
	var at_desk := {"n": 0, "dev": false}
	var desk := Director.desk(g)
	g.dev.done.clear()
	_run(g, 6.0 * 60.0, func() -> void:
		if dir.present and dir.task and dir.task.kind == "office" and dir.anim == "desk":
			at_desk["n"] = int(at_desk["n"]) + 1)
	check(dir.present, "директор пришёл на смену")
	check(int(at_desk["n"]) > 60, "директор работает за своим столом (%d шагов)" % int(at_desk["n"]))
	g.progress.all_open = true
	var step := g.dev.next_ready()
	if step != "":
		g.money += 1000000.0
		check(g.dev.start(step) == "", "директор взялся за ступень развития «%s»" % step)
		_run(g, 30.0)
		check(dir.task != null and dir.task.label.contains(Develop.sname(Develop.step_def(step))), "за столом он «ведёт развитие»: %s" % (dir.task.label if dir.task else "—"))
	g.fire(dir)
	check(Director.of(g) == dir, "директора нельзя уволить")
	var mw0 := g.wages_to_market()
	check(dir.wage == 0, "ставки до рынка: директора не трогают (%d подтянуто)" % mw0)
	# 3. сохранение: директор сохраняется; старое сохранение без директора — директор появляется
	var dd := g.to_dict()
	var g2 := Sim.from_dict(JSON.parse_string(JSON.stringify(dd)))
	check(Director.of(g2) != null and g2.workers.size() == g.workers.size(), "директор пережил сохранение")
	var old: Dictionary = JSON.parse_string(JSON.stringify(dd))
	var ws: Array = old["workers"]
	for i in range(ws.size() - 1, -1, -1):
		if str((ws[i] as Dictionary).get("prof", "")) == "director":
			ws.remove_at(i)
	old.erase("areas")
	var g3 := Sim.from_dict(old)
	check(Director.of(g3) != null, "старое сохранение без директора: директор появился")
	# 4. свои зоны: рабочему — не в кабинет, конторскому — не в цех
	var turner: Worker = g.workers[0]
	var dc := desk.cell
	check(not g.areas.own_area_ok(turner, dc) and g.areas.own_area_ok(dir, dc), "кабинет директора: рабочему без дела нельзя, директору можно")
	var shop := g.rooms.room_at(Vector2i(20, 12))
	check(shop != null and shop.type == "workshop" and not g.areas.own_area_ok(dir, Vector2i(20, 12)) and g.areas.own_area_ok(turner, Vector2i(20, 12)), "цех: директору без дела нельзя, рабочему можно")
	check(is_equal_approx(g.world.astar.get_point_weight_scale(dc + Vector2i(0, 1)), World.OFFICE_W), "клетка кабинета «дороже» для пути (×%.1f)" % World.OFFICE_W)
	# 5. обед из дома — у части людей, без кубика
	var lb := 0
	for i2 in 1000:
		var tw := Worker.new()
		tw.id = i2 + 1
		tw.prof = "turner"
		if Areas.brings_lunch(tw):
			lb += 1
	check(lb > 150 and lb < 300, "обед из дома носит примерно каждый пятый рабочий (%d из 1000)" % lb)
	# 6. логистика: цеху назначена бытовка; столовая для ИТР — рабочие туда не ходят
	var s5 := Scenario.new_game("garage", "mech", "market", 9)
	var shop5 := s5.rooms.room_at(Vector2i(20, 12))
	var lock5 := s5.rooms.room_at(Vector2i(12, 17))
	var cant5 := s5.rooms.room_at(Vector2i(12, 12))
	s5.areas.set_link(shop5, "locker", lock5)
	var t5: Worker = s5.workers[0]
	t5.pos = Vector2(20.5, 12.5)
	check(s5.areas.linked(t5, "locker") == lock5 and s5.areas.link_of(shop5, "locker") == lock5, "цеху назначена бытовка — рабочий цеха её видит")
	s5.areas.set_itr_canteen(cant5, true)
	check(not s5.areas.canteen_ok(t5, cant5) and s5.areas.canteen_ok(Director.of(s5), cant5), "столовая для ИТР: рабочему нельзя, директору можно")
	var bad := {"n": 0, "eat": 0}
	_run(s5, 7.0 * 60.0, func() -> void:
		for w in s5.workers:
			if w.present and w.task and w.task.kind == "eat":
				bad["eat"] = int(bad["eat"]) + 1
				if not w.is_itr() and s5.rooms.room_at(w.cell()) == cant5 and w.anim == "sit":
					bad["n"] = int(bad["n"]) + 1)
	check(int(bad["eat"]) > 0 and int(bad["n"]) == 0, "в обед рабочие не садятся в столовой для ИТР (обедов %d, нарушений %d)" % [int(bad["eat"]), int(bad["n"])])
	var d5 := s5.to_dict()
	var s6 := Sim.from_dict(JSON.parse_string(JSON.stringify(d5)))
	var c6 := s6.rooms.room_at(Vector2i(12, 12))
	check(s6.areas.is_itr_canteen(c6) and s6.areas.link_of(s6.rooms.room_at(Vector2i(20, 12)), "locker") != null, "назначения быта пережили сохранение")
	# 7. ученик ходит за наставником
	var s7 := Scenario.new_game("garage", "mech", "market", 11)
	var mentor: Worker = s7.workers[0]   # Батя, токарь 6-го разряда
	var app: Worker = s7.workers[2]      # Денис, разнорабочий
	app.mentor = mentor.id
	s7.training._appr_sig = ""
	var near := {"n": 0, "all": 0, "sh": 0}
	_run(s7, 8.0 * 60.0, func() -> void:
		if mentor.present and app.present and mentor.task and Brain.SHADOW_KINDS.has(mentor.task.kind):
			near["all"] = int(near["all"]) + 1
			if app.pos.distance_to(mentor.pos) <= 2.5:
				near["n"] = int(near["n"]) + 1
			if app.task and app.task.kind == "shadow":
				near["sh"] = int(near["sh"]) + 1)
	var share := float(near["n"]) / maxf(1.0, float(near["all"]))
	check(int(near["all"]) > 100 and share > 0.75 and int(near["sh"]) > 0, "ученик почти всё время рядом с работающим наставником (%d%%)" % int(share * 100.0))
	# 8. ИТР без раздевалки: приходят одетыми, шкафчик им не нужен
	var s8 := Scenario.new_game("garage", "mech", "market", 13)
	_run(s8, 3.0 * 60.0)
	var d8 := Director.of(s8)
	check(d8.present and d8.dressed and d8.locker_id < 0, "директор пришёл в своём, шкафчик не занимает")
	# 9. детерминизм: одна партия — одинаково
	var a := Scenario.new_game("garage", "mech", "market", 21)
	var b := Scenario.new_game("garage", "mech", "market", 21)
	_run(a, 600.0)
	_run(b, 600.0)
	check(is_equal_approx(a.money, b.money) and a.rng.state == b.rng.state and Director.of(a).pos == Director.of(b).pos, "одинаковое зерно — одинаковая партия")
	print("РЕЗУЛЬТАТ: %s" % ("OK" if fails.is_empty() else "ОШИБКИ: %d" % fails.size()))
	quit(0 if fails.is_empty() else 1)
