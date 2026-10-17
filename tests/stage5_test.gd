extends SceneTree
## Тест этапа 5: календарь и праздники, пожар и тушение, травма и больничный, проверка
## с инспектором (без замечаний и со штрафом), забастовка, зима (снег, уборка, отопление),
## рассказчик за 20 дней в «Лихих девяностых», многотиражка, сохранение и загрузка, старые сохранения.
## godot --headless --path . -s res://tests/stage5_test.gd

var fails: Array[String] = []


func check(cond: bool, what: String) -> void:
	print(("  ✓ " if cond else "  ✗ ") + what)
	if not cond:
		fails.append(what)


func run(sim: Sim, minutes: float, stop: Callable = Callable()) -> void:
	var t := 0.0
	while t < minutes:
		sim.tick(0.5)
		t += 0.5
		if stop.is_valid() and int(t * 2.0) % 20 == 0 and stop.call():
			return


func run_until_tod(sim: Sim, tod: float) -> void:
	var guard := 0
	while absf(sim.tod() - tod) > 0.6 and guard < 3000:
		sim.tick(0.5)
		guard += 1


func has_thought(sim: Sim, id: String) -> bool:
	for w in sim.workers:
		for th: Dictionary in w.thoughts:
			if str(th["id"]) == id:
				return true
	return false


