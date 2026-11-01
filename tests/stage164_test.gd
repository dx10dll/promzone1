extends SceneTree
## Тест 1.64: рутина (заказ материала) — только в журнал; помещение без пола — помещение и в нём ставят зону;
## строитель несёт материал на 6–8 клеток и строит стены подряд; «Распределение» вместо «Линий»; в музыке нет «только вальсов»;
## гарь после пожара убирают как грязь; газета не пишет про несуществующее; поддоны у зоны отгрузки внутри неё; насос в «Песочнице» подключён.
## godot --headless --path . --audio-driver Dummy -s res://tests/stage164_test.gd

const S := preload("res://tests/setups.gd")

var fails: Array[String] = []


func check(cond: bool, what: String) -> void:
	print(("  ✓ " if cond else "  ✗ ") + what)
	if not cond:
		fails.append(what)


func _game(scn: String, seed_v: int) -> Sim:
	var g := Scenario.new_game(scn, "mech", "calm", seed_v)
	g.story.enabled = false
	g.progress.tutorial = -1
	return g


func _run(sim: Sim, minutes: float, until: Callable = Callable()) -> float:
	var t := 0.0
	while t < minutes:
		sim.tick(1.0)
		t += 1.0
		if until.is_valid() and bool(until.call()):
			break
	return t


## Сколько раз строители брали материал в руки, пока достраивали ряд стен.
func _trips(carry: int) -> Array:
	var old: Variant = (Defs.build_mats["bm_brick"] as Dictionary).get("carry", 2)
	(Defs.build_mats["bm_brick"] as Dictionary)["carry"] = carry
	var g := _game("sandbox", 1641)
	g.money = 5000000.0
	var p := g.world.plot
	var y := p.position.y + 8
	var x0 := p.position.x + 12
	for k in 10:
		g.place_wall_bp(Vector2i(x0 + k, y), World.W_BRICK)
	for k2 in 10:
		var it := g.new_item("bmat", "bm_brick", "bmat")
		g.put_on_ground(it, Vector2i(x0 + 4, y + 3))
	var had := {}
	var trips := 0
	var left := 0
	for tm in 1500:
		g.tick(1.0)
		for w in g.workers:
			var has := false
			for iid in [w.carrying] + w.carry_extra:
				var it2: Item = g.items.get(int(iid))
				if it2 and it2.kind == "bmat":
					has = true
			if has and not bool(had.get(w.id, false)):
				trips += 1
			had[w.id] = has
		left = 0
		for k3 in g.bp_cells.keys():
			left += 1
		if left == 0:
			break
	var done := 10 - left
	(Defs.build_mats["bm_brick"] as Dictionary)["carry"] = old
	g.dispose()
	return [trips, done]


