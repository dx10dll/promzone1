extends Node
## 1.29: обучение не закрывает окна само — подшаги внутри окна, в конце игрок закрывает крестиком;
## рамка плавно едет за человеком.
## godot --headless --path . --audio-driver Dummy res://tests/tut129_test.tscn

var fails: Array[String] = []
var gm: GameMain
var tut: TutorialPanel


func check(cond: bool, what: String) -> void:
	print(("  ✓ " if cond else "  ✗ ") + what)
	if not cond:
		fails.append(what)


func _wait(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _go(id: String) -> void:
	gm.sim.progress.tutorial = tut._index_of(id)
	await _wait(3)


func _at() -> String:
	return str(tut._step().get("id", "")) if gm.sim.progress.tutorial >= 0 else "off"


func _ready() -> void:
	get_tree().create_timer(240.0).timeout.connect(func() -> void:
		print("РЕЗУЛЬТАТ: ОШИБКИ: тест не уложился во время")
		get_tree().quit(2))
	Game.pending = "new"
	Game.pending_scn = "garage"
	Game.pending_profile = "mech"
	Game.pending_opts = {"tutorial": true}
	Game.pending_seed = 129
	Game.settings["tutorial_done"] = false
	gm = load("res://scenes/game.tscn").instantiate()
	add_child(gm)
	await _wait(5)
	tut = gm.hud.tutorial
	check(tut != null and gm.sim.progress.tutorial == 0, "обучение запущено")
	for st: Dictionary in TutorialPanel.STEPS:
		if st.has("back"):
			check(tut._index_of(str(st["back"])) >= 0, "шаг %s: есть шаг возврата" % st["id"])

	print("— меню человека")
	await _go("worker")
	gm.set_speed(1)
	await _wait(30)
	var w: Worker = null
	for w0: Worker in gm.sim.workers:
		if w0.present and not w0.visitor:
			w = w0
			break
	var r := tut._target_rect()
	check(r.size != Vector2.ZERO, "рамка на человеке")
	check(tut.spot._shown.get_center().distance_to(r.get_center()) < 24.0, "рамка догнала человека плавно")
	gm.tool.select_worker(w.id)   # как щелчок по карте: маленькое меню над человеком
	gm.hud.info.visible = false
	gm.hud.worker_pop.show_for(w)
	await _wait(25)
	check(_at() == "pop", "щёлкнули по человеку — подшаг «Меню человека»")
	check(gm.hud.worker_pop.visible, "меню человека открыто")
	tut._next()
	await _wait(3)
	check(_at() == "pop_ctl" and gm.hud.worker_pop.visible and tut._target_rect().size != Vector2.ZERO, "«Далее» — кнопка управления, меню не закрылось")
	tut._next()
	await _wait(3)
	check(_at() == "pop_card" and tut._target_rect().size != Vector2.ZERO, "кнопка карточки подсвечена")
	tut._next()
	await _wait(25)
	check(_at() == "pop_close" and gm.hud.worker_pop.visible, "ждём, пока игрок закроет меню")
	var x := tut._find_text(gm.hud.worker_pop, "×")
	check(x != null and tut._target_rect().is_equal_approx(x.get_global_rect()), "подсвечен крестик меню")
	gm.hud.worker_pop.close()
	await _wait(25)
	check(_at() == "orders", "закрыли меню — дальше «Заказы»")

	print("— окно заказов")
	gm.hud.open_window("orders")
	await _wait(25)
	check(_at() == "orders_list" and gm.hud.win != null, "открыли «Заказы» — окно не закрылось, подшаг про список")
	await _wait(40)
	check(gm.hud.win != null and _at() == "orders_list", "окно стоит, пока игрок не нажал «Далее»")
	tut._next()
	await _wait(3)
	check(_at() == "orders_rail" and tut._target_rect().size != Vector2.ZERO, "подсвечены разделы окна")
	tut._next()
	await _wait(25)
	check(_at() == "orders_close" and gm.hud.win != null, "последний подшаг — крестик, окно ещё открыто")
	check(tut._target_rect().size != Vector2.ZERO, "крестик окна найден")
	gm.hud.close_window()
	await _wait(25)
	check(_at() == "money", "закрыли окно — следующий шаг")

	print("— закрыли окно раньше времени")
	await _go("goals")
	gm.hud.open_window("goals")
	await _wait(25)
	check(_at() == "goals_stage", "«Цели» открыты — подшаг про этап")
	gm.hud.close_window()
	await _wait(25)
	check(_at() == "goals", "окно закрыли раньше — вернулись к шагу «Откройте Цели»")

	print("— слой сетей")
	await _go("nets")
	gm.hud.set_overlay("nets")
	await _wait(25)
	check(_at() == "nets_look" and gm.hud.forced_overlay == "nets", "слой включён и остаётся")
	tut._next()
	await _wait(25)
	check(_at() == "nets_off" and gm.hud.forced_overlay == "nets", "ждём, пока игрок выключит слой")
	gm.hud.set_overlay("nets")
	await _wait(25)
	check(_at() == "hire", "выключили слой — «Найм»")

	print("— главы")
	check(tut._chapter(tut._index_of("orders_close")) == tut._chapter(tut._index_of("orders")), "подшаги — та же глава")
	check(tut.step_l.text.contains("ШАГ"), "подпись шага: " + tut.step_l.text)

	print("РЕЗУЛЬТАТ: ", "OK" if fails.is_empty() else "ОШИБКИ: " + ", ".join(fails))
	get_tree().quit(0 if fails.is_empty() else 1)
