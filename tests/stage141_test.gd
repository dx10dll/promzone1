extends Node
## 1.41: телефонные звонки — очередь, кнопка-телефон, звук и таймеры, эмоции → портреты, звонки инспекторов и заказчиков,
## ограничение частоты, одинаковый результат симуляции на RU и EN.
## xvfb-run -a godot --path . --rendering-driver opengl3 --resolution 1600x900 res://tests/stage141_test.tscn

var fails: Array[String] = []


func check(cond: bool, what: String) -> void:
	print(("  ✓ " if cond else "  ✗ ") + what)
	if not cond:
		fails.append(what)


func _wait(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _viol(fine: float) -> Dictionary:
	return {"key": "t1", "fine": fine, "text": "тест", "cell": [-1, -1]}


func _run(sim: Sim, minutes: float) -> void:
	var t := 0.0
	while t < minutes:
		sim.tick(0.5)
		t += 0.5


func _ready() -> void:
	get_tree().create_timer(300.0).timeout.connect(func() -> void:
		print("РЕЗУЛЬТАТ: ОШИБКИ: тест не уложился во время")
		get_tree().quit(2))
	Defs.load_all()
	print("— эмоции и картинки")
	for who: String in Calls.CHARS.keys():
		var ok := ResourceLoader.exists(Calls.office_path(who))
		for e: String in (Calls.info(who)["emo"] as Array):
			ok = ok and ResourceLoader.exists(Calls.portrait_path(who, e))
		check(ok, "%s: кабинет и все портреты на месте" % who)
	check(Calls.emotion_of("fire", "worried") == "neutral", "неизвестная эмоция инспектора — neutral")
	check(Calls.emotion_of("engineer", "worried") == "worried" and Calls.emotion_of("engineer", "ironic") == "ironic", "у инженера девять эмоций")
	check(Calls.portrait_path("deputy", "angry").ends_with("07_deputy/neutral.png"), "портрет без нужной эмоции — neutral")
	for tp in (Defs.inspections["types"] as Dictionary).keys():
		var mapped := Calls.INSPECTORS.has(str(tp))
		check(mapped or str(tp) == "military", "проверка «%s»: %s" % [tp, "звонит " + str(Calls.INSPECTORS.get(tp, "")) if mapped else "без звонка"])

	print("— звонки после проверок")
	var s := Scenario.new_game("garage", "mech", "market", 1411)
	var map := {"fire": "fire", "sanitary": "sanitary", "ecology": "ecology", "labor": "labor", "tech": "tech", "tax": "tax"}
	for t: String in map.keys():
		s.calls.queue.clear()
		s.calls.tag_at.clear()
		s.inspect._act(t, [_viol(5000.0)], [], "")
		var c := s.calls.peek()
		check(not c.is_empty() and str(c["caller"]) == map[t] and str(c["emotion"]) == "strict", "%s: штраф → звонит %s, строго" % [t, map[t]])
		s.calls.queue.clear()
		s.calls.tag_at.clear()
		s.inspect._act(t, [], [], "")
		check(s.calls.queue.is_empty(), "%s: без замечаний → звонка нет (1.44)" % t)
	s.calls.queue.clear()
	s.calls.tag_at.clear()
	s.inspect._act("military", [_viol(100.0)], [], "")
	check(s.calls.queue.is_empty(), "военная приёмка — без звонка (нет персонажа)")
	s.inspect.schedule("fire", s.minute + 3.0 * 1440.0, true, "")
	check(s.calls.queue.is_empty(), "объявлена проверка → инспектор не звонит (1.44; за сутки предупредит инженер)")
	s.inspect._act("fire", [_viol(5000.0)], [], "")
	var txt := Calls.text_of(s.calls.peek(), s)
	check(txt.contains("штраф") and not txt.contains("%"), "текст звонка собран: «%s»" % txt.left(60))
	s.calls.queue.clear()
	s.calls.tag_at.clear()
	s.story.scheduled_reclamation({"client": "ООО Тест", "product": "bushing", "qty": 5}, 2, 1000.0)
	s.story._ev_reclamation({"client": "ООО Тест", "product": "bushing", "bad": 2, "comp": 1000.0})
	var cr := s.calls.peek()
	check(not cr.is_empty() and str(cr["caller"]) == "procurement" and str(cr["emotion"]) == "strict", "рекламация → заказчик строго")
	s.calls.queue.clear()
	s.calls.on_visit_notice("governor")
	check(str(s.calls.peek().get("caller", "")) == "deputy", "визит губернатора → депутат")

	print("— ограничение частоты")
	var r := Scenario.new_game("garage", "mech", "market", 1412)
	r.minute = 3000.0
	var tags := ["a", "b", "c", "d", "e"]
	var n := 0
	for i in 5:
		r.minute += 200.0
		if r.calls.push("engineer", "neutral", "Тест", [], tags[i]):
			n += 1
		r.calls.queue.clear()
	check(n <= Calls.ENG_PER_DAY, "советник: не больше %d обычных звонков в сутки (было %d)" % [Calls.ENG_PER_DAY, n])
	r.minute += 1500.0
	r.calls.queue.clear()
	check(r.calls.push("engineer", "worried", "Совет", [], "same"), "в новые сутки звонок проходит")
	r.calls.queue.clear()
	r.minute += 1500.0
	check(not r.calls.push("engineer", "worried", "Совет", [], "same"), "тот же совет не повторяется сразу")
	r.minute += 4.0 * 1440.0
	check(r.calls.push("engineer", "worried", "Совет", [], "same"), "…но через несколько суток можно")
	r.calls.queue.clear()
	for i in 6:
		r.calls.tag_at.clear()
		r.calls.push("fire", "neutral", "Тест", [], "q%d" % i, "", "", false, 0.0)
	check(r.calls.queue.size() <= Calls.MAX_QUEUE, "очередь не длиннее %d" % Calls.MAX_QUEUE)
	var old := r.calls.queue.size()
	r.minute += Calls.EXPIRE_MIN + 5.0
	check(old > 0 and not r.calls.has_call() and r.calls.queue.is_empty(), "звонок без ответа тихо гаснет")

	print("— сутки игры: советник звонит, но не чаще лимита")
	var g1 := Scenario.new_game("garage", "mech", "market", 1413)
	var per_day: Dictionary = {}
	var t0 := 0.0
	while t0 < 10.0 * 1440.0:
		g1.tick(0.5)
		t0 += 0.5
		g1.calls.queue.clear()
		per_day[g1.day()] = int(g1.calls.eng_cnt) if g1.calls.eng_day == g1.day() else 0
	var mx := 0
	for v in per_day.values():
		mx = maxi(mx, int(v))
	check(mx <= Calls.ENG_URGENT_DAY, "за 10 дней не больше %d звонков советника в сутки (макс. %d)" % [Calls.ENG_URGENT_DAY, mx])
	check(g1.calls.total >= 0, "за 10 дней звонков: %d" % g1.calls.total)

	print("— RU и EN дают одну и ту же симуляцию")
	var res: Array = []
	for lang in ["ru", "en"]:
		L.apply(lang)
		var sm := Scenario.new_game("garage", "mech", "market", 1414)
		_run(sm, 6.0 * 1440.0)
		res.append([snappedf(sm.money, 0.01), snappedf(sm.reputation, 0.01), sm.workers.size(), sm.calls.total, sm.calls.tag_at.keys().size(), int(sm.stats.get("orders_done", 0))])
	L.apply("ru")
	check(str(res[0]) == str(res[1]), "RU %s = EN %s" % [str(res[0]), str(res[1])])
	var res2: Array = []
	for on in [true, false]:
		Game.settings["calls_on"] = on
		var sm2 := Scenario.new_game("garage", "mech", "market", 1415)
		_run(sm2, 4.0 * 1440.0)
		res2.append([snappedf(sm2.money, 0.01), snappedf(sm2.reputation, 0.01), sm2.workers.size()])
	Game.settings["calls_on"] = true
	check(str(res2[0]) == str(res2[1]), "звонки не влияют на экономику: %s" % str(res2[0]))
	var sv := Scenario.new_game("garage", "mech", "market", 1416)
	sv.calls.push("engineer", "tired", "Тест", [], "z")
	var sv2 := Sim.from_dict(sv.to_dict())
	check(sv2.calls.queue.size() == 1 and sv2.calls.total == 1, "очередь звонков переживает сохранение")

	print("— интерфейс: кнопка, звук, диалог")
	Game.pending = "new"
	Game.pending_scn = "garage"
	Game.pending_profile = "mech"
	Game.pending_opts = {"tutorial": false}
	Game.pending_seed = 1417
	Game.settings["tutorial_done"] = true
	var gm: GameMain = load("res://scenes/game.tscn").instantiate()
	add_child(gm)
	await get_tree().create_timer(1.5).timeout
	var sim := gm.sim
	var ph := gm.hud.phone
	sim.calls.queue.clear()
	check(ph.state == "hidden" and not ph.phone_btn.visible, "телефон скрыт, пока никто не звонит")
	sim.calls.push("engineer", "worried", "%s сломался. Нужны запчасти, и чем скорее, тем лучше. А ППР в «Производство → Станки» не даст такому повториться.", ["Станок"], "t1", "prod:machines", "Открыть станки")
	sim.calls.push("fire", "strict", "Проверка закончена: замечаний нет. Порядок образцовый, так держать.", [], "t2")
	await _wait(4)
	check(ph.state == "ringing" and ph.phone_btn.visible, "звонок: кнопка видна")
	var sz := ph.phone_btn.size
	check(sz.x >= 64.0 and sz.x <= 96.0, "кнопка 64–96 px (%d)" % int(sz.x))
	check(ph.ring_player.playing or float(Game.settings.get("vol_ui", 0.75)) <= 0.001, "звонок звучит")
	var f0 := ph.phone_icon.texture
	var moved := false
	for i in 40:
		await get_tree().process_frame
		if ph.phone_icon.texture != f0:
			moved = true
	check(moved, "телефон трясётся (кадры меняются)")
	await _wait(10)
	check(ph.state == "ringing", "без тиков симуляции (пауза) звонок остаётся")
	ph.answer()
	check(ph.state == "dialogue" and ph.panel.visible and not ph.phone_btn.visible, "ответ: кнопка скрыта, диалог открыт")
	check(not ph.ring_player.playing, "ответ: звонок остановлен")
	var rt := ph.ring_t
	await _wait(20)
	check(not ph.ring_player.playing and is_equal_approx(rt, ph.ring_t), "во время диалога звука и таймера звонка нет")
	check(ph.portrait.texture == ph.tex(Calls.portrait_path("engineer", "worried")), "портрет — worried")
	check(ph.role_l.text.contains("инженер") and ph.text_l.text.contains("Станок сломался"), "роль и текст: «%s» / «%s»" % [ph.role_l.text, ph.text_l.text.left(30)])
	await _wait(25)
	var pr := ph.portrait.get_global_rect()
	var ir := ph._img.get_global_rect()
	var tr := ph.text_l.get_global_rect()
	check(tr.position.y >= ir.end.y - 0.5, "текст ниже картинки, не поверх лица")
	check(pr.end.y - ir.end.y < ir.size.y * 0.08 and pr.size.x >= pr.size.y - 1.0, "портрет внизу по центру, без искажения")
	check(ph.act_btn.visible, "есть кнопка действия")
	ph.close()
	check(ph.state == "hidden" and not ph.panel.visible, "закрыли — скрытое состояние")
	await _wait(4)
	check(ph.state == "ringing" and str(ph.current.get("caller", "")) == "fire", "следующий звонок — отдельно, от инспектора")
	check(ph.ring_player.playing or float(Game.settings.get("vol_ui", 0.75)) <= 0.001, "…и снова со звонком")
	var ev := InputEventKey.new()
	ev.keycode = KEY_ENTER
	ev.pressed = true
	ph._unhandled_key_input(ev)
	check(ph.state == "dialogue" and ph.portrait.texture == ph.tex(Calls.portrait_path("fire", "strict")), "Enter отвечает; инспектор строгий")
	ph.close()
	sim.calls.push("engineer", "ironic", "Тест", [], "t3")
	await _wait(3)
	sim.minute += Calls.EXPIRE_MIN + 10.0
	await _wait(3)
	check(ph.state == "hidden" and sim.calls.queue.is_empty() and not ph.ring_player.playing, "без ответа звонок гаснет, звук стихает")
	Game.settings["calls_on"] = false
	sim.calls.push("engineer", "ironic", "Тест2", [], "t4")
	await _wait(4)
	check(ph.state == "hidden" and sim.calls.queue.is_empty(), "выключили «Звонки советника» — телефон молчит")
	Game.settings["calls_on"] = true
	Game.settings["reduce_motion"] = true
	sim.calls.push("fire", "neutral", "Тест5", [], "t5")
	await _wait(30)
	check(ph.state == "ringing" and ph.phone_icon.texture == ph._frames[0] and ph.phone_cap.visible, "reduced motion: статичный значок с подписью")
	Game.settings["reduce_motion"] = false
	ph.answer()
	ph.close()
	gm.queue_free()
	print("РЕЗУЛЬТАТ: " + ("ВСЁ ХОРОШО" if fails.is_empty() else "ОШИБКИ: %d — %s" % [fails.size(), "; ".join(fails)]))
	get_tree().quit(0 if fails.is_empty() else 1)
