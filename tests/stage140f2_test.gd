extends SceneTree
## Тест 1.40 (f2): без серёг, каски по должности, «Наладчик ЧПУ», навыки по профессии, ставки,
## этапы до ~100 человек, главный инженер выключен, новые двери, расстановка в песочнице и чистом поле.
## godot --headless --path . --audio-driver Dummy -s res://tests/stage140f2_test.gd

var fails: Array[String] = []


func check(cond: bool, what: String) -> void:
	print(("  ✓ " if cond else "  ✗ ") + what)
	if not cond:
		fails.append(what)


func _initialize() -> void:
	Defs.load_all()
	var rng := RandomNumberGenerator.new()
	rng.seed = 140

	print("— серьги")
	var ear := 0
	for i in 120:
		var w := People.make(rng, "accountant", 1.0)
		if bool(People.face(w.look, w.age)["earrings"]):
			ear += 1
		var rec := PortraitKit.recipe(w.look, {}) if PortraitKit.available() else {}
		if str(rec).contains("earrings"):
			ear += 1
	check(ear == 0, "у 120 женщин ни серёг, ни слоя серёг на портрете")
	var old := {"fem": true, "fs": 7, "face_ovr": {"earrings": true}}
	check(not bool(People.face(old)["earrings"]), "старое сохранение: серьги из редактора не показываются")
	var cached := {"fem": true, "_face": {"earrings": true, "head": "oval"}}
	check(not bool(People.face(cached)["earrings"]), "старое сохранение: серьги в кэше черт сброшены")
	var ce := {"female": true, "id": "x"}
	CustomWorkers.random_look(ce, rng)
	check(not bool((ce["look"]["face_ovr"] as Dictionary).get("earrings", false)), "редактор своих рабочих: серёг нет")

	print("— каски")
	check(Worker.helmet_hex("electrician") == Worker.HELMET_WORKER and Worker.helmet_hex("builder") == Worker.HELMET_WORKER, "рабочие — оранжевая")
	check(Worker.helmet_hex("safety_engineer") == Worker.HELMET_ITR and Worker.helmet_hex("technologist") == Worker.HELMET_ITR, "ИТР — красная")
	check(Worker.helmet_hex("foreman") == Worker.HELMET_BOSS and Worker.helmet_hex("chief") == Worker.HELMET_BOSS and Worker.helmet_hex("director") == Worker.HELMET_BOSS, "мастер, начальник, директор — белая")
	var bad_h := 0
	for pf: String in ["electrician", "builder", "caster", "foreman", "safety_engineer", "laborer"]:
		for i in 20:
			var w2 := People.make(rng, pf)
			if str(w2.look.get("hat", "")) == "helmet" and str(w2.look["hat_col"]) != Worker.helmet_hex(pf):
				bad_h += 1
	check(bad_h == 0, "новые люди в касках своего цвета")
	var ow := People.make(rng, "builder")
	var od := ow.to_dict()
	(od["look"] as Dictionary)["hat"] = "helmet"
	(od["look"] as Dictionary)["hat_col"] = "#d9b13b"
	check(str(Worker.from_dict(od).look["hat_col"]) == Worker.HELMET_WORKER, "старое сохранение: жёлтая каска строителя стала оранжевой")

	print("— наладчик ЧПУ")
	check(str(Worker.PROF_NAMES["setter"]) == "Наладчик ЧПУ", "профессия называется «Наладчик ЧПУ»")
	TranslationServer.set_locale("en")
	check(TranslationServer.translate("Наладчик ЧПУ") == "CNC Setter", "по-английски — CNC Setter")
	check(TranslationServer.translate("Коричневая дверь") == "Brown door" and TranslationServer.translate("Зелёная дверь") == "Green door", "двери переведены")
	TranslationServer.set_locale("ru")

	print("— навыки по профессии")
	var mach := 0
	for pf2: String in People.NON_MACHINE:
		for i in 15:
			var w3 := People.make(rng, pf2)
			for sk: String in People.MACHINE_SKILLS:
				if w3.skill(sk) > 0 and sk != w3.main_skill():
					mach += 1
	check(mach == 0, "у уборщиц, строителей, разнорабочих, охраны, конторских — станочных навыков нет")
	var gen := 0
	for i in 20:
		var l := People.make(rng, "laborer")
		var b := People.make(rng, "builder")
		if l.skill("haul") >= 3 and b.skill("build") >= 3 and b.skill("haul") >= 3:
			gen += 1
	check(gen == 20, "у разнорабочих и строителей — погрузка и стройка")
	var t := People.make(rng, "turner")
	check(t.skill("turning") >= 3, "токарь по-прежнему токарь")
	var sim := Scenario.new_game("garage", "mech", "market", 3)
	var crew_mach := 0
	for w4 in sim.workers:
		if People.NON_MACHINE.has(w4.prof):
			for sk2: String in People.MACHINE_SKILLS:
				if w4.skill(sk2) > 0:
					crew_mach += 1
	check(crew_mach == 0, "стартовая бригада гаража: у нестаночников нет станочных навыков")
	for i in 3:
		sim.refresh_candidates()
	var cand_mach := 0
	for cd: Dictionary in sim.candidates:
		var cw := Worker.from_dict(cd)
		if People.NON_MACHINE.has(cw.prof):
			for sk3: String in People.MACHINE_SKILLS:
				if cw.skill(sk3) > 0:
					cand_mach += 1
	check(cand_mach == 0, "кандидаты на найм — так же")

	print("— ставки")
	var P: GDScript = load("res://tests/econ_probe.gd")
	var payroll := 0
	var n := 0
	for pf3: String in P.PLANT_STAFF.keys():
		for i in int(P.PLANT_STAFF[pf3]):
			payroll += People.make(rng, pf3).wage
			n += 1
	check(n >= 30 and n <= 45, "состав среднего завода: %d человек" % n)
	check(payroll * 5 < 450000, "неделя зарплаты завода на %d человек — %s (было ≈ 670 тыс.)" % [n, Defs.money_str(payroll * 5.0)])
	var tw := 0
	for i in 20:
		tw += People.make(rng, "turner").wage
	check(tw / 20 <= 2200, "средняя ставка токаря %s за смену (1.39: ≈ 3 300)" % Defs.money_str(tw / 20.0))

	print("— путь завода")
	var mx := 0
	var lastp := ""
	var stg: Array = Defs.stages.get("stages", [])
	for sd2: Dictionary in stg:
		lastp = str(sd2.get("people", ""))
		for g: Dictionary in sd2.get("goals", []):
			mx = maxi(mx, int(g.get("n", 0)) if str(g.get("type", "")) == "staff" else 0)
		for g2: Dictionary in (sd2.get("choice", {}) as Dictionary).get("list", []):
			mx = maxi(mx, int(g2.get("staff", 0)))
	check(lastp == "100+", "верхний этап — 100+ человек (%s)" % lastp)
	check(mx > 0 and mx <= 60, "цели по штату не больше 60 (%d)" % mx)

	print("— главный инженер выключен")
	check(not Defs.CHIEF_ENGINEER, "флаг Defs.CHIEF_ENGINEER = false")
	check(not Defs.departments.has("engineer"), "отдела нет")
	check(Develop.step_def("tech2").is_empty() and not Develop.step_def("tech3").is_empty(), "ступень «Главный инженер» убрана, ISO 9001 осталась")
	check(not Rooms.ui_order().has("engineer_office") and Defs.rooms.has("engineer_office"), "кабинета нет в каталоге, но в справочнике есть (старые сохранения)")
	var grp_ok := true
	for grp: Array in CustomWorkers.prof_groups():
		if (grp[1] as Array).has("chief_engineer"):
			grp_ok = false
	check(grp_ok, "в найме и редакторе нет профессии «Главный инженер»")
	var s2 := Scenario.new_game("sandbox", "mech", "market", 3)
	s2.office.all_depts = true
	check(not s2.office.active("engineer"), "даже в песочнице со всеми отделами — не работает")
	var cw2 := People.make(s2.rng, "chief_engineer")
	s2.add_worker(cw2)
	var s3 := Sim.from_dict(JSON.parse_string(JSON.stringify(s2.to_dict())))
	check(s3 != null and s3.workers.size() == s2.workers.size(), "сохранение с главным инженером загружается")
	check(not s3.office.active("engineer"), "после загрузки отдел тоже не работает (ППР сам собой не включается)")
	check(HelpBook.broken_links().is_empty() and not HelpBook.search("главный инженер").has("advisor"), "справка: статьи нет, ссылки целы")

	print("— новые двери")
	for k2: String in ["door_brown", "door_green"]:
		var wd: Dictionary = Defs.walls.get(k2, {})
		check(not wd.is_empty() and bool(wd.get("buildable", false)) and float(wd.get("cost", 0)) > 0.0 and str(wd.get("kind", "")) == "door", "%s: строится, %s за клетку" % [k2, Defs.money_str(float(wd.get("cost", 0)))])
		check(ResourceLoader.exists("res://assets/tiles/%s.svg" % str(wd.get("icon", ""))), "%s: значок в меню" % k2)
	check(int(Defs.walls["door_brown"]["id"]) == World.W_DOOR_BROWN and int(Defs.walls["door_green"]["id"]) == World.W_DOOR_GREEN, "id дверей совпадают с World")
	var c := Vector2i(10, 10)
	s2.world.wall[s2.world.idx(c)] = World.W_DOOR_GREEN
	check(s2.world.is_door(c) and WallKinds.is_door(World.W_DOOR_BROWN) and not Defs.wall_solid(World.W_DOOR_BROWN), "это проход, как обычная дверь")

	print("— песочница и чистое поле")
	var sb := Scenario.new_game("sandbox", "mech", "market", 3)
	var pump: Thing = sb.things_of("pump")[0] if not sb.things_of("pump").is_empty() else null
	var near := false
	if pump:
		for pc: Vector2i in pump.cells():
			for d: Vector2i in Rooms.DIRS:
				if sb.world.is_door(pc + d):
					near = true
	check(pump != null and not near, "песочница: насосная не у самой двери")
	var fd := Scenario.new_game("field", "mech", "market", 3)
	var sink: Thing = null
	for th: Thing in fd.things_of("sink"):
		sink = th
	check(sink != null and sink.rot == 1 and fd.world.get_wall(sink.cell + Vector2i(1, 0)) != World.W_NONE, "чистое поле: раковина спиной к стене")
	var tr := Rect2i(19, 27, 7, 5)
	var touch := 0
	for y in range(tr.position.y - 1, tr.end.y + 1):
		for x in [tr.position.x - 1, tr.end.x]:
			if fd.world.get_wall(Vector2i(x, y)) != World.W_NONE:
				touch += 1
	var trm := fd.rooms.room_at(Vector2i(22, 30))
	check(touch == 0 and trm != null and trm.type == "tech_room", "чистое поле: техпомещение отдельным домиком")
	check(not fd.things_of("pump").is_empty() and fd.water.has_source(), "насосная качает")

	print("РЕЗУЛЬТАТ: " + ("OK" if fails.is_empty() else "ОШИБКИ: " + ", ".join(fails)))
	quit(0 if fails.is_empty() else 1)
