extends SceneTree
## Тест версии 1.4 «Люди и обучение»: учебный класс и курсы, учебный центр, инструктаж по охране
## труда, наставники, отношения, практиканты из ПТУ, честные повороты объектов, сохранение.
## godot --headless --path . -s res://tests/stage14_test.gd

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


func _to_shift(sim: Sim) -> void:
	while not sim.is_workday() or sim.tod() < 540.0:
		sim.tick(0.5)


func _classroom(sim: Sim) -> void:
	S._box(sim, Rect2i(2, 3, 8, 6), 3, Vector2i(9, 5))
	sim.place_thing("school_desk", Vector2i(3, 4), true, false)
	sim.place_thing("school_desk", Vector2i(6, 4), true, false)
	sim.place_thing("chalkboard", Vector2i(4, 7), true, false)
	sim.rooms.update()
	sim.rooms.assign(sim.rooms.room_at(Vector2i(5, 6)), "classroom")
	sim.rooms.update()


func _init() -> void:
	Defs.load_all()
	print("— повороты объектов")
	check(Thing.rotations("locker") == 4 and Thing.rotations("sink") == 4 and Thing.rotations("fridge") == 4, "шкафчик, раковина, холодильник — 4 положения")
	check(str(Thing.sprite_for("locker", 1)[0]) == "locker_v" and str(Thing.sprite_for("locker", 2)[0]) == "locker_b" and bool(Thing.sprite_for("locker", 3)[1]), "у шкафчика боковой вид, вид сзади и отражённый боковой")
	check(Thing.rotations("plant") == 1 and Thing.rotations("urn") == 1, "цветок и урну вращать незачем")
	var miss: Array[String] = []
	for k in Defs.objects.keys():
		var d: Dictionary = Defs.objects[k]
		if d.has("spots") and str(d.get("kind", "")) != "chair" and Thing.rotations(str(k)) == 4 and not Defs.sprites.has(str(k) + "_v"):
			miss.append(str(k))
	check(miss.is_empty(), "у всех объектов с местом работы на 4 положения есть боковой вид %s" % str(miss))
	var t := Thing.new()
	t.def_id = "mill"
	t.rot = 3
	var sp: Dictionary = t.spots()[0]
	check(Vector2i(sp["cell"]) == Vector2i(1, 0) and str(sp["face"]) == "left", "поворот 3 — зеркало поворота 1: фрезеровщик справа у верхней клетки")

	print("— учебный класс и курсы")
	var sim := Scenario.new_game("garage", "mech", "calm", 21)
	sim.story.enabled = false
	sim.sales.enabled = false
	sim.money = 500000.0
	_classroom(sim)
	check(sim.training.classrooms().size() == 1 and sim.training.class_seats() == 4, "класс оборудован, мест за партами: %d" % sim.training.class_seats())
	var w := sim.workers[0]
	var sk := w.main_skill()
	var lvl := w.skill(sk)
	var o := sim.training.offer(w, sk)
	check(int(o["to"]) == mini(10, lvl + 2), "курс повышения: %d → %d" % [lvl, int(o["to"])])
	var m0 := sim.money
	check(sim.training.start_course(w, sk, "class") == "" and sim.money < m0, "записан на курсы в классе, оплачено %s" % Defs.money_str(m0 - sim.money))
	_to_shift(sim)
	var studied := false
	for i in 1200:
		sim.tick(0.5)
		if w.task and w.task.kind == "study":
			studied = true
		if sim.training.course_of(w).is_empty():
			break
	check(studied, "сидел за партой")
	var guard := 0
	while not sim.training.course_of(w).is_empty() and guard < 20000:
		sim.tick(0.5)
		guard += 1
	check(w.skill(sk) == mini(10, lvl + 2), "окончил курсы: %d → %d" % [lvl, w.skill(sk)])
	check(int(sim.stats.get("courses", 0)) == 1, "курсы засчитаны в статистику")

	print("— смежная профессия в учебном центре")
	var w2 := sim.workers[1]
	w2.skills["milling"] = 1
	check(sim.training.start_course(w2, "milling", "center") == "" and w2.away_why == "на курсах", "уехал в учебный центр")
	var d0 := sim.day()
	while sim.day() < d0 + 5:
		sim.tick(1.0)
	check(w2.skill("milling") >= 3 and sim.training.course_of(w2).is_empty(), "освоил фрезерное дело: %d" % w2.skill("milling"))
	var mill := Thing.new()
	mill.def_id = "mill"
	check(sim.prod.can_operate(w2, mill), "теперь допущен к фрезерному станку")

	print("— инструктаж по охране труда")
	check(sim.training.injury_k() == 1.0, "без инструктажа травм не меньше")
	_to_shift(sim)
	check(sim.training.start_tb() == "", "инструктаж начат")
	_run(sim, 200.0)
	check(sim.training.tb_valid() and sim.training.injury_k() < 1.0, "проведён, травм меньше: ×%.1f" % sim.training.injury_k())
	var big := Scenario.new_game("garage", "mech", "calm", 4)
	big.story.enabled = false
	for i in 4:
		S.hire(big, "laborer", "haul", 4)
	var viol: Array = big.inspect.violations("labor")
	check(viol.any(func(v: Dictionary) -> bool: return str(v["key"]) == "no_tb"), "трудовая инспекция: нет инструктажа при 6+ рабочих — нарушение")
	big.training.tb_day = big.day()
	viol = big.inspect.violations("labor")
	check(not viol.any(func(v: Dictionary) -> bool: return str(v["key"]) == "no_tb"), "после инструктажа нарушения нет")
	big.dispose()

	print("— наставники")
	var a := S.hire(sim, "turner", "turning", 2)
	var mentor := S.hire(sim, "turner", "turning", 8)
	a.shift = mentor.shift
	check(sim.training.mentor_candidates(a).has(mentor), "опытный токарь подходит в наставники")
	check(sim.training.set_mentor(a, mentor) == "" and a.mentor == mentor.id, "наставник назначен")
	a.present = true
	mentor.present = true
	check(is_equal_approx(sim.training.growth_k(a, "turning"), 3.0), "ученик растёт втрое быстрее")
	check(sim.training.speed_k(mentor) < 1.0, "наставник чуть медленнее")
	var parts := Mood.breakdown(sim, a).map(func(p: Array) -> String: return str(p[0]))
	check(parts.any(func(x: String) -> bool: return x.begins_with("Есть у кого поучиться")), "ученику приятно: есть у кого учиться")
	a.skills["turning"] = 7
	sim.training._mentor_morning()
	check(a.mentor < 0 and int(sim.stats.get("mentored", 0)) == 1, "ученик дорос — наставничество окончено")

	print("— отношения")
	var x := sim.workers[0]
	var y := sim.workers[1]
	sim.training._add_rel(x, y, 45.0)
	check(sim.training.friends(x).has(y) and sim.training.friends(y).has(x), "подружились (взаимно)")
	x.present = true
	y.present = true
	y.shift = x.shift
	var px := Mood.breakdown(sim, x).map(func(p: Array) -> String: return str(p[0]))
	check(px.any(func(s2: String) -> bool: return s2.begins_with("Работает вместе с другом")), "с другом в смене работается веселее")
	sim.training._add_rel(x, y, -120.0)
	check(sim.training.foes(x).has(y), "поссорились")
	sim.training.resolve_feud({"a": x.id, "b": y.id}, 0)
	check(y.pending_shift >= 0 or y.shift != x.shift, "развели по сменам")
	var sim_t := sim.training
	var before := sim_t.rel(x, y)
	for i in 30:
		sim_t._tick_rel()
	check(true, "часовой пересчёт отношений не падает (было %d, стало %d)" % [int(before), int(sim_t.rel(x, y))])

	print("— ПТУ")
	var n0 := sim.workers.size()
	check(sim.training.ptu_sign() != "", "без ступени «Связь с ПТУ» договор не заключить")
	sim.office.all_depts = true   # с 1.11 договор с ПТУ — ступень развития отдела кадров
	check(sim.training.ptu_sign() == "" and sim.workers.size() == n0 + 1, "договор с ПТУ — пришёл первый практикант")
	sim.office.all_depts = false
	var st := sim.training.practicants()[0]
	check(st.traits.has("student") and st.wage == Training.PTU_WAGE and st.age >= 18, "практикант: стипендия %s, %d лет" % [Defs.money_str(st.wage), st.age])
	var tr_save := st.traits.duplicate()
	var mt_save := st.mentor
	st.traits = ["student"]
	st.mentor = -1
	check(is_equal_approx(sim.training.growth_k(st, st.main_skill()), 2.0), "учится вдвое быстрее")
	st.traits = tr_save
	st.mentor = mt_save
	st.practice_until = sim.day()
	sim.training._ptu_morning()
	var l := sim.story.get_letter_by_ev("practice_end")
	check(not l.is_empty(), "письмо об окончании практики")
	sim.story.resolve(int(l["id"]), 0)
	check(not st.traits.has("student") and st.practice_until < 0 and st.wage > Training.PTU_WAGE, "взят в штат со ставкой %s" % Defs.money_str(st.wage))

	print("— сохранение")
	var c2 := S.hire(sim, "qc", "qc", 4)
	sim.training.start_course(c2, "qc", "class")
	var d := Sim.from_dict(JSON.parse_string(JSON.stringify(sim.to_dict())))
	var x2 := d.get_worker(x.id)
	check(d.training.courses.size() == sim.training.courses.size() and d.training.ptu and d.training.tb_day == sim.training.tb_day, "курсы, ПТУ и инструктаж сохраняются")
	check(x2 != null and is_equal_approx(d.training.rel(x2, d.get_worker(y.id)), sim.training.rel(x, y)), "отношения сохраняются")
	d.dispose()
	sim.dispose()
	print("РЕЗУЛЬТАТ: ", "OK" if fails.is_empty() else "ОШИБКИ: " + ", ".join(fails))
	quit(0 if fails.is_empty() else 1)
