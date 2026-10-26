extends SceneTree
## Тест версии 1.50: карточка человека («Сейчас делает / Чем недоволен / Что сделать») и пять шкал настроения
## (Деньги, Условия, Коллектив, Перспектива, Отдых).
## godot --headless --path . --audio-driver Dummy -s res://tests/stage150_test.gd

const S := preload("res://tests/setups.gd")
const SCALES := ["money", "cond", "team", "future", "rest"]

var fails: Array[String] = []


func check(cond: bool, what: String) -> void:
	print(("  ✓ " if cond else "  ✗ ") + what)
	if not cond:
		fails.append(what)


func _parts_sum(parts: Array) -> float:
	var s := 0.0
	for p: Array in parts:
		s += float(p[1])
	return s


func _init() -> void:
	Defs.load_all()
	L.apply("ru")

	print("— каждая мысль попадает ровно в одну из пяти шкал")
	var bad := 0
	for id in Defs.thoughts.keys():
		if not SCALES.has(Mood.thought_scale(str(id))):
			bad += 1
	check(bad == 0 and Mood.LIFE.size() == 5, "все %d мыслей разложены по пяти шкалам" % Defs.thoughts.size())
	var want := {"wage_cut": "money", "payday": "money", "arrears": "money", "dark": "cond", "cold": "cond", "no_ppe": "cond",
		"ate_hot": "cond", "fight": "team", "corporate": "team", "union_denied": "team", "grade_up": "future", "course_done": "future",
		"stage_up": "future", "vacation": "rest", "no_vacation": "rest", "tea_break": "rest", "no_smoke": "rest"}
	var wrong: Array[String] = []
	for k in want.keys():
		if Mood.thought_scale(str(k)) != str(want[k]):
			wrong.append("%s→%s" % [k, Mood.thought_scale(str(k))])
	check(wrong.is_empty(), "примеры по шкалам верны %s" % str(wrong))
	check(Mood.scale_of("wage_low") == "money" and Mood.scale_of("tired") == "rest" and Mood.scale_of("foe") == "team" and Mood.scale_of("mentor") == "future" and Mood.scale_of("hungry") == "cond", "не-мысли (ставка, усталость, недруг, наставник, голод) — по своим шкалам")

	var g := Scenario.new_game("garage", "mech", "calm", 150)
	g.story.enabled = false
	var w := S.hire(g, "turner", "turning", 5)
	w.present = true
	for k in w.needs.keys():
		w.needs[k] = 80.0
	w.thoughts.clear()
	w.wage = Mood.market_wage(w)
	Mood.refresh(g, w)

	print("— шкалы собираются из тех же слагаемых, что и итоговое настроение")
	Mood.add(g, w, "wage_cut")
	Mood.add(g, w, "dark")
	Mood.add(g, w, "fight")
	Mood.add(g, w, "no_vacation")
	Mood.add(g, w, "exam_failed")
	var lf := Mood.life(g, w)
	var names := {}
	for sc in SCALES:
		names[sc] = (lf[sc]["parts"] as Array).map(func(p: Array) -> String: return str(p[2]))
	check(names["money"].has("t:wage_cut") and names["cond"].has("t:dark") and names["team"].has("t:fight") and names["rest"].has("t:no_vacation") and names["future"].has("t:exam_failed"), "пять причин — в пяти разных шкалах")
	var total := 0.0
	for sc in SCALES:
		total += _parts_sum(lf[sc]["parts"])
	var vet := 3.0 if Mood.veteran(g, w) else 0.0
	check(absf(total - vet - _parts_sum(Mood.breakdown(g, w))) < 0.001, "сумма шкал = сумма слагаемых настроения (баланс не менялся)")
	check(absf(Mood.value(g, w) - clampf(Defs.b("mood_base") + _parts_sum(Mood.breakdown(g, w)), 0.0, 100.0)) < 0.001, "итоговое настроение считается как раньше")
	for sc in SCALES:
		var v := float(lf[sc]["v"])
		check(v >= 0.0 and v <= 100.0, "шкала «%s»: %d" % [sc, int(v)])

	print("— «Чем недоволен» и «Что сделать»")
	# низкая ставка
	var a := S.hire(g, "turner", "turning", 5)
	a.present = true
	for k2 in a.needs.keys():
		a.needs[k2] = 80.0
	a.thoughts.clear()
	a.wage = maxi(1000, int(Mood.market_wage(a) * 0.6))
	var c1 := Mood.complaint(g, a)
	var ad1 := Mood.advice(g, a)
	print("   ставка: ", c1.get("text", ""), " | ", ad1)
	check(not c1.is_empty() and str(c1["scale"]) == "money" and "платят меньше" in str(c1["text"]), "низкая ставка: жалоба в «Деньги»")
	check("Поднять ставку до" in ad1 and Defs.money_str(Mood.wage_target(a)) in ad1, "низкая ставка: совет с числом")
	# драка
	var b := S.hire(g, "turner", "turning", 5)
	b.present = true
	for k3 in b.needs.keys():
		b.needs[k3] = 80.0
	b.thoughts.clear()
	b.wage = Mood.market_wage(b)
	for i in 3:
		Mood.add(g, b, "fight")
		Mood.add(g, b, "argued")
	var c2 := Mood.complaint(g, b)
	var ad2 := Mood.advice(g, b)
	print("   драка: ", c2.get("text", ""), " | ", ad2)
	check(not c2.is_empty() and str(c2["scale"]) == "team" and ad2 != "" and ("Устроить" in ad2 or "Перевести" in ad2 or "Развести" in ad2), "драка: «Коллектив» и совет про праздник/перевод")
	# есть недруг в той же бригаде
	var br := g.crew.add_brigade("Тест")
	var foe := S.hire(g, "turner", "turning", 5)
	foe.present = true
	b.brigade = int(br["id"])
	foe.brigade = int(br["id"])
	g.training._add_rel(b, foe, -100.0)
	if not g.training.foes(b).is_empty():
		check("другую бригаду" in Mood.advice_for(g, b, "team", "t:fight"), "недруг в бригаде: «перевести в другую бригаду»")
	else:
		print("   (недруг не получился — пропуск)")
	# нет отдыха
	var r := S.hire(g, "turner", "turning", 5)
	r.present = true
	r.thoughts.clear()
	r.wage = Mood.market_wage(r)
	r.needs["food"] = 80.0
	r.needs["bladder"] = 80.0
	r.needs["rest"] = 5.0
	var c3 := Mood.complaint(g, r)
	var ad3 := Mood.advice(g, r)
	print("   отдых: ", c3.get("text", ""), " | ", ad3)
	check(not c3.is_empty() and str(c3["scale"]) == "rest" and str(c3["cid"]) == "tired", "вымотан: жалоба в «Отдых»")
	check(("комнат" in ad3) or ("кулер" in ad3) or ("диван" in ad3) or ("смен" in ad3), "вымотан: совет про комнату отдыха, кулер или смену")
	check(Mood.advice_for(g, r, "rest", "tired") != "", "совет про отдых не пустой")
	if not Mood._has_restroom(g):
		check("комнату отдыха" in ad3, "комнаты отдыха нет — советуют построить")
	# отпуск
	Mood.add(g, r, "no_vacation")
	check("отпуск" in Mood.advice_for(g, r, "rest", "t:no_vacation"), "не пустили в отпуск: совет про отпуск")
	# всё хорошо
	var ok := S.hire(g, "turner", "turning", 5)
	ok.thoughts.clear()
	ok.wage = Mood.market_wage(ok)
	for k4 in ok.needs.keys():
		ok.needs[k4] = 80.0
	check(Mood.complaint(g, ok).is_empty() and Mood.advice(g, ok) != "", "всё хорошо: жалоб нет, совет — «ничего»")
	# каждая мысль даёт непустой совет
	var empty_adv := 0
	for id2 in Defs.thoughts.keys():
		if Mood.advice_for(g, ok, Mood.thought_scale(str(id2)), "t:" + str(id2)) == "":
			empty_adv += 1
	check(empty_adv == 0, "на любую причину есть совет")
	check(Mood.doing(g, w) != "", "«Сейчас делает» не пусто: %s" % Mood.doing(g, w))

	print("— старый сейв грузится")
	for fn in ["save_1.21.json", "save_1.22.json", "save_1.23.json"]:
		var txt := FileAccess.get_file_as_string("res://tests/saves/" + fn)
		var d: Variant = JSON.parse_string(txt)
		check(d is Dictionary, fn + ": читается")
		if d is Dictionary:
			var os := Sim.from_dict(d)
			var okn := 0
			for ow in os.workers:
				Mood.refresh(os, ow)
				var lf2 := Mood.life(os, ow)
				var good := lf2.size() == 5 and Mood.advice(os, ow, lf2) != "" and Mood.doing(os, ow) != ""
				if good:
					okn += 1
			check(not os.workers.is_empty() and okn == os.workers.size(), fn + ": у всех %d рабочих шкалы, жалоба и совет считаются" % os.workers.size())
	var rt := Sim.from_dict(JSON.parse_string(JSON.stringify(g.to_dict())))
	check(rt.workers.size() == g.workers.size() and Mood.life(rt, rt.workers[0]).size() == 5, "сохранить → загрузить: шкалы на месте")

	print("— английский")
	L.apply("en")
	check("Raise the rate to" in Mood.advice(g, a) and Mood.complaint(g, a)["name"] == "Money", "советы и шкалы переведены: %s" % Mood.advice(g, a))
	L.apply("ru")

	print("\nИТОГ: ", "ВСЁ ХОРОШО" if fails.is_empty() else "ПРОВАЛЫ: %d" % fails.size())
	for f in fails:
		print("  ✗ ", f)
	quit(0 if fails.is_empty() else 1)
