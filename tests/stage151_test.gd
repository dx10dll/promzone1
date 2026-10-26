extends SceneTree
## Тест версии 1.51: бригады (план смены, премия, характер бригадира, сплочённость) и путь карьеры.
## godot --headless --path . --audio-driver Dummy -s res://tests/stage151_test.gd

const S := preload("res://tests/setups.gd")

var fails: Array[String] = []


func check(cond: bool, what: String) -> void:
	print(("  ✓ " if cond else "  ✗ ") + what)
	if not cond:
		fails.append(what)


func _has_thought(w: Worker, id: String) -> bool:
	for th: Dictionary in w.thoughts:
		if str(th["id"]) == id and float(th["until"]) > 0.0:
			return true
	return false


func _init() -> void:
	Defs.load_all()
	L.apply("ru")

	var g := Scenario.new_game("garage", "mech", "calm", 151)
	g.story.enabled = false
	var lathe: Thing = g.things_of("machine")[0]
	var w1 := S.hire(g, "turner", "turning", 6)
	var w2 := S.hire(g, "turner", "turning", 4)
	var w3 := S.hire(g, "turner", "turning", 3)
	for w in [w1, w2, w3]:
		w.present = true
	if lathe.product == "":
		lathe.product = str(Defs.products.keys()[0])
	lathe.owner = w1.id
	var cr := g.crew
	var b := cr.add_brigade("Тест")
	var bid := int(b["id"])
	cr.set_member(w1, bid)
	cr.set_member(w2, bid)
	cr.set_lead(bid, w1.id)

	print("— план смены")
	check(cr.plan_for(bid) == 0, "без заказов плана нет")
	var o := g.orders.make_offer(lathe.product)
	o["qty"] = 24
	o["lead"] = 4
	o["status"] = "offer"
	g.orders.list.append(o)
	g.orders.accept(int(o["id"]), false)
	var auto := cr.plan_auto(bid)
	check(auto > 0, "заказ на станке бригады даёт план: %d оп." % auto)
	cr.set_plan_adj(bid, 3)
	check(cr.plan_for(bid) == auto + 3, "правка +3 меняет план: %d" % cr.plan_for(bid))
	cr.set_plan_adj(bid, -1000)
	check(cr.plan_for(bid) == 0, "план не уходит ниже нуля")
	cr.set_plan_adj(bid, 0)
	cr.start_plans()
	var plan := cr.plan_today(bid)
	check(plan == auto and cr.done_today(bid) == 0, "утром план зафиксирован: 0 из %d" % plan)
	cr.on_op(w1)
	cr.on_op(w2)
	check(cr.done_today(bid) == 2 and cr.plan_pct(bid) > 0.0, "сделано 2 из %d" % plan)

	print("— премия")
	cr.set_bonus(bid, 2)
	check(cr.bonus_pct(bid) == 10 and cr.bonus_sum(bid) > 0.0, "премия 10%%: %.0f ₽" % cr.bonus_sum(bid))
	for i in plan:
		cr.on_op(w1)
	var m0 := g.money
	var sum := cr.bonus_sum(bid)
	var mood_w := w2.mood
	cr.settle_plans()
	check(absf((m0 - g.money) - sum) < 0.01, "план выполнен: премия списана с денег (%.0f ₽)" % (m0 - g.money))
	check(_has_thought(w2, "crew_bonus") and Mood.thought_scale("crew_bonus") == "money", "премия попадает в шкалу «Деньги»")
	check(int(b["last_pct"]) >= 100, "итог вчерашнего плана: %d%%" % int(b["last_pct"]))
	cr.start_plans()
	cr.set_bonus(bid, 0)
	for i in plan:
		cr.on_op(w1)
	m0 = g.money
	cr.settle_plans()
	check(absf(m0 - g.money) < 0.01, "без премии в настройке деньги не уходят")
	cr.set_bonus(bid, 1)
	cr.start_plans()
	cr.on_op(w1)
	cr.settle_plans()
	check(_has_thought(w1, "crew_bonus_missed") and float(Defs.thoughts["crew_bonus_missed"]["mood"]) < 0.0, "премия есть, плана нет — обида")

	print("— характер бригадира")
	var t1 := S.hire(g, "turner", "turning", 5)
	t1.traits = ["workaholic"]
	var t2 := S.hire(g, "turner", "turning", 5)
	t2.traits = ["soul"]
	var t3 := S.hire(g, "turner", "turning", 5)
	t3.traits = ["born_mentor"]
	check(cr.char_for(t1) == "rush" and cr.char_for(t2) == "care" and cr.char_for(t3) == "mentor", "характер из черт бригадира")
	cr.set_lead(bid, w1.id)
	var chars := {}
	for c in Crew.CHARS:
		b["char"] = c
		chars[c] = {"speed": cr.speed_k(w2), "inj": cr.injury_k(w2), "grow": cr.growth_k(w2)}
	check(chars["rush"]["speed"] > chars["care"]["speed"], "«гонит план» быстрее, чем «бережёт людей»")
	check(chars["rush"]["inj"] > 1.0 and chars["care"]["inj"] < 1.0, "травм: гонит — больше, бережёт — меньше")
	check(chars["mentor"]["grow"] > 1.0 and chars["rush"]["grow"] == 1.0, "наставник ускоряет рост навыка подчинённых")
	b["char"] = "rush"
	cr.start_plans()
	check(_has_thought(w2, "lead_rush") and float(Defs.thoughts["lead_rush"]["mood"]) < 0.0, "гонит план: настроение вниз")
	b["char"] = "care"
	cr.start_plans()
	check(_has_thought(w2, "lead_care") and float(Defs.thoughts["lead_care"]["mood"]) > 0.0, "бережёт людей: настроение вверх")
	b["char"] = ""
	check(cr.char_of(bid) in Crew.CHARS, "характер без записи подбирается по бригадиру")

	print("— сплочённость")
	b["char"] = "care"
	var c0 := cr.cohesion(bid)
	for i in 10:
		cr.start_plans()
	var c1 := cr.cohesion(bid)
	check(c1 > c0, "пока состав не меняется, сплочённость растёт: %.0f → %.0f" % [c0, c1])
	check(cr.brigade_speed(bid) > -0.03 + 0.0, "сплочённость даёт плюс к скорости")
	for i in 40:
		cr.start_plans()
	check(cr.move_warning(w2, -1) != "", "в сплочённой бригаде перевод требует подтверждения")
	var c2 := cr.cohesion(bid)
	cr.set_member(w3, bid)
	check(cr.cohesion(bid) < c2, "перестановка роняет сплочённость: %.0f → %.0f" % [c2, cr.cohesion(bid)])

	print("— уход опытного")
	var vet := S.hire(g, "turner", "turning", 9)
	vet.grade_n = 4
	cr.set_member(vet, bid)
	var c3 := cr.cohesion(bid)
	cr.on_leave(vet)
	check(cr.cohesion(bid) < c3 - 5.0 and float(b["coh_pen"]) > 0.0, "уход ≥4 разряда: сплочённость падает и висит временный минус")
	var top: Dictionary = g.events[0]
	check(int(top["level"]) == Sim.LVL_WARN and str(top["text"]).contains("опытный"), "уведомление «важное»: " + str(top["text"]))
	var pen := float(b["coh_pen"])
	cr.start_plans()
	check(float(b["coh_pen"]) < pen, "временный минус сходит")

	print("— путь карьеры")
	var lab := S.hire(g, "laborer", "haul", 4)
	check(g.career.step_of(lab) == 0 and g.career.promote_kind(lab) == "apprentice", "разнорабочий — нулевая ступень")
	check(g.career.promote(lab) != "" and lab.prof == "laborer", "без навыка и стажа в ученики не берут")
	lab.skills["turning"] = 3
	lab.days_worked = 6
	check(g.career.promote(lab) == "" and lab.prof == "turner" and g.career.step_of(lab) == 1, "курс + стаж → ученик профессии (токарь, 1-й разряд)")
	lab.skills["turning"] = 4
	check(g.career.exam_block(lab) == "" and g.career.next_needs(lab).size() == 3, "ученик: навык, стаж, экзамен — три условия")
	lab.grade_n = 6
	lab.skills["turning"] = 10
	check(g.career.step_of(lab) == 6 and g.career.promote(lab) != "", "6-й разряд без стажа и бригадирства в мастера не берут")
	lab.days_worked = 60
	lab.tally["mentor"] = 1
	check(g.career.promote(lab) == "" and lab.prof == "foreman" and g.career.step_of(lab) == 7 and lab.is_itr(), "6-й разряд → мастер участка (ИТР)")
	check(lab.brigade < 0, "мастер выходит из бригады")
	check(g.career.promote(lab) != "", "мастеру до начальника цеха не хватает руководства")
	lab.skills["manage"] = 6
	lab.days_worked = 120
	check(g.career.promote(lab) == "" and lab.prof == "chief" and g.career.step_of(lab) == 8, "мастер → начальник цеха")
	check(g.career.next_needs(lab).is_empty() and g.career.promote_kind(lab) == "", "выше некуда")

	print("— старое сохранение")
	var d := cr.to_dict()
	for bb: Dictionary in d["brig"]:
		for k in ["plan_adj", "bonus", "char", "coh", "coh_pen", "done", "plan_now", "last_pct", "bonus_total"]:
			bb.erase(k)
	var g2 := Scenario.new_game("garage", "mech", "calm", 152)
	g2.crew.from_dict(d)
	var b2: Dictionary = g2.crew.brigades[0]
	check(b2.has("plan_adj") and int(b2["bonus"]) == 0 and float(b2["coh"]) > 0.0 and int(b2["plan_now"]) == -1, "поля бригады получили значения по умолчанию")
	check(g2.crew.plan_today(int(b2["id"])) >= 0 and g2.crew.cohesion(int(b2["id"])) >= 0.0, "старая бригада считается без ошибок")

	print("")
	if fails.is_empty():
		print("ВСЁ ХОРОШО: stage151")
	else:
		print("ПРОВАЛЕНО: %d" % fails.size())
		for f in fails:
			print("  - " + f)
	quit(0 if fails.is_empty() else 1)
