extends Node
## 1.40 (f5): оверлей «Логистика» — протянуть линию цех → столовая, убрать щелчком и ПКМ, столовая «только ИТР», выход.
## xvfb-run -a godot --path . --rendering-driver opengl3 --resolution 1600x900 res://tests/stage140f5_test.tscn

var fails: Array[String] = []


func check(cond: bool, what: String) -> void:
	print(("  ✓ " if cond else "  ✗ ") + what)
	if not cond:
		fails.append(what)


func _wait(n: int) -> void:
	for i in n:
		await get_tree().process_frame


## Достраивает на «Чистом поле» два цеха, душевую, вторую столовую, комнату отдыха и контору (без оборудования —
## для логистики важны только тип и положение). Используется и снимками.
static func build_plant(sim: Sim) -> void:
	var defs := [[Rect2i(4, 12, 10, 8), Vector2i(9, 19), "workshop"], [Rect2i(16, 12, 10, 8), Vector2i(20, 19), "workshop"],
		[Rect2i(28, 12, 5, 6), Vector2i(30, 17), "shower"], [Rect2i(35, 12, 6, 6), Vector2i(37, 17), "canteen"],
		[Rect2i(28, 19, 6, 5), Vector2i(30, 23), "restroom"], [Rect2i(43, 12, 6, 6), Vector2i(45, 17), "office"]]
	for d: Array in defs:
		var r: Rect2i = d[0]
		Scenario.box(sim, r, 3, [d[1]])
	sim.world.refresh_all()
	sim.rooms.update()
	for d2: Array in defs:
		var r2: Rect2i = d2[0]
		Scenario.assign_at(sim, r2.position + Vector2i(2, 2), str(d2[2]))
	sim.rooms.update()


func _first(sim: Sim, type: String, skip: int = 0) -> Rooms.Room:
	var k := 0
	for r in sim.rooms.list:
		if r.type == type:
			if k == skip:
				return r
			k += 1
	return null