func _init() -> void:
	var sim := Scenario.new_garage(777, "market")
	sim.sales.enabled = false   # без потока новых заказов — проверки и события
	sim.auto_supply = true
	var log_on := [true]
	sim.notified.connect(func(t: String, _l: int, _c: Vector2i) -> void:
		if log_on[0]:
			print("    [%s %s] %s" % [sim.date_str(), sim.time_str(), t]))
	print("— календарь")
	check(sim.season.month() == 8 and sim.season.dom() == 1, "старт: первая неделя сентября (%s)" % sim.date_str())
	check(sim.season.month(43) == 11 and sim.season.season_id(11) == "winter", "день 43 — декабрь, зима")
	var ny := sim.season.next_day_of(0, 1)
	check(not sim.is_workday(ny) and not sim.is_workday(ny + 2) and sim.is_workday(ny + 3), "новогодние каникулы — выходные (дни %d–%d)" % [ny, ny + 2])
	check(sim.season.sunset() > 1100.0, "в сентябре светло до %d:%02d" % [int(sim.season.sunset() / 60), int(sim.season.sunset()) % 60])

	print("— пожар")
	run(sim, 1440.0 * 2)
	run_until_tod(sim, 600.0)
	var fc := Vector2i(24, 15)
	check(sim.world.passable(fc), "клетка для пожара проходима")
	sim.story.ignite(fc, "Тестовый пожар")
	check(sim.story.fires.size() == 1, "загорелось")
	var max_cells := [0]
	run(sim, 240.0, func() -> bool:
		max_cells[0] = maxi(max_cells[0], sim.story.fires.size())
		return sim.story.fires.is_empty())
	check(sim.story.fires.is_empty(), "пожар потушили (максимум %d клеток)" % max_cells[0])
	check(not sim.story.soot.is_empty(), "остались следы копоти")
	check(has_thought(sim, "fire_scare"), "людям было страшно")

	print("— травма и больничный")
	run_until_tod(sim, 660.0)
	var w: Worker = null
	for x in sim.workers:
		if x.present and x.prof == "laborer":
			w = x
	if w == null:
		w = sim.workers[0]
	sim.story.injure(w, "work")
	check(w.sick_until > sim.minute and w.away_why == "на больничном", "%s на больничном до дня %d" % [w.full_name(), int(w.sick_until / 1440.0) + 1])
	check(w.task != null and w.task.kind == "go_home", "пострадавший ушёл с работы")
	check(sim.story.injuries.size() == 1, "травма учтена")
	run(sim, 1440.0)
	run_until_tod(sim, 600.0)
	check(not w.present, "на следующий день %s дома (%s)" % [w.first, w.activity])

	print("— проверка без замечаний")
	sim.inspect.queue.clear()
	sim.inspect.schedule("fire", sim.minute, false, "тест")
	run(sim, 1440.0, func() -> bool: return not sim.inspect.history.is_empty())
	check(not sim.inspect.history.is_empty(), "инспектор пришёл и ушёл")
	if not sim.inspect.history.is_empty():
		var h: Dictionary = sim.inspect.history[0]
		print("    итог: нарушений %d, штраф %s" % [int(h["n"]), Defs.money_str(float(h["fine"]))])
		check(int(h["n"]) == 0, "пожарный надзор: без замечаний")
	print("— проверка с нарушением")
	for t: Thing in sim.things.values().duplicate():
		if t.def_id == "extinguisher":
			sim.remove_thing(t, 0.0)
	var fines_before := sim.money
	run(sim, 1440.0)
	run_until_tod(sim, 540.0)
	while not sim.is_workday():
		run(sim, 1440.0)
	sim.inspect.queue.clear()
	var hb := sim.inspect.history.size()
	sim.inspect.schedule("fire", sim.minute, false, "тест 2")
	run(sim, 1440.0, func() -> bool: return sim.inspect.history.size() > hb)
	check(sim.inspect.history.size() > hb and int(sim.inspect.history[0]["n"]) > 0, "нарушение найдено: нет огнетушителя")
	check(not sim.inspect.marks.is_empty(), "нарушение отмечено на карте")
	check(not sim.inspect.prescriptions.is_empty(), "выдано предписание")
	var act := sim.story.get_letter_by_ev("inspection_act")
	check(not act.is_empty(), "пришёл акт проверки с выбором")
	if not act.is_empty():
		sim.story.resolve(int(act["id"]), 0)
		check(sim.money < fines_before, "штраф оплачен")

	print("— забастовка")
	run_until_tod(sim, 540.0)
	if not sim.is_workday():
		run(sim, 1440.0 * 2)
		run_until_tod(sim, 540.0)
	sim.story._start_strike(false)
	check(sim.story.strike.get("active", false), "забастовка началась: " + sim.story.demand_text(str(sim.story.strike["demand"])))
	run(sim, 90.0)
	var striking := 0
	var present := 0
	for x2 in sim.workers:
		if x2.present:
			present += 1
			if x2.task and x2.task.kind == "strike":
				striking += 1
	check(striking > 0 and striking >= present - 1, "рабочие у проходной с плакатами (%d из %d)" % [striking, present])
	var sl := sim.story.get_letter_by_ev("strike")
	check(not sl.is_empty(), "письмо с требованиями")
	if not sl.is_empty():
		sim.story.resolve(int(sl["id"]), 0)
	check(not sim.story.strike.get("active", false), "требование выполнено — забастовка окончена")
	check(has_thought(sim, "strike_won"), "рабочие довольны победой")

	print("— зима")
	var ws := Scenario.new_garage(31, "calm")
	ws.season.start_month = 11
	ws.season.temp_day = -16.0
	ws.season.snow_from = 0.0
	ws.season.snow_until = 1440.0 * 1.5
	var sweeps := [0]
	run(ws, 1440.0 * 2.3, func() -> bool:
		for x3 in ws.workers:
			if x3.task and x3.task.kind == "sweep":
				sweeps[0] += 1
		return false)
	check(ws.season.season_id() == "winter", "декабрь — зима (%s)" % ws.date_str())
	var snow_sum := 0
	for v in ws.season.snow:
		snow_sum += v
	check(snow_sum > 1000, "выпал снег (сумма %d, на дорожках %d)" % [snow_sum, int(ws.season.snow_avg)])
	check(sweeps[0] > 0, "рабочие чистили снег лопатой")
	var gr := ws.rooms.room_at(Vector2i(20, 12))
	var t_cold := float(ws.season.room_temp.get(gr.id, 99.0))
	check(t_cold < Defs.sea("cold_below"), "в гараже без батарей холодно: %+d °C" % int(t_cold))
	check(has_thought(ws, "cold") or has_thought(ws, "freezing"), "люди мёрзнут")
	var placed := 0
	for c in [Vector2i(28, 10), Vector2i(28, 11), Vector2i(28, 12), Vector2i(15, 16), Vector2i(15, 17), Vector2i(28, 17), Vector2i(20, 18)]:
		if ws.can_place("radiator", c) == "":
			ws.place_thing("radiator", c, true, true)
			placed += 1
	ws.rooms.update()
	ws.season.update_rooms()
	var t_warm := float(ws.season.room_temp.get(ws.rooms.room_at(Vector2i(20, 12)).id, -99.0))
	check(placed >= 5 and t_warm >= 18.0, "поставили %d батарей — стало %+d °C" % [placed, int(t_warm)])
	var heat_paid := false
	run(ws, 1440.0)
	for e: Dictionary in ws.ledger:
		if str(e["text"]).begins_with("Отопление"):
			heat_paid = true
	check(heat_paid, "счёт за отопление оплачен")
	ws.dispose()

	print("— рассказчик: 20 дней «Лихих девяностых»")
	log_on[0] = false
	var ws2 := Scenario.new_garage(4242, "wild")
	ws2.auto_supply = true
	var kinds := {}
	for d in 20:
		run(ws2, 1440.0)
		if ws2.orders.active_count() < 3:
			for o: Dictionary in ws2.orders.list:
				if str(o["status"]) == "offer":
					ws2.orders.accept(int(o["id"]), true)
					break
	for e2: Dictionary in ws2.story.archive:
		kinds[str(e2["title"])] = int(kinds.get(str(e2["title"]), 0)) + 1
	print("    события: ", kinds)
	check(ws2.story.archive.size() >= 6, "за 20 дней случилось %d событий" % ws2.story.archive.size())
	check(kinds.size() >= 4, "события разные (%d видов)" % kinds.size())
	check(ws2.paper.issues.size() >= 2, "вышло номеров многотиражки: %d" % ws2.paper.issues.size())
	if not ws2.paper.issues.is_empty():
		var iss: Dictionary = ws2.paper.issues[0]
		print("    № %d: %s" % [int(iss["no"]), ", ".join(PackedStringArray((iss["items"] as Array).map(func(x: Dictionary) -> String: return str(x.get("title", x.get("rubric", "")))))) ])
		check((iss["items"] as Array).size() >= 4, "в номере %d материалов" % (iss["items"] as Array).size())
	check(not ws2.story.plan.is_empty(), "месячный план: %d изделий" % int(ws2.story.plan.get("target", 0)))
	print("    деньги %s, заказов %d, репутация %d, травм %d, проверок %d" % [Defs.money_str(ws2.money), int(ws2.stats["orders_done"]), int(ws2.reputation), ws2.story.injuries.size(), ws2.inspect.total])

	print("— сохранение и загрузка")
	var d2 := ws2.to_dict()
	var js := JSON.stringify(d2)
	var back: Dictionary = JSON.parse_string(js)
	var s3 := Sim.from_dict(back)
	check(s3.story.mode == "wild" and s3.story.archive.size() == mini(ws2.story.archive.size(), 50), "рассказчик восстановлен")
	check(s3.paper.issues.size() == ws2.paper.issues.size(), "многотиражка восстановлена")
	check(s3.season.start_month == ws2.season.start_month and s3.season.snow.size() == ws2.season.snow.size(), "погода восстановлена")
	run(s3, 600.0)
	check(true, "после загрузки игра идёт: " + s3.date_str() + " " + s3.time_str())
	print("— старое сохранение (версия 4)")
	var old := ws2.to_dict()
	for k in ["season", "story", "inspect", "paper"]:
		old.erase(k)
	old["version"] = 4
	var s4 := Sim.from_dict(JSON.parse_string(JSON.stringify(old)))
	run(s4, 1440.0)
	check(s4.story.mode == "market" and s4.season.snow.size() == s4.world.w * s4.world.h, "сохранение v4 загружено и играется (%s)" % s4.date_str())
	s3.dispose()
	s4.dispose()
	ws2.dispose()
	sim.dispose()
	print("РЕЗУЛЬТАТ: ", "OK" if fails.is_empty() else "ОШИБКИ: " + ", ".join(fails))
	quit(0 if fails.is_empty() else 1)