func _initialize() -> void:
	Defs.load_all()

	print("— рутина только в журнал")
	var g := _game("sandbox", 1640)
	g.money = 5000000.0
	var popups: Array[String] = []
	g.notified.connect(func(t: String, _l: int, _c: Vector2i) -> void: popups.append(t))
	var p := g.world.plot
	for k in 8:
		g.place_wall_bp(Vector2i(p.position.x + 12 + k, p.position.y + 8), World.W_BRICK)
	_run(g, 40.0)
	var ord := ""
	for e: Dictionary in g.events:
		if str(e["text"]).contains("Заказаны стройматериалы"):
			ord = str(e["text"])
	check(ord != "", "заказ материала записан в журнал: %s" % ord)
	var pop_ord := false
	for t in popups:
		if t.contains("Заказаны стройматериалы"):
			pop_ord = true
	check(not pop_ord, "всплывающего уведомления о заказе материала нет")
	g.note("проверка")
	check(popups.size() == 0 or not popups.has("проверка"), "Sim.note не шлёт уведомление")
	g.dispose()

	print("— помещение без пола")
	var r := _game("sandbox", 1642)
	r.money = 5000000.0
	var q := r.world.plot
	var o := Vector2i(q.position.x + 14, q.position.y + 6)
	for x in range(o.x, o.x + 7):
		for y in range(o.y, o.y + 6):
			if x == o.x or x == o.x + 6 or y == o.y or y == o.y + 5:
				r.world.wall[r.world.idx(Vector2i(x, y))] = World.W_BRICK
	r.world.wall[r.world.idx(Vector2i(o.x + 3, o.y + 5))] = World.W_DOOR
	r.world.refresh_all()
	r.rooms.update()
	var inside := o + Vector2i(3, 2)
	check(r.world.flr[r.world.idx(inside)] <= 0, "пола внутри нет")
	check(r.rooms.room_at(inside) != null, "замкнутая коробка без пола — помещение")
	var n := r.rooms.paint(Rect2i(o + Vector2i(1, 1), Vector2i(5, 4)), "workshop")
	check(n == 20, "зона «цех» поставилась на всю площадь без пола: %d кл." % n)
	var rm := r.rooms.room_at(inside)
	check(rm != null and rm.type == "workshop" and rm.area() == 20, "помещение получило назначение: %s" % (rm.type if rm else "—"))
	var n2 := r.rooms.fill(inside, "storage")
	check(n2 == 20 and r.rooms.room_at(inside).type == "storage", "заливка зоны ведром тоже работает: %d" % n2)
	# улица рядом с коробкой — не помещение
	var outside := o + Vector2i(-3, 2)
	check(r.rooms.room_at(outside) == null and r.rooms.paint(Rect2i(outside, Vector2i(2, 2)), "workshop") == 0, "открытая земля помещением не становится")
	# коробка с дырой в стене — не помещение
	r.world.wall[r.world.idx(Vector2i(o.x + 6, o.y + 2))] = World.W_NONE
	r.world.refresh_all()
	r.rooms.update()
	check(r.rooms.room_at(inside) == null, "стена с дырой: помещения нет")
	r.dispose()

	print("— строитель: больше материала за ходку")
	check(BuildMats.carry("bm_brick") >= 6 and BuildMats.carry("bm_tile") >= 6, "носит за раз: кирпич %d, плитка %d" % [BuildMats.carry("bm_brick"), BuildMats.carry("bm_tile")])
	var before := _trips(2)
	var after := _trips(BuildMats.carry("bm_brick"))
	check(int(after[1]) == 10, "10 стен построено: %d" % int(after[1]))
	check(int(after[0]) < int(before[0]) and int(after[0]) <= 4, "ходок за 10 стен: %d (при 2 за раз было %d)" % [int(after[0]), int(before[0])])

	print("— «Распределение» вместо «Линий»")
	var hud_src := FileAccess.get_file_as_string("res://scripts/ui/hud.gd")
	check(hud_src.contains('["logistics", "Распределение",') and not hud_src.contains('["logistics", "Линии"'), "подвкладка слоя «Логистика» называется «Распределение»")
	TranslationServer.set_locale("en")
	check(TranslationServer.translate("Распределение") == "Distribution", "EN: Distribution")
	check(TranslationServer.translate("Распределение: протяните линию от цеха (или конторы — для ИТР) к бытовке, душевой, туалету, столовой или комнате отдыха.").begins_with("Distribution:"), "EN: легенда")
	TranslationServer.set_locale("ru")

	print("— музыка")
	var names: Array[String] = []
	for m: Array in MusicDirector.MODES:
		names.append(str(m[1]))
	check(MusicDirector.MODES.size() == 2 and not "".join(names).contains("вальс"), "режимов два, без «только вальсов»: %s" % str(names))
	var s0 := _game("sandbox", 1643)
	check(MusicDirector.playlist(s0, 2) == MusicDirector.ALL and MusicDirector.playlist(s0, 1) == MusicDirector.ALL, "старое «только вальсы» (2) играет как «всё подряд»")
	check(MusicDirector.ALL.has("music_waltz") and MusicDirector.ALL.has("music_accwaltz"), "вальсы играют в «всё подряд»")
	check(MusicDirector.norm_mode(2) == 1 and MusicDirector.norm_mode(0) == 0, "норма режима")
	s0.dispose()

	print("— гарь после пожара")
	var f := _game("sandbox", 1644)
	f.money = 5000000.0
	S.hire(f, "cleaner", "clean", 3)
	var sc := Vector2i(f.gate_x + 3, f.world.plot.end.y - 8)
	f.story.burn_mark(f.world.idx(sc))
	check(f.story.soot.has(f.world.idx(sc)), "след пожара есть")
	check(f.upkeep.dirty_cells(55, 30).has(sc), "он в очереди уборки")
	_run(f, 2880.0, func() -> bool: return f.story.soot.is_empty())
	check(f.story.soot.is_empty(), "гарь убрали со временем")
	f.dispose()

	print("— газета")
	var pp := _game("sandbox", 1645)
	S.hire(pp, "cook", "cook", 3)   # повар есть, столовой нет
	var texts := ""
	for i in 60:
		pp.minute = float(8 + i * 3) * 1440.0 + 480.0
		for id in Defs.paper.get("events", {}).keys():
			pp.paper.event(str(id), ["Х", "У"])
		pp.paper.publish(true)
	for iss: Dictionary in pp.paper.issues:
		for it2: Dictionary in iss["items"]:
			texts += str(it2.get("title", "")) + " | " + str(it2.get("text", "")) + "\n"
	for ln in texts.split("\n"):
		if ln.to_lower().contains("компот"):
			print("    ", ln)
	for word in ["компот", "буфетчи", "в столовой", "бытовк", "раздевал", "профком", "профсоюз", "курилк", "кипятильник"]:
		check(not texts.to_lower().contains(word), "без нужной вещи газета не пишет «%s»" % word)
	# всё разом при выпусках за много недель (issues хранит 12 — прогоним ещё раз с другим числом)
	var cnt := 0
	for k in 40:
		pp.minute = float(300 + k * 7) * 1440.0 + 480.0
		pp.paper.publish(true)
		for it3: Dictionary in (pp.paper.issues[0] as Dictionary)["items"]:
			var tx := (str(it3.get("title", "")) + str(it3.get("text", ""))).to_lower()
			if tx.contains("компот") or tx.contains("столовой") or tx.contains("бытовк") or tx.contains("профком"):
				cnt += 1
	check(cnt == 0, "ещё 40 выпусков: упоминаний несуществующего %d" % cnt)
	check(pp.paper.cond_ok("room:canteen") == false and pp.paper.cond_ok("cook") and not pp.paper.cond_ok("off") and not pp.paper.cond_ok("cook,union"), "условия заметок")
	pp.dispose()

	print("— старты «Чистое поле» и «Песочница»")
	for scn in ["field", "sandbox"]:
		var s := _game(scn, 1646)
		for i in 30:
			s.tick(1.0)
		var sh := s.logi.ship_cells()
		var pallets := 0
		var outs := 0
		for t: Thing in s.things.values():
			if t.def_id == "pallet":
				pallets += 1
				if not sh.has(t.cell):
					outs += 1
		check(pallets >= 2 and outs == 0, "%s: поддонов %d, вне зоны отгрузки %d" % [scn, pallets, outs])
		var pump_ok := true
		var badges := 0
		for t2: Thing in s.things.values():
			if t2.kind() == "pump":
				s.water.update()
				pump_ok = pump_ok and int(s.water.thing_net.get(t2.id, -1)) >= 0 and s.power.powered(t2)
			if not ObjectBadges.reason(s, t2).is_empty():
				badges += 1
		check(pump_ok, "%s: насос подключён к трубе и под током" % scn)
		check(badges == 0, "%s: значков проблем у объектов нет (%d)" % [scn, badges])
		var warns := 0
		for e2: Dictionary in s.events:
			if int(e2["level"]) >= Sim.LVL_WARN:
				warns += 1
		check(warns == 0, "%s: тревог в журнале нет (%d)" % [scn, warns])
		s.dispose()

	print("РЕЗУЛЬТАТ: " + ("ВСЁ ВЕРНО" if fails.is_empty() else "ОШИБКИ: %d" % fails.size()))
	quit(0 if fails.is_empty() else 1)
