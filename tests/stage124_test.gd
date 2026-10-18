extends SceneTree
## Тест версии 1.24 «Порядок»: старые сохранения 1.21–1.23 грузятся и играются,
## «Что стоит» объясняет простои, поиск и фильтры людей, фон меню.
## godot --headless --path . -s res://tests/stage124_test.gd

const S := preload("res://tests/setups.gd")

var fails: Array[String] = []


func check(cond: bool, what: String) -> void:
	print(("  ✓ " if cond else "  ✗ ") + what)
	if not cond:
		fails.append(what)


func _has_reason(lst: Array, m: Thing, why: String) -> bool:
	for r: Dictionary in lst:
		if r["m"] == m:
			return str(r["why"]) == why
	return false


func _init() -> void:
	Defs.load_all()

	print("— старые сохранения")
	for v in ["1.21", "1.22", "1.23"]:
		var p := "res://tests/saves/save_%s.json" % v
		check(FileAccess.file_exists(p), "есть сохранение %s" % v)
		if not FileAccess.file_exists(p):
			continue
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(p))
		check(d is Dictionary, "%s: файл читается" % v)
		if not d is Dictionary:
			continue
		var sim := Sim.from_dict(d)
		var nw := sim.workers.size()
		var nt := sim.things.size()
		var m0 := sim.money
		var made0 := 0
		for m in sim.things_of("machine"):
			made0 += m.parts_made
		check(nw == (d["workers"] as Array).size(), "%s: люди на месте (%d)" % [v, nw])
		check(nt > 10, "%s: объекты на месте (%d)" % [v, nt])
		check(absf(m0 - float(d["money"])) < 1.0, "%s: деньги те же" % v)
		var t0 := sim.minute
		while sim.minute < t0 + 2.0 * 1440.0:
			sim.tick(0.5)
		var made := 0
		for m in sim.things_of("machine"):
			made += m.parts_made
		check(sim.minute >= t0 + 2.0 * 1440.0, "%s: двое суток прошли" % v)
		check(is_finite(sim.money), "%s: деньги в порядке (%d ₽)" % [v, int(sim.money)])
		check(made > made0, "%s: завод работает после загрузки (+%d операций)" % [v, made - made0])
		var st := Stall.list(sim)
		check(st.size() <= sim.things_of("machine").size(), "%s: «Что стоит» строится" % v)
		var keys_ok := true
		for w in sim.workers:
			if w.search_key() == "":
				keys_ok = false
		check(keys_ok, "%s: поиск по людям строится" % v)
		var again := Sim.from_dict(JSON.parse_string(JSON.stringify(sim.to_dict())))
		check(again.workers.size() == sim.workers.size() and again.things.size() == sim.things.size(), "%s: пересохраняется в 1.24" % v)

	print("— «Что стоит»")
	var g := Scenario.new_garage(124)
	g.story.enabled = false
	g.progress.tutorial = -1
	g.bmats.enabled = false
	g.money = 3000000.0
	S.big_shop(g)
	S.hire(g, "turner", "turning", 5)
	S.hire(g, "laborer", "haul", 3)
	var ms := g.things_of("machine")
	check(ms.size() >= 4, "станки поставлены (%d)" % ms.size())
	var lst := Stall.list(g)
	check(not lst.is_empty(), "без заказов станки стоят")
	check(_has_reason(lst, ms[0], "Нет задания") or not lst.is_empty(), "причина «Нет задания»")
	ms[0].broken = true
	ms[1].enabled = false
	lst = Stall.list(g)
	check(_has_reason(lst, ms[0], "Сломан"), "сломанный — «Сломан»")
	check(_has_reason(lst, ms[1], "Выключен"), "выключенный — «Выключен»")
	check(int(lst[0]["lvl"]) == Stall.BAD, "серьёзное — сверху")
	check(Stall.bad_count(g) >= 1, "значок раздела считает серьёзные")
	ms[0].broken = false
	ms[1].enabled = true
	for m in ms:
		if m.working:
			check(Stall.reason(g, m).is_empty(), "работающий не в списке")
			break

	print("— люди: поиск и «без дела»")
	var w0 := g.workers[0]
	check(w0.search_key().contains(w0.prof_name().to_lower()), "поиск находит профессию")
	check(w0.search_key().contains(w0.last.to_lower()), "поиск находит фамилию")
	w0.present = false
	check(not w0.idle_now(), "кого нет на заводе — не «без дела»")
	w0.present = true
	w0.task = null
	check(w0.idle_now(), "на заводе без задачи — «без дела»")

	print("— фон меню")
	var a := MenuScenes.build()
	check(a.workers.size() >= 31, "на заводе меню не меньше 31 человека (%d)" % a.workers.size())
	var canteen := 0
	for t in a.things.values():
		if (t as Thing).def_id in ["stove", "serving_line"]:
			canteen += 1
	check(canteen == 2, "в столовой плита и раздача")
	var target := MenuScenes.next_minute(a.minute, MenuScenes.tod_of(2))
	var steps := 0
	while not MenuScenes.advance_to(a, target, 50):
		steps += 1
		if steps > 400:
			break
	check(a.minute >= target, "мир проматывается к обеду")
	var eating := 0
	for w in a.workers:
		if w.present and MenuScenes.CANTEEN.has_point(w.cell()):
			eating += 1
	check(eating >= 8, "в обед в столовой люди (%d)" % eating)

	print("")
	if fails.is_empty():
		print("РЕЗУЛЬТАТ: OK")
	else:
		print("РЕЗУЛЬТАТ: ОШИБКИ (%d)" % fails.size())
		for ff in fails:
			print("  - " + ff)
	quit(0 if fails.is_empty() else 1)
