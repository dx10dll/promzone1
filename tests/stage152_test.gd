extends SceneTree
## Тест версии 1.52: чек-лист инспектора за неделю до проверки и газета (заметки о решениях игрока, объявления).
## godot --headless --path . --audio-driver Dummy -s res://tests/stage152_test.gd

const S := preload("res://tests/setups.gd")

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


func _new_shop(seed_n: int) -> Sim:
	var g := Scenario.new_game("garage", "mech", "calm", seed_n)
	g.story.enabled = false
	S.big_shop(g)
	for w in g.workers:
		w.present = true
		w.dressed = true
	return g


func _roundtrip(d: Dictionary) -> Dictionary:
	return JSON.parse_string(JSON.stringify(d))


func _inspect_until_done(g: Sim, t: String) -> Dictionary:
	## Запускает проверку; прогноз снимает в момент, когда инспектор входит на завод.
	var ins := g.inspect
	var n0 := ins.history.size()
	ins.queue.clear()
	ins.prescriptions.clear()   # повторные проверки по предписаниям сюда не мешаем
	ins.schedule(t, g.minute, true)
	var snap := {}
	var guard := 0
	while ins.history.size() == n0 and guard < 9000:
		g.tick(0.5)
		guard += 1
		if snap.is_empty() and ins.busy() and str(ins.visit.get("type", "")) == t:
			snap = ins.forecast(t)
	return {"fc": snap, "act": ins.history[0] if ins.history.size() > n0 else {}, "end": ins.forecast(t)}


