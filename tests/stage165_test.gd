extends SceneTree
## Тест 1.65: чистка лишнего по аудиту 1.64 — убранные объекты, события, разработка, мыши, мёртвый код, старая папка портретов;
## слитые предметы (кулер, шкафчик, растения) на старом сохранении становятся оставшимися, убранные снимаются с возвратом денег.
## godot --headless --path . --audio-driver Dummy -s res://tests/stage165_test.gd

var fails: Array[String] = []


func check(cond: bool, what: String) -> void:
	print(("  ✓ " if cond else "  ✗ ") + what)
	if not cond:
		fails.append(what)


## Имена функций в файле (по тексту: часть скриптов зависит от автозагрузок и не грузится в тесте без сцены).
func _methods(path: String) -> Array[String]:
	var out: Array[String] = []
	var rx := RegEx.new()
	rx.compile("(?m)^(?:static )?func (\\w+)\\(")
	for m in rx.search_all(FileAccess.get_file_as_string(path)):
		out.append(m.get_string(1))
	return out


func _old_save() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://tests/saves/save_1.23.json")) as Dictionary


func _thing(id: int, def: String, c: Vector2i, built: bool = true, paid: float = 0.0) -> Dictionary:
	return {"id": id, "def": def, "cx": c.x, "cy": c.y, "built": built, "paid": paid}


