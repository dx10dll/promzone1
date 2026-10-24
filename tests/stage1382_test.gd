extends Node
## 1.38.2: главное меню и «Создать рабочего» не тормозят со временем.
## 1) Фон меню не живёт сутками: 25 смен видов (5 «дней» по 5 видов) — заводы фона не уходят дальше первых суток,
##    грузы на полу и все грузы не копятся, сменённые заводы освобождаются целиком (Sim.release).
## 2) Долгий прогон (EditorBench.soak) с ЖИВЫМ фоном (один вид — смены видов проверены в п. 1): редактор открыт, нажатия в темпе человека — узлы, объекты,
##    сироты, ресурсы, память текстур, твины, таймеры, кэш портретов ровные, кадр в конце не тяжелее, чем в начале.
## 3) F3 в меню показывает строку диагностики.
## xvfb-run -a godot --path . --rendering-driver opengl3 tests/stage1382_test.tscn [-- --soak-secs=150]

var fails: Array[String] = []


func check(cond: bool, what: String) -> void:
	print(("  ✓ " if cond else "  ✗ ") + what)
	if not cond:
		fails.append(what)


func _wait(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _ready() -> void:
	get_tree().create_timer(1200.0).timeout.connect(func() -> void:
		print("РЕЗУЛЬТАТ: ОШИБКИ: тест не уложился во время")
		get_tree().quit(2))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var secs := 150
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--soak-secs="):
			secs = int(a.get_slice("=", 1))
	CustomWorkers.path = "user://test1382_custom_workers.json"
	if FileAccess.file_exists(CustomWorkers.path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(CustomWorkers.path))
	var mm: Node = load("res://scenes/main_menu.tscn").instantiate()
	add_child(mm)
	await _wait(5)

	print("— фон меню: 25 смен видов")
	var ws: Array = mm.get("worlds")
	var refs: Array[WeakRef] = []
	var seen := {}
	var max_min := 0.0
	var max_ground := 0
	var max_items := 0
	var it0 := (ws[0] as Sim).items.size()
	for k in 25:
		ws = mm.get("worlds")
		for s: Sim in ws:
			if not seen.has(s.get_instance_id()):
				seen[s.get_instance_id()] = true
				refs.append(weakref(s))
		var hid := ws[1 - int(mm.get("cur"))] as Sim
		MenuScenes.advance_to(hid, float(mm.get("_next_target")), 6000)
		mm.call("next_scene")
		var shown := (mm.get("worlds") as Array)[int(mm.get("cur"))] as Sim
		for f in 600:   # минут 12 на экране, как за один вид
			shown.tick(0.024)
		await _wait(2)
		for s2: Sim in mm.get("worlds"):
			max_min = maxf(max_min, s2.minute)
			max_ground = maxi(max_ground, s2.ground_items.size())
			max_items = maxi(max_items, s2.items.size())
	await _wait(6)
	var alive := 0
	for r in refs:
		if r.get_ref() != null:
			alive += 1
	check(max_min < 1440.0 * 1.0 + 1440.0, "заводы фона не уходят дальше первых суток: последняя минута %.0f (сутки %d)" % [max_min, int(max_min / 1440.0) + 1])
	check(refs.size() >= 6, "заводы фона сменялись свежими из снимка: %d разных" % refs.size())
	check(alive <= 2, "сменённые заводы освобождены целиком: живых %d из %d" % [alive, refs.size()])
	check(max_ground <= 40, "грузы на полу не копятся: не больше %d" % max_ground)
	check(max_items <= it0 * 3 + 60, "грузы на заводе не копятся: %d → не больше %d" % [it0, max_items])
	var snap: PackedByteArray = mm.get("_snap")
	var r1 := MenuScenes.restore(snap)
	var r2 := MenuScenes.restore(snap)
	check(var_to_str(r1.to_dict()) == var_to_str(r2.to_dict()), "свежий завод из снимка каждый раз одинаковый")
	r1.release()
	r2.release()

	print("— F3")
	var ev := InputEventKey.new()
	ev.keycode = KEY_F3
	ev.pressed = true
	Input.parse_input_event(ev)
	await _wait(40)
	var dg: Variant = mm.get("diag")
	check(dg is DiagLine and (dg as DiagLine).label.text.contains("FPS") and (dg as DiagLine).label.text.contains("узлов"),
		"F3 в меню — строка диагностики: %s" % ((dg as DiagLine).label.text if dg is DiagLine else "нет"))
	mm.call("toggle_diag")
	await _wait(2)
	check(mm.get("diag") == null, "второй F3 прячет строку")

	print("— долгий прогон: «Создать рабочего», живой фон, %d с" % secs)
	mm.call("_show_custom")
	await _wait(5)
	var b := EditorBench.new()
	b.hold_scene = true   # фон живой (завод тикает, люди ходят), но вид один — кадр сравниваем на одном виде
	add_child(b)
	await b.soak(mm, secs, "click")
	check(b.clicks >= secs / 2, "нажатий в темпе человека: %d за %d с" % [b.clicks, secs])
	var w := maxi(20, secs / 5)
	var a := b.soak_avg(10, 10 + w)
	var z := b.soak_avg(secs - w, secs + 1)
	var f := func(k: String) -> String: return "%.1f → %.1f" % [float(a[k]), float(z[k])]
	# узлы и ресурсы зависят от вида на фоне (сколько людей и объектов в кадре) — допуск на смену вида
	check(float(z["nodes"]) <= float(a["nodes"]) * 1.15 + 60.0, "узлы ровные: " + f.call("nodes"))
	check(float(z["objects"]) <= float(a["objects"]) * 1.05 + 150.0, "объекты ровные: " + f.call("objects"))
	check(float(z["orphans"]) <= float(a["orphans"]) + 20.0, "сироты не копятся: " + f.call("orphans"))
	# слои портретов — кэш с пределом (PortraitKit.TEX_KEEP, пила 120–160 слоёв по ~1,2 МБ), отсюда допуск
	check(float(z["resources"]) <= float(a["resources"]) * 1.25 + 30.0, "ресурсы в пределе: " + f.call("resources"))
	check(float(z["tex_mb"]) <= float(a["tex_mb"]) * 1.25 + 60.0, "память текстур в пределе: " + f.call("tex_mb"))
	check(int(z["people"]) <= Tex.PEOPLE_KEEP, "растры людей в пределе: %d" % int(z["people"]))
	check(float(z["bg_nodes"]) <= float(a["bg_nodes"]) * 1.15 + 60.0, "узлы фона ровные: " + f.call("bg_nodes"))
	check(float(z["tweens"]) <= float(a["tweens"]) + 4.0 and float(z["timers"]) <= float(a["timers"]) + 2.0, "твины и таймеры не копятся: %s; %s" % [f.call("tweens"), f.call("timers")])
	check(int(PortraitKit.loaded_count()) <= PortraitKit.TEX_KEEP + 8, "кэш портретов в пределе: %d" % PortraitKit.loaded_count())
	check(float(z["ms_avg"]) <= float(a["ms_avg"]) * 1.25 + 3.0, "кадр в конце не тяжелее: " + f.call("ms_avg") + " мс")
	check(float(z["process_ms"]) <= float(a["process_ms"]) * 1.25 + 3.0, "process в конце не тяжелее: " + f.call("process_ms") + " мс")
	var big := 0
	for g: Array in b.soak_grew:
		if not str(g[0]).begins_with("node:EditorBench") and not str(g[0]).ends_with(".path") and int(g[2]) - int(g[1]) > 300:
			big += 1
			print("    выросло: %s %d → %d" % [g[0], g[1], g[2]])
	check(big == 0, "ни одна коллекция в скриптах не выросла на сотни (кроме текущих путей людей): %d" % big)
	if FileAccess.file_exists(CustomWorkers.path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(CustomWorkers.path))
	print("РЕЗУЛЬТАТ: OK" if fails.is_empty() else "РЕЗУЛЬТАТ: ОШИБКИ: " + ", ".join(fails))
	get_tree().quit(0 if fails.is_empty() else 1)