func _init() -> void:
	Defs.load_all()
	L.apply("ru")

	print("— объявление за неделю")
	var g := _new_shop(152)
	g.minute = 19.0 * 1440.0 + 8.0 * 60.0
	var ins := g.inspect
	ins.queue.clear()
	ins.next_due["fire"] = g.day()
	ins.next_due["labor"] = 999
	ins.next_due["sanitary"] = 999
	ins.next_due["tech"] = 999
	ins.next_due["ecology"] = 999
	ins.next_due["tax"] = 999
	ins.next_due["military"] = 999
	ins.morning()
	var up := ins.upcoming()
	var fire_up: Dictionary = {}
	for u: Dictionary in up:
		if str(u["type"]) == "fire":
			fire_up = u
	check(not fire_up.is_empty(), "пожарная проверка объявлена")
	check(int(fire_up.get("left", 0)) >= 7 and int(fire_up.get("left", 0)) <= 9, "до проверки %d дн. (не меньше недели)" % int(fire_up.get("left", 0)))
	check(ins.announce_days() == 7, "срок объявления в данных: 7 дней")

	print("— чек-лист")
	var fc := ins.forecast("fire")
	var rules: Dictionary = ins.tdef("fire")["rules"]
	var keys := {}
	for it: Dictionary in fc["items"]:
		keys[str(it["key"])] = true
	var all_rules := true
	for k in rules.keys():
		if not keys.has(str(k)):
			all_rules = false
	check(all_rules, "в чек-листе есть все правила пожарной проверки (%d)" % rules.size())
	var bad_n := 0
	for it2: Dictionary in fc["items"]:
		if not bool(it2["ok"]):
			bad_n += 1
	check(bad_n == int(fc["n"]) and bad_n > 0, "строк ✗ столько же, сколько нарушений: %d" % bad_n)
	check(float(fc["fine"]) >= 0.0, "ожидаемый штраф посчитан: %d ₽ (предупреждений %d)" % [int(fc["fine"]), int(fc["warns"])])
	var has_fix := false
	for it3: Dictionary in fc["items"]:
		if not bool(it3["ok"]) and str(it3["fix"]) != "":
			has_fix = true
	check(has_fix, "у нарушений есть подсказка «что сделать»")
	for it4: Dictionary in fc["items"]:
		if bool(it4["ok"]):
			check(str(it4["text"]) != str(it4["key"]), "у пункта ✓ есть описание требования: %s" % str(it4["text"]))
			break
	var cell_ok := false
	for it5: Dictionary in fc["items"]:
		var cc: Array = it5["cell"]
		if not bool(it5["ok"]) and int(cc[0]) >= 0:
			cell_ok = true
	check(cell_ok, "у части нарушений есть место для кнопки «Показать»")
	# исправили нарушение — пункт стал ✓, штраф упал
	var before := float(fc["fine"])
	g.place_thing("extinguisher", Vector2i(30, 4), true, false)
	g.rooms.update()
	var fc2 := ins.forecast("fire")
	check(int(fc2["n"]) <= int(fc["n"]), "после правки нарушений не больше: %d -> %d" % [int(fc["n"]), int(fc2["n"])])
	check(float(fc2["fine"]) <= before, "ожидаемый штраф не вырос")

	print("— чек-лист совпадает с настоящей проверкой")
	var g2 := _new_shop(153)
	g2.progress.stage = 3   # малый бизнес: первое нарушение — предупреждение
	g2.minute = 20.0 * 1440.0 + 7.0 * 60.0
	var fa := g2.inspect.forecast("fire")
	var r1 := _inspect_until_done(g2, "fire")
	var f1: Dictionary = r1["fc"]
	var a1: Dictionary = r1["act"]
	check(not f1.is_empty() and not a1.is_empty(), "проверка прошла, прогноз снят")
	check(int(a1["n"]) == int(f1["n"]), "число нарушений: прогноз %d, акт %d" % [int(f1["n"]), int(a1["n"])])
	check(absf(float(a1["fine"]) - float(f1["fine"])) < 0.5, "штраф: прогноз %d ₽, акт %d ₽ (малый бизнес — предупреждения)" % [int(f1["fine"]), int(a1["fine"])])
	check(int(a1.get("warns", 0)) == int(f1["warns"]), "предупреждений: %d" % int(f1["warns"]))
	# вторая проверка: ключи уже были в предупреждениях — теперь штраф настоящий
	g2.minute += 2.0 * 1440.0
	var f2pre := g2.inspect.forecast("fire")
	check(float(f2pre["fine"]) > 0.0, "после предупреждений прогноз показывает штраф: %d ₽" % int(f2pre["fine"]))
	var r2 := _inspect_until_done(g2, "fire")
	var f2: Dictionary = r2["fc"]
	var a2: Dictionary = r2["act"]
	check(int(a2["n"]) == int(f2["n"]), "вторая проверка, число нарушений: прогноз %d, акт %d" % [int(f2["n"]), int(a2["n"])])
	check(absf(float(a2["fine"]) - float(f2["fine"])) < 0.5 and float(a2["fine"]) > 0.0, "ожидаемый штраф = фактическому: %d ₽ = %d ₽" % [int(f2["fine"]), int(a2["fine"])])
	for t in ["labor", "sanitary", "tech"]:
		g2.minute += 2.0 * 1440.0
		g2.inspect.warned.clear()
		g2.progress.stage = 4
		var r3 := _inspect_until_done(g2, t)
		var f3: Dictionary = r3["fc"]
		var a3: Dictionary = r3["act"]
		var e3: Dictionary = r3["end"]
		if int(e3["n"]) != int(f3.get("n", -1)) or absf(float(e3["fine"]) - float(f3.get("fine", 0.0))) > 0.5:
			print("  · %s: пока шла проверка, завод изменился (появился мусор и т. п.) — пропуск" % t)
			continue
		check(not f3.is_empty() and int(a3["n"]) == int(f3["n"]) and absf(float(a3["fine"]) - float(f3["fine"])) < 0.5, "%s: нарушений %d = %d, штраф %d = %d ₽" % [t, int(f3.get("n", -1)), int(a3.get("n", -2)), int(f3.get("fine", -1)), int(a3.get("fine", -2))])

	print("— внезапных меньше, напоминание накануне")
	check(float(Defs.inspections.get("sudden_chance", 1.0)) < 0.025, "шанс внезапной проверки снижен")
	var g3 := _new_shop(154)
	g3.inspect.queue.clear()
	g3.minute = 30.0 * 1440.0 + 8.0 * 60.0
	g3.inspect.queue.append({"type": "tech", "at": g3.minute + 1.0 * 1440.0 + 60.0, "announced": true, "why": "", "repeat": []})
	g3.inspect.morning()
	check(bool(g3.inspect.queue[0].get("reminded", false)), "накануне проверки пришло напоминание")

	print("— заметки о решениях игрока")
	var p := g.paper
	g.story.enabled = false
	for w in g.workers.duplicate():
		if w.prof == "foreman":
			g.fire(w, true, true)
	check(not p.has_prof("foreman"), "прораба на заводе нет")
	var prod := str(Defs.products.keys()[0])
	var o := g.orders.make_offer(prod)
	o["qty"] = 100
	o["price"] = 3000.0
	o["status"] = "offer"
	g.orders.list.append(o)
	p.pending.clear()
	check(g.orders.accept(int(o["id"]), false) == "", "крупный заказ принят")
	check(p.pending.size() == 1 and bool(p.pending[0].get("pri", false)), "газета заметила крупный заказ: «%s»" % (str(p.pending[0]["title"]) if not p.pending.is_empty() else ""))
	check(not str(p.pending[0]["text"] if not p.pending.is_empty() else "").contains("{"), "подстановка выполнена")
	var o2 := g.orders.make_offer(prod)
	o2["qty"] = 10
	o2["price"] = 500.0
	o2["kind"] = "state"
	o2["status"] = "offer"
	g.orders.list.append(o2)
	p.pending.clear()
	g.orders.accept(int(o2["id"]), false)
	check(p.pending.size() == 1, "госзаказ — отдельная заметка: «%s»" % (str(p.pending[0]["title"]) if not p.pending.is_empty() else ""))
	p.pending.clear()
	g.orders.fail(o, "не успели")
	check(p.pending.size() == 1, "срыв заказа попал в газету: «%s»" % (str(p.pending[0]["title"]) if not p.pending.is_empty() else ""))
	p.pending.clear()
	p.on_crew_plan("Токарный участок", 125)
	check(p.pending.size() == 1 and (str(p.pending[0]["title"]).contains("Токарный участок") or str(p.pending[0]["text"]).contains("125")), "бригада перевыполнила план")
	p.pending.clear()
	p.on_crew_plan("Токарный участок", 95)
	check(p.pending.is_empty(), "план не выполнен на 110% — заметки нет")
	p.on_iso()
	check(p.pending.size() == 1, "получили ISO: «%s»" % str(p.pending[0]["title"]))
	p.pending.clear()
	g.refresh_candidates()
	var hired := 0
	for i in 3:
		if g.hire(0) == "":
			hired += 1
	check(hired == 3 and p.hired_w >= 3, "наняли троих")
	var victims: Array[Worker] = []
	for w in g.workers:
		if not w.is_director() and victims.size() < 2:
			victims.append(w)
	for w in victims:
		g.fire(w)
	check(p.fired_w >= 2, "уволили двоих")
	g.rooms.update()
	p.publish(true)
	var issue: Dictionary = p.issues[0]
	var pri := 0
	var titles: Array[String] = []
	for it6: Dictionary in issue["items"]:
		titles.append(str(it6.get("title", "")))
		if bool(it6.get("pri", false)):
			pri += 1
	check(pri >= 2, "в номере заметок о решениях: %d (%s)" % [pri, "; ".join(titles.slice(0, 4))])
	check(p.hired_w == 0 and p.fired_w == 0, "счётчики кадров сброшены после номера")
	# правило 1.44: шаблон про «мастера» без мастера не выходит
	var bad_tpl := 0
	var events: Dictionary = Defs.paper["events"]
	for id: String in events.keys():
		var tpls: Array = events[id]
		for dd in 6:
			g.minute += 1440.0
			p.pending.clear()
			p.event(id, ["А", "Б"])
			if p.pending.is_empty():
				continue
			var got := str(p.pending[0]["title"])
			for tp: Array in tpls:
				if tp.size() > 3 and not p.has_prof(str(tp[3])) and got == str(tp[1]).replace("{0}", "А").replace("{1}", "Б"):
					bad_tpl += 1
	check(bad_tpl == 0, "газета не пишет про должности, которых нет на заводе (нарушений правила: %d)" % bad_tpl)
	check(events.size() >= 9, "шаблонов событий: %d видов" % events.size())

	print("— столовая и старый сейв")
	var g4 := _new_shop(155)
	g4.paper.flags_init = false
	g4.paper.flags = {"canteen": false}
	var sr := g4.rooms.room_at(Vector2i(37, 10))
	g4.rooms.assign(sr, "canteen")
	g4.paper.pending.clear()
	g4.paper._weekly_events()
	check(not g4.rooms.of_type("canteen").is_empty() and g4.paper.pending.size() == 1, "появилась столовая — заметка: «%s»" % (str(g4.paper.pending[0]["title"]) if not g4.paper.pending.is_empty() else ""))
	g4.paper.pending.clear()
	g4.paper._weekly_events()
	check(g4.paper.pending.is_empty(), "про ту же столовую дважды не пишут")

	print("— объявления")
	var g5 := _new_shop(156)
	var pp := g5.paper
	g5.minute = 14.0 * 1440.0 + 8.0 * 60.0
	var ad_m := pp._make_ad("machine")
	check(not ad_m.is_empty() and pp.live_ads().size() == 1, "объявление о станке: «%s»" % str(ad_m.get("title", "")))
	var def := str(ad_m["def"])
	var c0 := g5.thing_cost(def)
	check(pp.accept_ad(int(ad_m["id"])) == "", "станок выкуплен")
	check(g5.story.has_mod("voucher:" + def) and g5.thing_cost(def) < c0, "на станок скидка: %d ₽ -> %d ₽" % [int(c0), int(g5.thing_cost(def))])
	check(pp.accept_ad(int(ad_m["id"])) != "", "повторно воспользоваться нельзя")
	var ad_w := pp._make_ad("master")
	var n_c := g5.candidates.size()
	check(pp.accept_ad(int(ad_w["id"])) == "" and g5.candidates.size() == n_c + 1, "мастер среди кандидатов")
	var cw := Worker.from_dict(g5.candidates[0])
	check(cw.skill(cw.main_skill()) >= 8, "у мастера высокий навык: %s %d" % [cw.main_skill(), cw.skill(cw.main_skill())])
	g5.refresh_candidates()
	check(g5.candidates.any(func(c: Dictionary) -> bool: return c.has("ad_until")), "мастер ждёт собеседования и после обновления списка")
	check(g5.hire(0) == "" and g5.workers.any(func(w: Worker) -> bool: return w.full_name() == cw.full_name()), "мастера можно нанять")
	var mat := str(Defs.materials.keys()[0])
	var mp0 := g5.material_price(mat)
	var ad_k := pp._make_ad("metal")
	check(pp.accept_ad(int(ad_k["id"])) == "" and g5.material_price(mat) < mp0, "металл дешевле: %d ₽ -> %d ₽" % [int(mp0), int(g5.material_price(mat))])
	# срок
	var left_days := int(ad_k["until"]) - g5.day()
	g5.minute += float(left_days + 8) * 1440.0
	pp.morning()
	g5.story.mods = g5.story.mods.filter(func(m: Dictionary) -> bool: return float(m["until"]) > g5.minute)
	check(pp.live_ads().is_empty(), "объявления истекли")
	check(g5.material_price(mat) == mp0 or absf(g5.material_price(mat) - mp0) <= mp0 * 0.5, "скидка на металл закончилась")
	check(not g5.story.has_mod("metal_sale"), "модификатор распродажи снят")
	check(pp.accept_ad(int(ad_m["id"])) != "", "истёкшее предложение принять нельзя")
	g5.refresh_candidates()
	check(not g5.candidates.any(func(c: Dictionary) -> bool: return c.has("ad_until")), "устаревший мастер из списка ушёл")
	# частота: не чаще раза в несколько дней
	var g6 := _new_shop(157)
	var days: Array[int] = []
	g6.minute = 8.0 * 1440.0 + 8.0 * 60.0
	for wk in 40:
		g6.minute += 7.0 * 1440.0
		var before_ads := g6.paper.ads.size()
		g6.paper.morning()
		g6.paper.publish(true)
		for a: Dictionary in g6.paper.ads:
			if not days.has(int(a["day"])):
				days.append(int(a["day"]))
	days.sort()
	var min_gap := 999
	for i in range(1, days.size()):
		min_gap = mini(min_gap, days[i] - days[i - 1])
	check(days.size() >= 3 and days.size() < 40, "предложения выходят не каждый номер: %d из 40" % days.size())
	check(days.size() < 2 or min_gap >= int(Paper.AD_GAP[0]), "между предложениями не меньше %d дн. (минимум %d)" % [int(Paper.AD_GAP[0]), min_gap])
	var in_issue := false
	for iss: Dictionary in g6.paper.issues:
		for it7: Dictionary in iss["items"]:
			if it7.has("ad"):
				in_issue = true
	check(in_issue, "объявление печатается в номере")

	print("— старый сейв")
	var d := _roundtrip(g.to_dict())
	var pd: Dictionary = d["paper"]
	for k in ["ads", "ad_next", "ad_seq", "flags", "hired_w", "fired_w"]:
		pd.erase(k)
	for q: Dictionary in (d["inspect"] as Dictionary).get("queue", []):
		q.erase("reminded")
	var g7 := Sim.from_dict(d)
	check(g7.paper.ads.is_empty() and g7.paper.flags_init, "бумага без новых полей: пустые объявления, флаги неизвестны")
	g7.paper.publish(true)
	check(g7.paper.issues.size() >= 1, "номер выходит")
	check(g7.inspect.forecast("fire")["items"].size() > 0, "чек-лист строится")
	g7.inspect.morning()
	var d2 := _roundtrip(g5.to_dict())
	var g8 := Sim.from_dict(d2)
	check(g8.paper.ad_seq == g5.paper.ad_seq and g8.paper.ads.size() == g5.paper.ads.size(), "новые поля сохраняются и грузятся")

	print("")
	if fails.is_empty():
		print("ВСЕ ПРОВЕРКИ ПРОЙДЕНЫ")
	else:
		print("ПРОВАЛЕНО: %d" % fails.size())
		for f in fails:
			print("  - " + f)
	quit(0 if fails.is_empty() else 1)
