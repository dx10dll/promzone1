extends Node
## 1.44: пропуск пустого времени, окно настроек в экране, газета без выдуманных людей, редкие звонки, чёткий шрифт.
## xvfb-run -a -s "-screen 0 1920x1080x24" godot --path . --rendering-driver opengl3 res://tests/stage144_test.tscn

var fails: Array[String] = []


func check(cond: bool, what: String) -> void:
	print(("  ✓ " if cond else "  ✗ ") + what)
	if not cond:
		fails.append(what)


func _wait(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _fits(c: Control) -> bool:
	var vr := get_viewport().get_visible_rect()
	var r := c.get_global_rect()
	return r.position.x >= -0.5 and r.position.y >= -0.5 and r.end.x <= vr.size.x + 0.5 and r.end.y <= vr.size.y + 0.5


func _ready() -> void:
	get_tree().create_timer(240.0).timeout.connect(func() -> void:
		print("РЕЗУЛЬТАТ: ОШИБКИ: тест не уложился во время")
		get_tree().quit(2))
	Defs.load_all()

	print("— пропуск до смены: те же шаги, то же состояние")
	var a := Scenario.new_game("garage", "mech", "market", 1441)
	a.minute = 5.0 * 1440.0 + 18.0 * 60.0   # суббота, 18:00
	for w in a.workers:
		w.present = false
	var b := Scenario.new_game("garage", "mech", "market", 1441)
	b.minute = a.minute
	for w in b.workers:
		w.present = false
	check(a.can_skip_idle(), "суббота вечером, никого нет — пропуск доступен")
	var tgt := a.next_shift_start()
	check(a.is_workday(a.day() + 2) and absf(tgt - (float(a.day() + 1) * 1440.0 + Defs.b("shift_start"))) < 0.1, "цель — начало смены в понедельник (день %d)" % (a.day() + 2))
	# A: обычный прогон
	while a.minute < tgt - 0.01:
		a.tick(0.5)
	# B: то же, но кадрами по бюджету, как game_main._skip_frame
	var c0 := b.calls.seq
	var bad0 := b.bad_seq
	var frames := 0
	while b.minute < tgt - 0.01:
		var n := 0
		while b.minute < tgt - 0.01 and n < 300:
			b.skip_stop_reason(c0, bad0)
			b.tick(0.5)
			n += 1
		frames += 1
	check(absf(a.minute - b.minute) < 0.001, "доехали до одной и той же минуты (%.1f)" % a.minute)
	check(is_equal_approx(a.money, b.money), "деньги совпадают (%.2f)" % a.money)
	check(a.rng.state == b.rng.state, "состояние rng совпадает")
	check(frames < 20, "двое суток укладываются в %d кадров по 300 шагов" % frames)

	print("— звонки: только важное")
	var s := Scenario.new_game("garage", "mech", "market", 1442)
	s.minute = 3000.0
	s.inspect._act("fire", [], [], "")
	check(s.calls.queue.is_empty(), "проверка без замечаний — звонка нет")
	s.inspect._act("fire", [{"key": "t1", "fine": 5000.0, "text": "тест", "cell": [-1, -1]}], [], "")
	check(not s.calls.queue.is_empty() and str(s.calls.peek()["caller"]) == "fire", "штраф — звонит инспектор")
	s.calls.queue.clear()
	s.calls.tag_at.clear()
	s.minute = 5000.0
	s.calls.eng_day = -1
	check(s.calls.push("engineer", "worried", "Тест1", [], "x1"), "первый звонок советника за сутки проходит")
	check(not s.calls.push("engineer", "worried", "Тест2", [], "x2"), "второй обычный за те же сутки — нет")
	s.minute += 40.0
	check(s.calls.push("engineer", "surprised", "Пожар", [], "fire", "", "", true), "срочный (пожар) проходит сверх лимита")
	s.calls.queue.clear()
	s.minute += 1440.0 * 3.0
	check(not s.calls.push("engineer", "worried", "Тест1", [], "x1"), "та же тема через 3 суток — нет")
	s.minute += 1440.0 * 3.0
	check(s.calls.push("engineer", "worried", "Тест1", [], "x1"), "та же тема через 6 суток — можно")
	check(not s.calls.has_method("on_delivered") and not s.calls.has_method("on_stage") and not s.calls.has_method("on_overtime"), "болтливые звонки удалены")

	print("— газета не пишет о тех, кого нет")
	var p := Scenario.new_game("garage", "mech", "market", 1443)
	for w in p.workers.duplicate():
		if w.prof == "cook" or w.prof == "foreman" or w.prof == "nurse" or w.prof == "qc":
			p.workers.erase(w)
	check(not p.paper.has_prof("cook"), "поваров нет")
	var bad := 0
	var bad_words := ["Буфетчиц", "буфетчиц", "Мастер спрашивает", "Советы мастера", "Врач напоминает"]
	for i in 40:
		p.minute = float(7 + i * 3) * 1440.0
		p.paper.publish(true)
		for it: Dictionary in (p.paper.issues[0] as Dictionary)["items"]:
			for wd in bad_words:
				if str(it.get("text", "")).contains(wd) or str(it.get("title", "")).contains(wd) or str(it.get("rubric", "")).contains(wd):
					bad += 1
	check(bad == 0, "40 номеров без буфетчицы, мастера и врача (найдено %d)" % bad)

	print("— чёткость: шрифт и привязка к пикселям")
	var f: FontFile = load("res://assets/fonts/IBMPlexSans-Regular.ttf")
	check(not f.multichannel_signed_distance_field, "основной шрифт — не MSDF (на мелком тексте даёт мыло)")
	check(bool(ProjectSettings.get_setting("rendering/2d/snap/snap_2d_transforms_to_pixel", false)), "привязка 2D-преобразований к пикселю включена")

	print("— меню настроек в экране (игра)")
	Game.pending = "new"
	Game.pending_scn = "garage"
	Game.pending_profile = "mech"
	Game.pending_opts = {"tutorial": false}
	Game.pending_seed = 1444
	Game.settings["tutorial_done"] = true
	var gm: GameMain = load("res://scenes/game.tscn").instantiate()
	add_child(gm)
	await _wait(20)
	gm.sim.minute = 5.0 * 1440.0 + 21.0 * 60.0
	for w in gm.sim.workers:
		w.present = false
	await _wait(60)
	check(gm.hud.skip_btn != null and gm.hud.skip_btn.visible, "ночью без людей на панели есть кнопка «%s»" % gm.hud.skip_btn.text)
	check(gm.start_skip() and gm.is_skipping(), "кнопка запускает пропуск")
	await _wait(5)
	gm.stop_skip()
	check(not gm.is_skipping(), "пропуск останавливается")
	for lang in ["ru", "en"]:
		L.apply(lang)
		for sz in [Vector2i(1280, 720), Vector2i(1366, 768), Vector2i(1600, 900)]:
			for sc in [1.0, 1.3]:
				get_window().size = sz
				Game.settings["ui_scale"] = sc
				Game.apply_ui_scale()
				await _wait(6)
				gm.hud.show_settings()
				await _wait(6)
				var panel := gm.hud.modal.get_child(0) as Control
				check(_fits(panel), "%s %dx%d ×%.1f: окно настроек в экране (%s из %s)" % [lang, sz.x, sz.y, sc, panel.get_global_rect().size, get_viewport().get_visible_rect().size])
				gm.hud.close_modal()
	L.apply("ru")
	gm.queue_free()
	await _wait(3)

	print("— меню настроек в экране (главное меню)")
	var mm: Node = load("res://scenes/main_menu.tscn").instantiate()
	add_child(mm)
	await _wait(10)
	for sz in [Vector2i(1280, 720), Vector2i(1600, 900)]:
		for sc in [1.0, 1.3]:
			get_window().size = sz
			Game.settings["ui_scale"] = sc
			Game.apply_ui_scale()
			await _wait(6)
			mm.call("_show_settings")
			await _wait(8)
			var sub := mm.get("sub") as Control
			check(sub != null and _fits(sub), "меню %dx%d ×%.1f: настройки в экране" % [sz.x, sz.y, sc])
	Game.settings["ui_scale"] = 1.0
	Game.apply_ui_scale()

	if fails.is_empty():
		print("РЕЗУЛЬТАТ: ВСЁ ХОРОШО")
		get_tree().quit(0)
	else:
		print("РЕЗУЛЬТАТ: ОШИБКИ: %d" % fails.size())
		get_tree().quit(1)