func _ready() -> void:
	get_tree().create_timer(200.0).timeout.connect(func() -> void:
		print("РЕЗУЛЬТАТ: ОШИБКИ: тест не уложился во время")
		get_tree().quit(2))
	get_tree().root.size = Vector2i(1600, 900)
	Game.pending = "new"
	Game.pending_scn = "field"
	Game.pending_profile = "mech"
	Game.pending_opts = {"tutorial": false}
	Game.pending_seed = 1405
	Game.settings["tutorial_done"] = true
	var gm: GameMain = load("res://scenes/game.tscn").instantiate()
	add_child(gm)
	await get_tree().create_timer(2.0).timeout
	var hud := gm.hud
	var sim := gm.sim
	var tool := gm.tool
	build_plant(sim)
	var ar := sim.areas
	print("— комнаты")
	var types: Array[String] = []
	for r in sim.rooms.list:
		types.append(r.type)
	print(types)
	var shop := _first(sim, "workshop")
	var cant := _first(sim, "canteen")
	var wc := _first(sim, "wc")
	check(shop != null and cant != null and wc != null, "в сценарии есть цех, столовая и туалет")
	if shop == null or cant == null or wc == null:
		get_tree().quit(1)
		return
	var T := float(World.T)

	print("— вход в оверлей")
	hud.toggle_sub("build")
	hud.toggle_logistics()
	await _wait(3)
	check(tool.mode == "logistics" and not tool.plan_mode, "режим «логистика» включён, меню стройки закрыто")
	check(gm.overlay.mode == "logistics", "слой «логистика» нарисован")
	check(hud.ov_btns.has("logistics") and (hud.ov_btns["logistics"] as Button).button_pressed, "кнопка в панели слоёв горит")

	print("— протянуть линию цех → столовая")
	check(ar.link_of(shop, "canteen") == null, "до этого связи нет")
	tool.logi_press_at(shop.center * T)
	check(tool.logi_src != null and tool.logi_src.id == shop.id, "нажали на цех — он источник")
	tool.logi_release_at(cant.center * T)
	check(ar.link_of(shop, "canteen") != null and ar.link_of(shop, "canteen").id == cant.id, "после отпускания над столовой связь назначена, вид по типу цели")
	check(ar.link_list().size() >= 1, "связь есть в списке для рисования")
	await _wait(2)

	print("— неподходящая цель")
	var n0 := ar.link_list().size()
	tool.logi_press_at(shop.center * T)
	tool.logi_release_at(shop.center * T + Vector2(0, 1))   # отпустили над тем же цехом
	check(ar.link_list().size() == n0, "над самим цехом связь не создаётся")

	print("— убрать щелчком по линии")
	var pts := OverlayLayer.logi_curve(shop.center * T, cant.center * T, "canteen")
	var mid := pts[pts.size() / 2]
	tool.logi_press_at(mid)
	check(ar.link_of(shop, "canteen") == null, "щелчок по линии убрал связь")

	print("— убрать ПКМ и туалет")
	tool.logi_press_at(shop.center * T)
	tool.logi_release_at(wc.center * T)
	check(ar.link_of(shop, "wc") != null, "связь с туалетом назначена")
	var p2 := OverlayLayer.logi_curve(shop.center * T, wc.center * T, "wc")
	check(tool.logi_remove_at(p2[p2.size() / 2]), "ПКМ по линии убирает её")
	check(ar.link_of(shop, "wc") == null, "связь с туалетом снята")

	print("— ИТР")
	var office: Rooms.Room = null
	for r in sim.rooms.list:
		if Areas.is_office_type(r.type):
			office = r
			break
	if office:
		tool.logi_press_at(office.center * T)
		tool.logi_release_at(cant.center * T)
		check(ar.itr_of("canteen") != null and ar.itr_of("canteen").id == cant.id, "от конторы — столовая ИТР назначена")
		var ls := ar.link_list()
		check(ls.size() >= 1 and bool(ls[ls.size() - 1]["itr"]), "связь ИТР помечена для пунктира")
		tool.logi_press_at(office.center * T)
		tool.logi_release_at(_first(sim, "locker").center * T if _first(sim, "locker") else cant.center * T)
		check(not ar.itr.has("locker"), "ИТР и бытовка не связываются")
		ar.set_itr("canteen", null)
	else:
		print("  (в сценарии нет конторы — часть про ИТР пропущена)")

	print("— столовая «только ИТР»")
	check(not ar.is_itr_canteen(cant), "сначала для всех")
	tool.logi_press_at(cant.center * T)
	tool.logi_release_at(cant.center * T)
	check(ar.is_itr_canteen(cant), "щелчок по столовой — только для ИТР")
	tool.logi_press_at(cant.center * T)
	tool.logi_release_at(cant.center * T)
	check(not ar.is_itr_canteen(cant), "второй щелчок вернул")

	print("— выход")
	hud.toggle_logistics()
	check(tool.mode == "select", "та же кнопка выходит")
	hud.toggle_logistics()
	tool.set_mode("select")
	await _wait(2)
	hud.toggle_logistics()
	hud.toggle_plan()
	check(tool.mode == "select" and tool.plan_mode, "кнопка «План» выводит из логистики в план")
	hud.toggle_logistics()
	check(tool.mode == "logistics" and not tool.plan_mode, "логистика выводит из плана")
	hud.toggle_sub("objects")
	check(tool.mode == "select", "другая кнопка нижней панели выходит из оверлея")
	hud.toggle_logistics()
	hud.set_overlay("dirt")
	check(tool.mode == "select", "другой слой выходит из логистики")
	hud.set_overlay("dirt")

	print("РЕЗУЛЬТАТ: " + ("ВСЁ ВЕРНО" if fails.is_empty() else "ОШИБКИ: " + str(fails)))
	get_tree().quit(0 if fails.is_empty() else 1)