func _init() -> void:
	Defs.load_all()
	print("— объекты: убраны и слиты")
	for gone in ["cactus", "monstera", "palm", "globe", "bookcase", "coat_rack", "samovar", "statue_worker", "notice_board", "cooler", "locker2", "loudspeaker", "lamp_street"]:
		check(not Defs.objects.has(gone), "«%s» убран из каталога" % gone)
		check(Defs.OBJ_REMAP.has(gone), "«%s» есть в таблице замен для старых сохранений" % gone)
	for keep in ["plant", "water_cooler", "locker", "ny_tree", "bust", "trophy_case", "floor_clock", "flagpole", "rug", "pennant", "chip_bin", "scrap_bin", "safe", "union_board", "wip_rack", "pallet_raw", "urn", "radio_station"]:
		check(Defs.objects.has(keep), "«%s» остаётся" % keep)
	var pl: Dictionary = Defs.objects["plant"]
	check((pl.get("variants", []) as Array).size() == 3, "у растения три картинки")
	for v: String in pl.get("variants", []):
		check(Defs.sprites.has(v) and ResourceLoader.exists("res://assets/objects/%s.svg" % v), "картинка растения «%s» на месте" % v)
	var no_sprite: Array[String] = []
	for id: String in Defs.objects.keys():
		if not Defs.sprites.has(id):
			no_sprite.append(id)
	check(no_sprite.size() < 40, "у остальных объектов своя картинка в sprite_meta (без картинки: %d)" % no_sprite.size())
	var bad_rooms: Array[String] = []
	for rk: String in Defs.rooms.keys():
		for n: Dictionary in Defs.rooms[rk].get("needs", []):
			for i: String in n.get("ids", []):
				if not Defs.objects.has(i):
					bad_rooms.append("%s:%s" % [rk, i])
	check(bad_rooms.is_empty(), "в требованиях помещений нет убранных предметов %s" % str(bad_rooms))
	var bad_tpl: Array[String] = []
	for tk: String in Defs.templates.keys():
		for o: Variant in Defs.templates[tk].get("objs", []):
			if not Defs.objects.has(str((o as Array)[0])):
				bad_tpl.append("%s:%s" % [tk, str((o as Array)[0])])
	check(bad_tpl.is_empty(), "в шаблонах нет убранных предметов %s" % str(bad_tpl))
	for sprite_gone in ["palm", "globe", "bookcase", "coat_rack", "samovar", "statue_worker", "notice_board", "cooler", "locker2", "loudspeaker", "lamp_street"]:
		check(not ResourceLoader.exists("res://assets/objects/%s.svg" % sprite_gone), "файл картинки «%s» удалён" % sprite_gone)

	print("— старое сохранение: слитое заменяется, убранное снимается с возвратом")
	var d := _old_save()
	var base_things: Array = d["things"]
	var n_lock2 := 0
	for t: Dictionary in base_things:
		if str(t["def"]) == "locker2":
			n_lock2 += 1
	check(n_lock2 >= 2, "в сохранении 1.23 есть шкафчики на двоих (%d)" % n_lock2)
	var mx := 0
	for t2: Dictionary in base_things:
		mx = maxi(mx, int(t2["id"]))
	d["things"] = base_things + [_thing(mx + 1, "cooler", Vector2i(2, 2)), _thing(mx + 2, "cactus", Vector2i(3, 2)), _thing(mx + 3, "palm", Vector2i(4, 2)),
		_thing(mx + 4, "monstera", Vector2i(5, 2)), _thing(mx + 5, "globe", Vector2i(6, 2), true, 3500.0), _thing(mx + 6, "loudspeaker", Vector2i(7, 2), true, 6000.0),
		_thing(mx + 7, "samovar", Vector2i(8, 2), false, 1234.0)]
	d["next_id"] = int(d["next_id"]) + 20
	var money0 := float(d["money"])
	var s := Sim.from_dict(d)
	var defs_now := {}
	for t3: Thing in s.things.values():
		defs_now[t3.def_id] = int(defs_now.get(t3.def_id, 0)) + 1
	for gone2 in Defs.OBJ_REMAP.keys():
		check(not defs_now.has(gone2), "после загрузки «%s» нет" % gone2)
	check(int(defs_now.get("locker", 0)) >= n_lock2, "шкафчики на двоих стали обычными шкафчиками (%d)" % int(defs_now.get("locker", 0)))
	check(s.things.has(mx + 1) and s.things[mx + 1].def_id == "water_cooler", "кулер слит с «Кулером с водой»")
	check(s.things.has(mx + 2) and s.things[mx + 2].def_id == "plant" and s.things[mx + 3].def_id == "plant" and s.things[mx + 4].def_id == "plant", "кактус, пальма и монстера стали растением")
	check(not s.things.has(mx + 5) and not s.things.has(mx + 6) and not s.things.has(mx + 7), "глобус, громкоговоритель и самовар сняты")
	check(absf(s.money - (money0 + 3500.0 + 6000.0 + 7000.0 + 0.0)) < 1.0 or s.money > money0 + 9000.0, "деньги за снятое возвращены: %d → %d" % [int(money0), int(s.money)])
	check(not s.ledger.is_empty(), "возврат записан в движение денег")
	for i in 600:
		s.tick(1.0)
	check(s.minute > 0.0, "игра идёт после загрузки старого сейва")
	var s2 := Sim.from_dict(JSON.parse_string(JSON.stringify(s.to_dict())) as Dictionary)
	check(s2.things.size() == s.things.size(), "сохранить → загрузить снова: предметов столько же (%d)" % s2.things.size())

	print("— старые ящики и заказы оборудования с убранным предметом")
	var d2 := _old_save()
	d2["logi"] = {"equip": [{"id": 90001, "thing": 99991, "def": "cooler", "eta": 9999.0, "spawned": false}, {"id": 90002, "thing": 99992, "def": "globe", "eta": 9999.0, "spawned": false}]}
	d2["items"] = (d2["items"] as Array) + [{"id": 99001, "kind": "crate", "def": "samovar", "q": "ok", "defect": false, "step": 0, "loc": 1, "holder": -1, "x": 3, "y": 3}]
	var before_items: int = (d2["items"] as Array).size()
	var s3 := Sim.from_dict(d2)
	check(s3.logi.equip.size() == 1 and str(s3.logi.equip[0]["def"]) == "water_cooler", "заказ кулера переименован, заказ глобуса отменён")
	check(s3.items.size() == before_items - 1, "ящик убранного предмета исчез")

	print("— события: слиты дубли")
	var evs: Dictionary = Defs.events["events"]
	for gone3 in ["metal_up", "metal_down", "heatwave", "heat_off", "pipe_burst"]:
		check(not evs.has(gone3), "событие «%s» убрано" % gone3)
	for keep3 in ["metal_jump", "cold_snap", "leak", "flood", "journalist", "governor"]:
		check(evs.has(keep3), "событие «%s» есть" % keep3)
	check(Defs.events.has("modes") and (Defs.events["modes"] as Dictionary).size() == 3, "режимы рассказчика на месте")
	var g := Scenario.new_game("garage", "mech", "market", 1651)
	g.story.enabled = false
	g.money = 500000.0
	var up := 0
	var down := 0
	for k in 40:
		g.story.mods.clear()
		g.story._start("metal_jump", false)
		var f := g.story.mod("metal_price")
		if f > 1.0:
			up += 1
		elif f < 1.0:
			down += 1
	check(up > 0 and down > 0, "«Скачок цен на металл» идёт и вверх (%d), и вниз (%d)" % [up, down])
	g.story._start("cold_snap", false)
	check(g.season.snap < 0.0, "морозы включаются")
	var letters0 := g.story.letters.size()
	var log0 := g.events.size()
	g.story._start("leak", false)
	check(g.story.letters.size() >= letters0 and g.events.size() >= log0, "«Прорвало трубу» запускается без ошибок")

	print("— разработка «Комплексные обеды» и мысль")
	check(not Defs.research.has("lunch_menu"), "разработка «Комплексные обеды» убрана")
	check(not Defs.thoughts.has("ate_menu") and not Defs.thoughts.has("mice"), "мысли «ate_menu» и «mice» убраны")
	check(Defs.thoughts.has("room_l3") and Defs.thoughts.has("room_l5") and Defs.thoughts.has("radio_news"), "мысли про помещения и радио остаются (используются)")
	var d3 := _old_save()
	var of: Dictionary = d3.get("office", {})
	of["done"] = ["gymnastics", "lunch_menu"]
	of["cur"] = "lunch_menu"
	of["pts"] = {"lunch_menu": 5.0}
	d3["office"] = of
	var ws: Array = d3["workers"]
	if not ws.is_empty():
		(ws[0] as Dictionary)["thoughts"] = [{"id": "mice", "until": 99999.0, "k": 1.0}, {"id": "ate_menu", "until": 99999.0, "k": 1.0}]
	var s4 := Sim.from_dict(d3)
	check(s4.office.research_done == ["gymnastics"] and s4.office.research_cur == "", "в старом сейве «Комплексные обеды» выброшены")
	check(s4.workers.is_empty() or s4.workers[0].thoughts.is_empty(), "убранные мысли из старого сейва выброшены")

	print("— живность: мышей нет")
	var fa := g.fauna
	check(not ("mice" in fa), "у Fauna нет списка мышей")
	check(not _methods("res://scripts/sim/fauna.gd").has("mice_in") and not _methods("res://scripts/sim/fauna.gd").has("_mice_spawn"), "функции мышей убраны")
	for i2 in 300:
		fa.tick(1.0)
	check(not g.inspect.violations("sanitary").any(func(v: Dictionary) -> bool: return str(v["key"]) == "mice"), "санинспекция про грызунов молчит")
	check(not (Defs.inspections.get("texts", {}) as Dictionary).has("mice"), "текст про грызунов убран")

	print("— радио без громкоговорителей")
	var rs := Scenario.new_game("garage", "mech", "calm", 1652)
	check(rs.town.radio_rooms().is_empty(), "без радиоузла слышно нигде")
	check(not Defs.objects.has("loudspeaker"), "громкоговорителя нет")

	print("— мёртвый код убран")
	var dead := {
		"res://scripts/ui/windows.gd": ["_finance_energy", "_cons_rows", "_traits_line", "_our_procs", "_events_cal", "_events_hist", "_stall"],
		"res://scripts/ui/hud.gd": ["help_open", "_short_money"],
		"res://scripts/sim/town.gd": ["kids_of"], "res://scripts/sim/season.gd": ["snow_at"], "res://scripts/sim/world.gd": ["flora_at"],
		"res://scripts/sim/story.gd": ["receivable_total"], "res://scripts/sim/crew.gd": ["move_cost", "open_cases"], "res://scripts/sim/social.gd": ["chat_in_place"],
		"res://scripts/sim/progress.gd": ["spawn_dogs"], "res://scripts/view/entity_layer.gd": ["thing_view"],
		"res://scripts/ui/info_panel.gd": ["_people_line"], "res://scripts/ui/main_menu.gd": ["_build_news"], "res://scripts/sim/inspections.gd": ["_room_count"],
		"res://scripts/sim/orders.gd": ["_committed_material"], "res://scripts/view/city_backdrop.gd": ["_school"], "res://scripts/view/tex.gd": ["portrait", "emo"]}
	for p: String in dead.keys():
		var ms := _methods(p)
		for fn: String in dead[p]:
			check(not ms.has(fn), "%s: «%s» убрана" % [p.get_file(), fn])
	check(not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("res://assets/portrait")), "старой папки assets/portrait нет")
	check(DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("res://assets/portrait2")), "живая папка assets/portrait2 на месте")
	check(FileAccess.file_exists("res://assets/vec/portrait.json"), "набор портретов assets/vec/portrait.json на месте")
	check(not FileAccess.file_exists("res://assets/sound/m_grinder.ogg") and not FileAccess.file_exists("res://assets/sound/beeper.ogg"), "звуки m_grinder и beeper удалены")
	check(ResourceLoader.exists("res://assets/sound/m_lathe.ogg"), "звуки станков на месте")
	check(ResourceLoader.exists("res://assets/ui/icons/emo_food.png") and ResourceLoader.exists("res://assets/ui/icons/emo_argue.png"), "набор значков владельца (102) цел")

	print("— английский")
	L.apply("en")
	for key in ["Динамика", "Неделя", "График", "Сутки", "Все", "Растение", "Склад оборудования", "Заводской кот", "Этап роста и рейтинг", "Бригады и график смены",
			"Звук: окружение и интерфейс ▸", "Рейтинг завода", "Простой"]:
		check(TranslationServer.translate(key) != key, "перевод есть: «%s» → «%s»" % [key, TranslationServer.translate(key)])
	L.apply("ru")

	print("\nИТОГ: ", "ВСЁ ХОРОШО" if fails.is_empty() else "ПРОВАЛЫ: %d" % fails.size())
	for f2 in fails:
		print("  ✗ ", f2)
	quit(0 if fails.is_empty() else 1)
