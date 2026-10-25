extends SceneTree
## Тест версии 0.7: сценарии (гараж, чистое поле, песочница), строители, телосложения,
## прозвища без отчеств, каталог помещений и назначение типа щелчком.
## godot --headless --path . -s res://tests/stage7_test.gd

var fails: Array[String] = []


func check(cond: bool, what: String) -> void:
	print(("  ✓ " if cond else "  ✗ ") + what)
	if not cond:
		fails.append(what)


func run(sim: Sim, minutes: float) -> void:
	var t := 0.0
	while t < minutes:
		sim.tick(0.5)
		t += 0.5


func _init() -> void:
	print("— сценарии")
	var f := Scenario.new_game("field", "mech", "market", 31)
	check(Defs.scenarios.keys() == ["garage", "field", "sandbox"], "остались только гараж, чистое поле, песочница: %s" % str(Defs.scenarios.keys()))
	var all_builders := f.workers.all(func(w: Worker) -> bool: return w.prof == "builder" or w.is_director())   # 1.40: и директор
	check(all_builders and f.workers.size() == 4, "чистое поле: три строителя, станочников нет")
	# строители строят: стена и пол
	f.money += 500000.0
	for x in range(20, 28):
		for y in range(10, 16):
			var c := Vector2i(x, y)
			var edge := x == 20 or x == 27 or y == 10 or y == 15
			if edge:
				f.place_wall_bp(c, World.W_BRICK)
			else:
				f.place_floor_bp(c, 1)
	var bp0 := f.bp_cells.size()
	run(f, 1440.0 * 2)
	check(f.bp_cells.size() < bp0, "строители построили %d из %d клеток за два дня" % [bp0 - f.bp_cells.size(), bp0])
	var s := Scenario.new_game("sandbox", "mech", "calm", 5, {"money": 1000000, "map": "large", "all_open": true})
	var walls := 0
	for i in s.world.w * s.world.h:
		if WallKinds.is_room_wall(s.world.wall[i]):
			walls += 1
	# 1.29: у ворот — обязательные зоны с поддонами (заготовок и готовой продукции), остальное пусто
	var objs := s.things.values().filter(func(t: Thing) -> bool: return t.def_id != "pallet" and t.def_id != "pallet_raw").size()
	walls -= Director.office_counts(s).x   # 1.40: отдельная контора директора
	objs -= Director.office_counts(s).y
	# 1.29: и одно техпомещение 7×5 у ворот (подстанция, насосная, котёл, лампа, огнетушитель)
	check(walls <= 20 and objs <= 5, "песочница пустая: стен %d, объектов %d (кроме поддонов и техпомещения у ворот)" % [walls, objs])

	print("— люди: имена без отчеств, телосложение, прозвища")
	var g := Scenario.new_game("garage", "mech", "market", 7)
	var gromov := g.workers[0]
	check(gromov.formal_name() == "Виктор «Батя» Громов", "имя с прозвищем: " + gromov.formal_name())
	check(not g.workers[1].formal_name().contains("Николаевна"), "без отчества: " + g.workers[1].formal_name())
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var bodies := {}
	for k in 300:
		var w := People.make(rng, "turner")
		bodies[str(w.look.get("body", ""))] = int(bodies.get(str(w.look.get("body", "")), 0)) + 1
		if w.patronymic != "":
			check(false, "у новых людей нет отчества")
			break
	print("    телосложения: ", bodies)
	check(bodies.size() >= 5, "встречаются разные телосложения (1.22: их семь): %d" % bodies.size())
	# прозвища: приходят с найма и зарабатываются поступками
	var big := Scenario.new_game("sandbox", "mech", "calm", 11, {"money": 5000000, "all_open": true})
	for k2 in 24:
		var w2 := People.make(big.rng, ["turner", "laborer", "qc", "welder", "builder"][k2 % 5])
		big.add_worker(w2)
	var with_nick := big.workers.filter(func(w3: Worker) -> bool: return w3.nick != "").size()
	print("    с прозвищем при найме: %d из %d" % [with_nick, big.workers.size()])
	check(with_nick >= 1 and with_nick < big.workers.size(), "часть людей приходит со своим прозвищем")
	# пожарный: потушил пожар
	var hero: Worker = null
	for w4 in big.workers:
		if w4.nick == "":
			hero = w4
			break
	hero.days_worked = 5
	Nicks.count(hero, "fire")
	for o in big.workers:
		if o != hero and o.nick == "":
			o.days_worked = 0  # остальных пока не рассматриваем
	big.stats["nick_day"] = -99
	var got := false
	for d in 20:
		Nicks.daily(big)
		big.stats["nick_day"] = -99
		if hero.nick != "":
			got = true
			break
	check(got and hero.nick in ["Пожарный", "Брандмейстер", "Пожарная"], "за тушение пожара прозвали: «%s»" % hero.nick)
	check(hero.history[0].contains("прозвище") and not hero.history[0].contains("(а)") and not hero.history[0].contains("{"), "в истории: " + str(hero.history[0]))
	var in_paper := big.paper.pending.any(func(p: Dictionary) -> bool: return str(p["title"]).contains(hero.nick))
	check(in_paper, "о прозвище написала многотиражка")
	var d2 := Sim.from_dict(JSON.parse_string(JSON.stringify(big.to_dict())))
	check(d2.get_worker(hero.id).nick == hero.nick and int(d2.get_worker(hero.id).tally.get("fire", 0)) == 1, "прозвище и счётчики сохраняются")
	d2.dispose()

	print("— помещения: требования видны заранее")
	for t in Rooms.TYPES:
		var txt := Rooms.req_text(t)
		if not txt.begins_with("помещение от "):
			check(false, "требования %s: %s" % [t, txt])
	check(Rooms.req_text("canteen").contains("обеденный стол"), "столовая: " + Rooms.req_text("canteen"))

	f.dispose()
	s.dispose()
	g.dispose()
	big.dispose()
	print("РЕЗУЛЬТАТ: ", "OK" if fails.is_empty() else "ОШИБКИ: " + ", ".join(fails))
	quit(0 if fails.is_empty() else 1)
