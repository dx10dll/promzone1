extends Node
## Тест 1.60: меню «Объекты» — 8 вкладок (показ поверх старых 16 категорий), «Живость города», «Ники».
## godot --headless --path . --audio-driver Dummy res://tests/stage160_ui.tscn

var fails: Array[String] = []


func check(cond: bool, what: String) -> void:
	print(("  ✓ " if cond else "  ✗ ") + what)
	if not cond:
		fails.append(what)


func _wait(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _tabs(hud: Hud) -> Array[String]:
	var out: Array[String] = []
	for b: Node in hud.sub_panel.find_children("*", "Button", true, false):
		if b.has_meta("cat") and not b.is_queued_for_deletion():
			out.append(str(b.get_meta("cat")))
	return out


func _tiles(hud: Hud) -> Array[String]:
	var out: Array[String] = []
	for b: Node in hud.sub_panel.find_children("*", "Button", true, false):
		if b.has_meta("arg") and not b.is_queued_for_deletion():
			out.append(str(b.get_meta("arg")))
	return out


func _ready() -> void:
	var Game: Node = get_node("/root/Game")
	Game.pending = "new"
	Game.pending_scn = "field"
	Game.pending_profile = "mech"
	Game.pending_opts = {"tutorial": false}
	Game.pending_seed = 1600
	Game.settings["tutorial_done"] = true
	var gm: GameMain = load("res://scenes/game.tscn").instantiate()
	add_child(gm)
	await _wait(30)
	var hud := gm.hud
	var sim := gm.sim
	sim.progress.all_open = true

	print("— 8 групп объектов")
	check(Hud.OBJ_CATS.size() == 8, "вкладок 8 (%d)" % Hud.OBJ_CATS.size())
	var cnt := {}
	var bad: Array[String] = []
	var raw_cats := {}
	for k: String in Defs.objects.keys():
		var od: Dictionary = Defs.objects[k]
		if bool(od.get("legacy", false)):
			continue
		raw_cats[str(od.get("cat", ""))] = true
		var g := Hud.obj_group(str(od.get("cat", "")))
		if not Hud.OBJ_CATS.has(g):
			bad.append(k)
		cnt[g] = int(cnt.get(g, 0)) + 1
	check(bad.is_empty(), "каждый объект попадает в одну из 8 групп (мимо: %s)" % str(bad))
	check(cnt.size() == 8, "все 8 групп непустые: %s" % str(cnt))
	check(raw_cats.size() == 16, "в данных по-прежнему 16 старых категорий (%d)" % raw_cats.size())
	var unmapped: Array[String] = []
	for c: String in raw_cats.keys():
		if not Hud.OBJ_GROUP_OF.has(c):
			unmapped.append(c)
	check(unmapped.is_empty(), "у каждой старой категории есть группа %s" % str(unmapped))
	hud.obj_cat = "ЧПУ"
	check(hud.obj_cat == "Станки", "старое имя категории («ЧПУ») ведёт во вкладку «Станки»")
	hud.obj_cat = "Освещение"
	check(hud.obj_cat == "Инженерия", "«Освещение» → «Инженерия»")

	print("— меню «Стройка/Объекты»")
	hud.toggle_sub("objects")
	await _wait(3)
	var tabs := _tabs(hud)
	check(tabs.size() == 8, "в меню объектов 8 вкладок (%s)" % str(tabs))
	for g: String in Hud.OBJ_CATS:
		hud.obj_cat = g
		hud._fill_sub()
		await _wait(2)
		var shown := _tiles(hud)
		var exp := 0
		for k: String in Defs.objects.keys():
			if not bool(Defs.objects[k].get("legacy", false)) and Hud.obj_group(str(Defs.objects[k].get("cat", ""))) == g:
				exp += 1
		check(shown.size() == exp and exp > 0, "вкладка «%s»: плиток %d из %d" % [g, shown.size(), exp])
	BuildMenu.query["objects"] = "токарн"
	hud._fill_sub()
	await _wait(2)
	var found := _tiles(hud)
	check(found.size() >= 3, "поиск «токарн» находит станки из любой вкладки (%d)" % found.size())
	BuildMenu.query["objects"] = ""
	hud.toggle_sub("build")
	await _wait(3)
	var has_plan := false
	for b: Node in hud.sub_panel.find_children("*", "Button", true, false):
		if b.has_meta("cat") and str(b.get_meta("cat")) == "Калька (план)":
			has_plan = true
	check(has_plan, "кнопка «Калька (план)» на месте в строке «Стройка»")
	hud.toggle_sub("build")

	print("— живость города")
	var folk: StreetFolk = gm.find_children("*", "StreetFolk", true, false)[0]
	var life: CityLife = gm.city.life
	check(Game.settings.get("city_life", -1) == 2 and Game.settings.get("nick_mode", -1) == 1, "по умолчанию: живость полная, ники «важные»")
	var res := {}
	for lvl: int in [2, 1, 0]:
		Game.settings["city_life"] = lvl
		await _wait(20)
		sim.fauna.pigeons.clear()
		sim.minute = 12.0 * 60.0
		for i in 80:
			sim.fauna._spawn()
		var live := sim.fauna.pigeons.filter(func(p: Dictionary) -> bool: return str(p["st"]) != "gone" and not bool(p.get("leave", false)))
		res[lvl] = [folk._folk.size(), life.visible_cars().size(), live.size()]
		print("    режим %d: горожан %d, машин %d, голубей %d" % [lvl, res[lvl][0], res[lvl][1], res[lvl][2]])
	check(res[2][0] == StreetFolk.FOLK_N and res[2][1] == life._cars.size() and res[2][2] >= 2, "полная: всё как раньше")
	check(res[1][0] == StreetFolk.FOLK_N / 2 and res[1][1] * 2 >= life._cars.size() - 1 and res[1][1] * 2 <= life._cars.size() + 1, "умеренная: горожан и машин вдвое меньше")
	check(res[1][2] < res[2][2] or res[2][2] <= 2, "умеренная: голубей не больше, чем при полной")
	check(res[0][0] == 0 and res[0][1] == 0 and res[0][2] == 0, "выкл.: ни горожан, ни машин, ни голубей")
	check(CityMode.vehicle_shown("delivery", 0) and CityMode.vehicle_shown("pickup", 0) and CityMode.vehicle_shown("visit", 0), "выкл.: поставки, отгрузка и посетители на месте")
	check(not CityMode.vehicle_shown("fire", 0) and not CityMode.vehicle_shown("scrap", 0) and CityMode.vehicle_shown("fire", 1), "выкл.: пожарные и мусоровоз скрыты, при умеренной — видны")
	check(not CityMode.cat_shown(0) and CityMode.cat_shown(1), "кот скрыт только при «выкл.»")
	# настоящая машина-поставка в режиме «выкл.» видна, ломовоз — нет
	var vd := sim.spawn_vehicle("delivery")
	vd.state = "arriving"
	var vs := sim.spawn_vehicle("scrap")
	vs.state = "arriving"
	await _wait(5)
	var vdn: Node2D = gm.ents.vans.get(vd.id)
	var vsn: Node2D = gm.ents.vans.get(vs.id)
	check(vdn != null and vdn.visible and vsn != null and not vsn.visible, "в режиме «выкл.» поставка видна, ломовоз скрыт")
	check(gm.ents.workers.size() > 0 and sim.workers.size() > 0, "наши люди на месте")
	Game.settings["city_life"] = 1
	await _wait(5)
	check(vsn.visible, "при умеренной ломовоз виден")
	Game.settings["city_life"] = 2
	await _wait(20)
	check(folk._folk.size() == StreetFolk.FOLK_N, "возврат на «полную» возвращает горожан")

	print("— ники")
	check(NameLayer.shows_nick(NameLayer.NICK_NONE, true, true, true, true) == false, "«нет»: ника нет даже у выбранного")
	check(NameLayer.shows_nick(NameLayer.NICK_ALL, false, false, false, false), "«все»: ник у каждого")
	check(not NameLayer.shows_nick(NameLayer.NICK_IMPORTANT, false, false, false, false), "«важные»: рядовой без проблем — без ника")
	check(NameLayer.shows_nick(NameLayer.NICK_IMPORTANT, true, false, false, false), "«важные»: выбранный")
	check(NameLayer.shows_nick(NameLayer.NICK_IMPORTANT, false, true, false, false), "«важные»: бригадир")
	check(NameLayer.shows_nick(NameLayer.NICK_IMPORTANT, false, false, true, false), "«важные»: под мышью")
	check(NameLayer.shows_nick(NameLayer.NICK_IMPORTANT, false, false, false, true), "«важные»: с серьёзной проблемой")

	print("— настройки")
	var sv := VBoxContainer.new()
	add_child(sv)
	SettingsUI.build(sv)
	var texts: Array[String] = []
	for ob: Node in sv.find_children("*", "OptionButton", true, false):
		for i in (ob as OptionButton).item_count:
			texts.append((ob as OptionButton).get_item_text(i))
	check(texts.has("умеренная") and texts.has("важные") and texts.has("полная"), "в настройках есть «Живость города» и «Ники»")
	var labels: Array[String] = []
	for l: Node in sv.find_children("*", "Label", true, false):
		labels.append((l as Label).text)
	check(labels.has("Живость города") and labels.has("Ники"), "подписи рядов")
	sv.queue_free()

	print("— английский")
	L.apply("en")
	check(tr("Живость города") == "City liveliness" and tr("Сварка и термо") == "Welding & heat" and tr("Ники") == "Nicknames", "переводы на месте")
	L.apply("ru")

	print("РЕЗУЛЬТАТ: " + ("ВСЁ ВЕРНО" if fails.is_empty() else "ОШИБКИ: %d" % fails.size()))
	get_tree().quit(0 if fails.is_empty() else 1)
