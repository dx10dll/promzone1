extends SceneTree
## Тест версии 1.22 «Мир и люди»: новые телосложения, оператор ЧПУ, голуби, мыши и охота кота,
## сохранение живности.
## godot --headless --path . -s res://tests/stage122_test.gd

var fails: Array[String] = []


func check(cond: bool, what: String) -> void:
	print(("  ✓ " if cond else "  ✗ ") + what)
	if not cond:
		fails.append(what)


func _init() -> void:
	Defs.load_all()

	print("— телосложения")
	for k in ["vthin", "thin", "normal", "stout", "strong", "fat", "vfat"]:
		check(People.BODIES.has(k), "есть телосложение «%s»" % k)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var seen := {}
	for i in 600:
		seen[People.random_body(rng, rng.randi_range(20, 60))] = true
	check(seen.has("vthin") and seen.has("strong") and seen.has("vfat"), "в найме встречаются очень худые, могучие и очень полные: %s" % ", ".join(PackedStringArray(seen.keys())))
	for sk in ["m_vthin", "m_strong", "f_vthin", "f_strong", "m_vfat"]:
		check(ResourceLoader.exists("res://assets/people/torso_side_%s.svg" % sk), "есть силуэт сбоку %s" % sk)

	print("— оператор ЧПУ")
	var g := Scenario.new_game("garage", "mech", "calm", 221)
	g.story.enabled = false
	g.progress.tutorial = -1
	g.bmats.enabled = false
	var op := People.make(rng, "cnc_operator")
	check(op.prof_name() == "Оператор станков с ЧПУ", "профессия: %s" % op.prof_name())
	check(op.skill("cnc") >= 3, "навык «Работа на ЧПУ»: %d" % op.skill("cnc"))
	var cnc_id := ""
	for k2 in Defs.objects.keys():
		if bool(Defs.objects[k2].get("machine", {}).get("cnc", false)) and str(Defs.objects[k2]["machine"].get("process", "")) == "turning" and not bool(Defs.objects[k2].get("legacy", false)):
			cnc_id = str(k2)
			break
	var cell := Vector2i(int(g.world.plot.get_center().x) + 6, int(g.world.plot.get_center().y) + 4)
	var cnc: Thing = g.place_thing(cnc_id, cell, true, false)
	check(cnc != null and cnc.is_cnc(), "поставлен станок с ЧПУ «%s»" % cnc_id)
	check(Production.op_skill(op, cnc) == "cnc", "на ЧПУ оператор работает навыком «ЧПУ»")
	check(g.prod.can_operate(op, cnc), "оператор может работать на станке с ЧПУ")
	var lathe: Thing = null
	for m in g.things_of("machine"):
		if not m.is_cnc() and m.process() == "turning":
			lathe = m
	if lathe:
		op.skills["turning"] = 1
		check(not g.prod.can_operate(op, lathe), "на ручном токарном оператор ЧПУ без навыка не работает")
	var has_op := false
	for k3 in 6:
		g.refresh_candidates()
		for c: Dictionary in g.candidates:
			if str(c.get("prof", "")) == "cnc_operator":
				has_op = true
	check(has_op, "есть станок с ЧПУ — операторы приходят на собеседование")
	g.refresh_candidates("cnc_operator")
	check(not g.candidates.is_empty() and str((g.candidates[0] as Dictionary).get("prof", "")) == "cnc_operator", "объявление «оператор ЧПУ» — приходят операторы")

	print("— голуби, мыши, кот")
	var f := Scenario.new_game("garage", "mech", "calm", 222)
	f.story.enabled = false
	f.progress.tutorial = -1
	f.bmats.enabled = false
	f.minute = floor(f.minute / 1440.0) * 1440.0 + 600.0   # 10:00
	for i2 in 240:
		f.fauna.tick(0.5)
		f.minute += 0.5
	check(not f.fauna.pigeons.is_empty(), "днём во дворе голуби: %d" % f.fauna.pigeons.size())
	# ночь — улетают
	f.minute = floor(f.minute / 1440.0) * 1440.0 + 1380.0
	for i3 in 200:
		f.fauna.tick(0.5)
		f.minute += 0.5
	check(f.fauna.pigeons.is_empty(), "ночью голуби улетают")
	# грязь — мыши
	f.rooms.update()
	var r: Rooms.Room = null
	for rr in f.rooms.list:
		if rr.cells.size() >= 20:
			r = rr
	f.upkeep._ensure()
	for c in r.cells:
		f.upkeep.dirt[f.world.idx(c)] = 220
	for i4 in 400:
		f.fauna.tick(0.5)
		f.minute += 0.5
		if not f.fauna.mice.is_empty():
			break
	check(not f.fauna.mice.is_empty(), "в грязном помещении завелись мыши")
	# кот ловит
	if f.town.cat == null:
		f.town.cat = Cat.new(f)
	var cat := f.town.cat
	cat.pos = Vector2(r.cells[0]) + Vector2(0.5, 0.5)
	cat.state = "sit"
	cat.until = f.minute
	var m0 := cat.mice
	var hunted := false
	for i5 in 6000:
		f.minute += 0.5
		f.fauna.tick(0.5)
		cat.tick(0.5)
		if cat.state == "pounce" or str(cat.next_state) == "hunt":
			hunted = true
		if cat.mice > m0:
			break
		# мыши не должны пропасть из-за уборки в тесте
		for c2 in r.cells:
			f.upkeep.dirt[f.world.idx(c2)] = 220
	check(hunted, "кот охотится")
	check(cat.mice > m0, "кот поймал мышь (всего %d)" % cat.mice)
	# чисто — мыши уходят
	for c3 in r.cells:
		f.upkeep.dirt[f.world.idx(c3)] = 0
	for i6 in 10:
		f.fauna.tick(2.0)
		f.minute += 2.0
	check(f.fauna.mice.is_empty(), "убрали — мыши ушли")
	var fd := Sim.from_dict(f.to_dict())
	check(fd.fauna.caught_mice == f.fauna.caught_mice, "живность сохраняется (поймано мышей: %d)" % fd.fauna.caught_mice)

	print("")
	if fails.is_empty():
		print("РЕЗУЛЬТАТ: OK")
	else:
		print("РЕЗУЛЬТАТ: ОШИБКИ (%d)" % fails.size())
		for ff in fails:
			print("  - " + ff)
	quit(0 if fails.is_empty() else 1)
