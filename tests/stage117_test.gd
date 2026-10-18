extends SceneTree
## Тест версии 1.17 «Старт»: название и эмблема завода, неделя стройки без заказов с кнопкой
## «Начать раньше», бытовка в чистом поле, режим планировки, готовые помещения.
## godot --headless --path . -s res://tests/stage117_test.gd

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

	print("— название и эмблема")
	var em := {"shape": "shield", "symbol": "gear_hammer", "bg": "#7a1f1f", "fg": "#e2b73a", "rim": "#e2b73a", "text": ""}
	var g := Scenario.new_game("garage", "mech", "calm", 171, {"company": {"name": "  «Красный  станочник» ", "emblem": em}})
	check(Company.name_of(g) == "Красный станочник", "название очищено от кавычек и пробелов: «%s»" % Company.name_of(g))
	check(Company.title(g) == "Мастерская «Красный станочник»", "до ООО — мастерская: %s" % Company.title(g))
	g.progress.ooo = true
	check(Company.title(g).begins_with("ООО «"), "после регистрации — ООО: %s" % Company.title(g))
	var d: Dictionary = JSON.parse_string(JSON.stringify(g.to_dict()))
	var g2 := Sim.from_dict(d)
	check(Company.name_of(g2) == "Красный станочник" and str(Company.emblem_of(g2)["symbol"]) == "gear_hammer", "название и эмблема сохраняются")
	g2.dispose()
	var a := Scenario.new_game("garage", "mech", "calm", 172)
	var b := Scenario.new_game("garage", "mech", "calm", 172)
	check(Company.name_of(a) != "" and Company.name_of(a) == Company.name_of(b), "без выбора — случайное, но одинаковое для одного зерна: %s" % Company.name_of(a))
	check(a.workers[0].full_name() == b.workers[0].full_name(), "случайная эмблема не сбивает генератор игры")
	var svg := Emblem.svg(em)
	var img := Image.new()
	check(img.load_svg_from_string(svg, 0.5) == OK and img.get_width() == 50, "эмблема рисуется: SVG → картинка %d px" % img.get_width())
	var bad := 0
	for sh: Array in Company.SHAPES:
		for sy: Array in Company.SYMBOLS:
			var e2 := {"shape": sh[0], "symbol": sy[0], "bg": "#1f3a5f", "fg": "#e2b73a", "rim": "#f2efe6", "text": "АБ"}
			var im2 := Image.new()
			if im2.load_svg_from_string(Emblem.svg(e2), 0.3) != OK:
				bad += 1
	check(bad == 0, "все %d сочетаний формы и знака рисуются" % (Company.SHAPES.size() * Company.SYMBOLS.size()))
	check(Company.initials("Красный станочник") == "КС", "буквы из названия: КС")
	check(Defs.objects.has("company_board") and Defs.sprites.has("company_board"), "вывеска завода — объект для цеха")

	print("— чистое поле: только бытовка, неделя стройки")
	var f := Scenario.new_game("field", "mech", "calm", 173)
	# 1.29: поддоны у ворот в обязательных зонах — не склад
	check(f.things_of("storage").filter(func(t: Thing) -> bool: return t.def_id != "pallet" and t.def_id != "pallet_raw").is_empty(), "в чистом поле нет склада — только бытовка")
	check(f.progress.quiet() and f.progress.quiet_left() == 7, "неделя стройки: заказов не будет 7 дней")
	check(f.orders.list.is_empty(), "заявок с утра нет")
	f.story.enabled = false
	run(f, 1440.0 * 2)
	check(f.orders.list.is_empty() and f.sales.queue.is_empty(), "за два дня заявок так и нет")
	var log0 := f.sales.log.size()
	f.progress.start_early()
	check(not f.progress.quiet() and (not f.sales.queue.is_empty() or not f.orders.list.is_empty() or f.sales.log.size() > log0), "«Начать раньше» — сбыт сразу получает заявки")
	var s := Scenario.new_game("sandbox", "mech", "calm", 174, {"money": 1000000, "all_open": true})
	check(s.progress.quiet(), "в песочнице тоже неделя стройки")
	s.minute += 1440.0 * 7.0
	s.orders.morning()
	check(not s.progress.quiet() and s.progress.quiet_until == 0, "через неделю сбыт сам начинает работать")
	check(not g.progress.quiet(), "в гараже заказы с первого дня")

	print("— режим планировки")
	var p := Scenario.new_game("field", "mech", "calm", 175)
	p.money += 3000000.0
	var pl := p.plan
	var hall := Rect2i(24, 10, 10, 8)
	for y in range(hall.position.y, hall.end.y):
		for x in range(hall.position.x, hall.end.x):
			var c := Vector2i(x, y)
			if x == hall.position.x or x == hall.end.x - 1 or y == hall.position.y or y == hall.end.y - 1:
				pl.add_wall(c, World.W_BRICK)
			else:
				pl.add_floor(c, 1)
	pl.add_wall(Vector2i(28, 17), World.W_DOOR)
	pl.paint_zone(Rect2i(25, 11, 8, 6), "workshop")
	check(pl.add_obj("lathe", Vector2i(26, 12), 0) == "", "станок на плане")
	check(pl.add_obj("mill", Vector2i(27, 12), 0) != "", "второй объект поверх первого — нельзя")
	var money0 := p.money
	var bp0 := p.bp_cells.size()
	check(bp0 == 0 and is_equal_approx(p.money, money0), "план ничего не стоит и рабочим не виден")
	var est := pl.cost()
	check(est > 0.0, "смета плана: %s" % Defs.money_str(est))
	var d3: Dictionary = JSON.parse_string(JSON.stringify(p.to_dict()))
	var p2 := Sim.from_dict(d3)
	check(p2.plan.walls.size() == pl.walls.size() and p2.plan.objs.size() == 1 and p2.plan.zones.size() == pl.zones.size(), "план сохраняется")
	p2.dispose()
	var res := pl.approve()
	check(int(res["floors"]) > 0 and int(res["walls"]) > 0 and p.bp_cells.size() > 0, "утвердили: чертежи пола %d и стен %d" % [int(res["floors"]), int(res["walls"])])
	check(p.money < money0 - est * 0.5, "деньги списаны по смете")
	check(pl.zones.is_empty() and not pl.ok_zones.is_empty(), "зона ждёт, пока построят стены")
	p.story.enabled = false
	p.progress.quiet_until = 0
	run(p, 1440.0 * 6, func() -> bool: return pl.ok_zones.is_empty())
	var r := p.rooms.room_at(Vector2i(29, 14))
	check(r != null and r.type == "workshop", "стены построили — зона «Цех» разметилась сама")
	var lathe_bp := false
	for t: Thing in p.things.values():
		if t.def_id == "lathe":
			lathe_bp = true
	check(lathe_bp, "станок с плана заказан")
	check(pl.erase(Rect2i(0, 0, 64, 44)) >= 0 and pl.pending_empty(), "план можно стереть")

	print("— готовые помещения")
	var q := Scenario.new_game("field", "mech", "calm", 176)
	q.money += 3000000.0
	check(Templates.inner("workshop") == Vector2i(10, 6), "цех внутри 10×6 — как раз под цель «цех от 60 клеток»")
	var m0 := q.money
	var cst := Templates.cost(q, "workshop")
	check(Templates.place(q, "workshop", Vector2i(24, 10)) == "", "цех заказан одним щелчком")
	check(m0 - q.money > cst * 0.6, "списано по смете ~%s" % Defs.money_str(cst))
	check(Templates.place(q, "storage", Vector2i(26, 11)) != "", "поверх цеха склад не встанет")
	check(Templates.locked(Scenario.new_game("garage", "mech", "calm", 177), "tech") == "", "техпомещение с подстанцией и насосной — доступно сразу (1.18)")
	check(Templates.place(q, "canteen", Vector2i(40, 10), true) == "" and not q.plan.objs.is_empty(), "шаблон можно положить и на план")
	q.story.enabled = false
	q.progress.quiet_until = 0
	run(q, 1440.0 * 12, func() -> bool: return q.rooms.room_at(Vector2i(29, 13)) != null and q.rooms.room_at(Vector2i(29, 13)).type == "workshop")
	var rw := q.rooms.room_at(Vector2i(29, 13))
	print("    чертежей осталось: %d, день %d" % [q.bp_cells.size(), q.day()])
	check(rw != null and rw.type == "workshop", "цех достроили и разметили")
	var lamps := 0
	for t2: Thing in q.things.values():
		if t2.def_id == "lamp_tube" and t2.built:
			lamps += 1
	check(lamps >= 1, "свет из шаблона смонтирован: %d" % lamps)

	print("РЕЗУЛЬТАТ: " + ("OK" if fails.is_empty() else "ОШИБКИ: " + ", ".join(fails)))
	quit(0 if fails.is_empty() else 1)
