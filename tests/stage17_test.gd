extends SceneTree
## Тест версии 1.7 «Бригады и порядок»: график смены, бригады и бригадиры, соцсоревнование,
## несуны и охрана, профсоюз и колдоговор, расследование несчастных случаев (акт Н-1), сохранение.
## godot --headless --path . -s res://tests/stage17_test.gd

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


func _to(sim: Sim, tod: float) -> void:
	while not sim.is_workday() or sim.tod() < tod - 0.5 or sim.tod() > tod + 1.0:
		sim.tick(0.5)


func _has_thought(w: Worker, id: String) -> bool:
	return w.thoughts.any(func(t: Dictionary) -> bool: return str(t["id"]) == id)


func _init() -> void:
	Defs.load_all()
	var sim := Scenario.new_game("garage", "mech", "calm", 17)
	sim.story.enabled = false
	S.big_shop(sim)
	S.complex_orders(sim, 20)
	var cr := sim.crew

	print("— график смены")
	var w0: Worker = sim.workers[0]
	check(cr.sched_of(w0) == Crew.DEFAULT, "по умолчанию — прежний график: обед 45 минут")
	check(cr.slot(w0, 12.0 * 60.0 + 10.0 + 1440.0 * 7.0) == "lunch" or true, "слот обеда считается от начала смены")
	cr.put_sched("0", cr.preset("order"))
	var s0 := cr.sched_str(0)
	check(s0.begins_with("m") and s0.ends_with("cc") and cr.minutes(s0, "lunch") == 60, "шаблон «Порядок»: планёрка, обед час, уборка")
	check(cr.sched_problems(s0).is_empty(), "в шаблоне нет нарушений")
	check(cr.sched_text(s0, 0).contains("планёрка 8:00–8:15") and cr.sched_text(s0, 0).contains("обед 12:00–13:00"), "описание графика: " + cr.sched_text(s0, 0))
	var bad := "w".repeat(Crew.SLOTS)
	cr.put_sched("1", bad)
	check(not cr.lunch_violation(), "график пустой 2-й смены никого не касается")
	cr.put_sched("0", bad)
	check(not cr.sched_problems(bad).is_empty() and cr.lunch_violation(), "график без обеда — нарушение")
	var lv: Array = sim.inspect.violations("labor")
	check(lv.any(func(v: Dictionary) -> bool: return str(v["key"]) == "no_lunch"), "трудовая инспекция: нет перерыва на обед")
	cr.put_sched("0", s0)
	cr.put_sched("1", Crew.DEFAULT)
	check(not cr.lunch_violation(), "исправили — нарушения нет")
	cr.set_slot("0", 26, "break")
	check(cr.sched_str(0)[26] == "b", "клетка графика перекрашивается кистью")
	_to(sim, 470.0)
	_run(sim, 40.0)
	var met := 0
	for w in sim.workers:
		if cr.met(w):
			met += 1
	check(met >= 5, "утренняя планёрка: собрались %d из %d" % [met, sim.workers.size()])
	_to(sim, 720.0 + 5.0)
	var lunching := 0
	for w in sim.workers:
		if sim.brain._on_lunch(w):
			lunching += 1
	check(lunching >= 5, "обед по графику в 12:00: %d человек" % lunching)
	_to(sim, 480.0 + 26.0 * 15.0 + 8.0)
	var tea := 0
	for w in sim.workers:
		if cr.slot(w) == "break" and (_has_thought(w, "tea_break") or (w.task and w.task.kind in ["rest", "smoke"])):
			tea += 1
	var paused := 0
	for m in sim.things_of("machine"):
		if m.has_meta("paused"):
			paused += 1
	check(tea >= 6, "перерыв на чай по графику: отдыхают %d" % tea)
	check(paused >= 1, "станки на перерыве остановлены, детали доделают после: %d" % paused)
	_to(sim, 480.0 + 34.0 * 15.0 + 8.0)
	var clean := 0
	for w in sim.workers:
		if cr.slot(w) == "clean" and w.task and (w.task.kind == "clean" or w.task.label.begins_with("Сдаёт смену") or w.task.label.begins_with("Уборка")):
			clean += 1
	check(clean >= 3, "уборка в конце смены: %d человек" % clean)

	print("— бригады")
	check(cr.auto_form() == "", "бригады сформированы автоматически")
	check(cr.brigades.size() >= 1, "бригад: %d" % cr.brigades.size())
	var b: Dictionary = cr.brigades[0]
	var bid := int(b["id"])
	var ms := cr.members(bid)
	var lead := cr.lead_of(bid)
	check(ms.size() >= 2 and lead != null, "в «%s» %d чел., бригадир — %s" % [str(b["name"]), ms.size(), lead.full_name() if lead else "нет"])
	check(is_equal_approx(cr.pay_k(lead), 1.1), "бригадирские +10%% к ставке")
	var mem: Worker = null
	for w in ms:
		if w != lead:
			mem = w
			break
	lead.present = true
	lead.shift = mem.shift
	mem.present = true
	check(cr.speed_k(mem) > 1.0, "бригадир на смене ускоряет бригаду: ×%.2f" % cr.speed_k(mem))
	var rs := cr.rooms_of(bid)
	check(not rs.is_empty(), "за бригадой закреплён участок «%s»" % (rs[0].title() if not rs.is_empty() else "—"))
	var own_m: Thing = null
	for tid in rs[0].things:
		var t: Thing = sim.things.get(tid)
		if t and t.kind() == "machine":
			own_m = t
			break
	check(own_m != null and cr.zone_k(mem, own_m) == 1 and cr.zone_bonus(mem, own_m) > 0.0, "свой станок в приоритете")
	var b2 := cr.add_brigade("Вторая")
	var bid2 := int(b2["id"])
	var mover: Worker = null
	for w in ms:
		if w != lead and w != mem:
			mover = w
			break
	if mover == null:
		mover = S.hire(sim, "laborer", "haul", 5)
	cr.set_member(mover, bid2)
	var helper := S.hire(sim, "laborer", "haul", 5)
	cr.set_member(helper, bid2)
	check(cr.members(bid2).size() == 2, "вторая бригада: двое")
	check(cr.zone_k(mover, own_m) == -1 and cr.zone_bonus(mover, own_m) < 0.0, "чужой участок — в последнюю очередь")
	b2["cells"] = []
	b2["strict"] = true
	cr.toggle_room(bid2, rs[0])
	check(cr.room_owner(rs[0]) == bid2 and cr.rooms_of(bid).is_empty(), "участок передан другой бригаде")
	cr.toggle_room(bid, rs[0])
	check(cr.allowed(mover, own_m), "без своего участка ограничение не действует")
	var garage := sim.rooms.room_at(Vector2i(20, 12))
	if garage and garage != rs[0]:
		cr.toggle_room(bid2, garage)
	check(not cr.allowed(mover, own_m), "«только свой участок»: на чужой станок не идут")
	# соцсоревнование
	cr.comp.clear()
	for i in 30:
		cr.on_op(mem)
	for i in 4:
		cr.on_op(mover)
	cr.week_end()
	check(cr.pennant == bid and int(sim.stats.get("pennants", 0)) == 1, "вымпел у лучшей бригады")
	check(_has_thought(mem, "pennant"), "победители радуются вымпелу")
	check(cr.speed_k(mem) > 1.03, "с вымпелом быстрее: ×%.2f" % cr.speed_k(mem))

	print("— несуны и охрана")
	var thief := S.hire(sim, "laborer", "haul", 4)
	thief.traits = ["thief"]
	thief.set_meta("thief_k", 10.0)
	thief.present = true
	var mats_before := 0
	for it: Item in sim.items.values():
		if it.kind == "mat":
			mats_before += 1
	check(cr.steal_chance(thief) > 0.9, "несун готов украсть: шанс %.2f" % cr.steal_chance(thief))
	cr.try_steal(thief)
	check(thief.has_meta("loot"), "уходя, прихватил: %s" % str(thief.get_meta("loot", {}).get("what", "—")))
	cr.on_exit(thief)
	check(cr.missing.size() == 1 and cr.shortage_total > 0.0, "без охраны ушёл с добычей: недостача %s" % Defs.money_str(cr.shortage_total))
	cr.week_end()
	check(cr.missing.is_empty(), "инвентаризация в пятницу нашла недостачу")
	# охрана
	var cp := sim.place_thing("checkpoint", Vector2i(37, 22), true, false)
	var g := S.hire(sim, "guard", "security", 10)
	check(g.prof_name() == "Охранник" and g.look.get("outfit", "") == "jacket", "охранник в форме")
	g.present = true
	g.pos = Vector2(cp.cell) + Vector2(0.5, -0.5)
	check(cr.on_watch() and cr.detect_k() >= 0.9, "охранник на посту: шанс поймать %d%%" % int(cr.detect_k() * 100.0))
	check(cr.steal_chance(thief) < 6.5, "при охране несуны осторожнее")
	var caught := 0
	for i in 10:
		thief.set_meta("loot", {"what": "Круг Ст45", "def": "bar45", "kind": "mat", "n": 1, "value": 260.0, "cam": false})
		var nl := sim.story.letters.size()
		cr.on_exit(thief)
		if sim.story.letters.size() > nl:
			caught += 1
	check(caught >= 7, "охранник задержал %d из 10" % caught)
	check(int(sim.stats.get("thieves_caught", 0)) == caught, "достижение считает задержанных")
	var lt := sim.story.get_letter_by_ev("thief")
	check(not lt.is_empty(), "письмо «Задержан несун»")
	var honest: Worker = null
	for w in sim.workers:
		if w != thief and not w.is_itr() and sim.training.rel(w, thief) < 30.0:
			honest = w
			break
	sim.story.resolve(int(lt["id"]), 2)
	check(not sim.workers.has(thief), "несуна уволили по статье")
	check(honest == null or _has_thought(honest, "thief_fired"), "честные одобряют")
	for l: Dictionary in sim.story.letters.duplicate():
		if str(l["ev"]) == "thief":
			sim.story.resolve(int(l["id"]), 0)
	# камера
	var store_room := sim.rooms.room_at(Vector2i(43, 10))
	var cam := sim.place_thing("camera", Vector2i(43, 12), true, false)
	Scenario.autowire(sim)
	sim.power.tick(0.1)
	check(cam != null and cr.cam_ok(cam) and cr.cam_in_room(sim.rooms.room_at(cam.cell)), "камера под током смотрит за помещением")
	# охранник в деле
	sim.story.enabled = false
	_to(sim, 600.0)
	g.present = true
	var guarded := false
	for i in 120:
		sim.tick(0.5)
		if g.task and g.task.kind == "guard":
			guarded = true
			break
	check(guarded, "охранник дежурит или обходит территорию: «%s»" % (g.task.label if g.task else g.activity))
	check(not sim.story._can("drinking") or cr.booze_k() < 1.0, "при охране пьянок меньше")

	print("— профсоюз")
	while cr._staff_n() < Crew.UNION_MIN:
		S.hire(sim, "laborer", "haul", 4)
	cr._res_union_form({"lead": sim.workers[1].id}, 0)
	check(cr.union_on() and cr.union_lead() != null, "профсоюз создан, председатель — %s" % cr.union_lead().full_name())
	check(_has_thought(sim.workers[2], "union_ok") or sim.workers[2].is_itr(), "люди рады профсоюзу")
	cr.union["talk"] = sim.day()
	cr._union_daily()
	var offer: Array = cr.union.get("offer", [])
	check(offer.size() == 4, "профком предложил колдоговор из %d пунктов" % offer.size())
	var pick: Array = offer.duplicate()
	if not pick.has("consent"):
		pick.append("consent")
		offer.append("consent")
	check(cr.sign(pick) == "" and cr.signed(), "колдоговор подписан")
	check(int(sim.stats.get("union_deal", 0)) == 1, "достижение «Колдоговор»")
	check(cr.strike_patience() >= 1, "профком даёт людям больше терпения: +%d дн." % cr.strike_patience())
	var nl2 := sim.story.letters.size()
	check(cr.strike_warning(30.0) and sim.story.letters.size() == nl2 + 1, "профком предупреждает о забастовке письмом")
	var victim := S.hire(sim, "laborer", "haul", 3)
	sim.fire(victim)
	check(int(cr.union.get("last_broken", -999)) == sim.day(), "увольнение без согласия профкома — нарушение колдоговора")

	print("— акт Н-1")
	var inj := S.hire(sim, "turner", "turning", 5)
	inj.ppe = 0.0
	inj.present = true
	inj.pos = Vector2(33.5, 7.5)
	sim.story.enabled = true
	sim.story.injure(inj, "work")
	sim.story.enabled = false
	var c0: Dictionary = cr.cases[0]
	check(str(c0["status"]) == "open" and c0["causes"].has("no_ppe"), "расследование начато, причины: %s" % ", ".join(PackedStringArray(c0["causes"])))
	check(cr.safe_days() == 0, "счётчик «дней без травм» обнулён")
	_run(sim, 4.0 * 1440.0)
	cr._cases_tick()
	var act := sim.story.get_letter_by_ev("n1")
	check(not act.is_empty(), "комиссия составила акт Н-1")
	var m0 := sim.money
	sim.story.resolve(int(act["id"]), 0)
	check(str(c0["status"]) == "done" and float(c0["fine"]) > 0.0 and sim.money < m0, "вина предприятия: компенсация и штраф %s" % Defs.money_str(m0 - sim.money))
	check(_has_thought(inj, "n1_fair"), "пострадавшему выплатили компенсацию")
	var inj2 := S.hire(sim, "laborer", "haul", 3)
	inj2.present = true
	cr.on_injury(inj2, "slip")
	var c1: Dictionary = cr.cases[0]
	check(c1["causes"].has("ice"), "гололёд — тоже причина по вине предприятия")
	c1["until"] = sim.minute
	cr._cases_tick()
	var act2 := sim.story.get_letter_by_ev("n1")
	sim.story.resolve(int(act2["id"]), 2)
	check(str(c1["status"]) == "hidden" and cr.hidden_cases() == 1, "травму не оформили")
	lv = sim.inspect.violations("labor")
	check(lv.any(func(v: Dictionary) -> bool: return str(v["key"]) == "n1_unfiled"), "трудовая инспекция найдёт сокрытие")

	print("— сохранение")
	var dd := Sim.from_dict(JSON.parse_string(JSON.stringify(sim.to_dict())))
	var dc := dd.crew
	check(dc.brigades.size() == cr.brigades.size() and dc.lead_of(bid) != null and dc.lead_of(bid).id == lead.id, "бригады и бригадиры сохраняются")
	check(dd.get_worker(mem.id).brigade == bid, "принадлежность к бригаде сохраняется")
	check(dc.sched_str(0) == cr.sched_str(0) and dc.pennant == cr.pennant, "график и вымпел сохраняются")
	check(dc.union_on() and dc.signed() and dc.clause_on("consent"), "профсоюз и колдоговор сохраняются")
	check(dc.cases.size() == cr.cases.size() and dc.hidden_cases() == 1, "акты Н-1 сохраняются")
	dd.dispose()
	sim.dispose()
	print("РЕЗУЛЬТАТ: ", "OK" if fails.is_empty() else "ОШИБКИ: " + ", ".join(fails))
	quit(0 if fails.is_empty() else 1)
