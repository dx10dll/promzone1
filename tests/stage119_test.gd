extends SceneTree
## Тест версии 1.19 «Управление»: станки с ЧПУ по прототипам (Сайдвей — фрезерный, новый Майдэй),
## мелкий крепёж (болт, гайка, шпилька), управление человеком («Взять под управление», «Сделать сейчас»),
## миграция сохранений v11.
## godot --headless --path . -s res://tests/stage119_test.gd

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


func _free_cells(g: Sim, n: int, min_gap: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var pl := g.world.plot
	for y in range(pl.position.y + 1, pl.end.y - 1):
		for x in range(pl.position.x + 1, pl.end.x - 1):
			var c := Vector2i(x, y)
			var i := g.world.idx(c)
			if g.world.flr[i] != 0 or g.world.flora[i] != 0 or g.world.wall[i] != World.W_NONE or g.thing_at(c) or not g.world.passable(c):
				continue
			if g.rooms.room_at(c) != null:
				continue
			var ok := true
			for o in out:
				if absi(o.x - c.x) + absi(o.y - c.y) < min_gap:
					ok = false
			if ok:
				out.append(c)
			if out.size() >= n:
				return out
	return out


func _init() -> void:
	Defs.load_all()

	print("— станки с ЧПУ")
	var cnc: Array = []
	for k in Defs.objects.keys():
		if bool(Defs.objects[k].get("machine", {}).get("cnc", false)) and not bool(Defs.objects[k].get("legacy", false)):
			cnc.append(str(k))
	check(cnc.size() == 8 and cnc.has("cnc_maiday"), "восемь станков с ЧПУ, есть Майдэй: %s" % ", ".join(cnc))
	check(str(Defs.objects["cnc_sidway"]["machine"]["process"]) == "milling", "Сайдвей — фрезерный")
	check(str(Defs.objects["cnc_maiday"]["machine"]["process"]) == "turning", "Майдэй — токарный")
	var mills := 0
	var lathes := 0
	for k2: String in cnc:
		var pr := str(Defs.objects[k2]["machine"]["process"])
		mills += 1 if pr == "milling" else 0
		lathes += 1 if pr == "turning" else 0
	check(mills == 4 and lathes == 4, "по четыре фрезерных и токарных: %d и %d" % [mills, lathes])
	var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/sprite_meta.json"))
	var sizes := {}
	for k3: String in cnc:
		for suf in ["", "_v", "_b"]:
			var m: Dictionary = meta.get(k3 + suf, {})
			var an: Dictionary = m.get("anchors", {})
			check(not m.is_empty() and an.has("lamp") and (an.has("work") or an.has("chuck")), "%s%s: спрайт и якоря" % [k3, suf])
		var mm: Dictionary = meta.get(k3, {})
		sizes["%dx%d" % [int(mm.get("w", 0)), int(mm.get("h", 0))]] = true
	check(sizes.size() >= 6, "у станков разные силуэты (размеры спрайтов): %d" % sizes.size())
	check(FileAccess.file_exists("res://assets/objects/cnc_maiday.svg"), "спрайт Майдэя на месте")

	print("— мелкий крепёж")
	for p in ["bolt", "nut", "stud"]:
		check(Defs.products.has(p) and str(Defs.products[p]["size"]) == "s", "%s — мелкая деталь" % p)
		check(FileAccess.file_exists("res://assets/items/%s.svg" % p), "%s: значок" % p)
	check(Defs.route("nut").size() == 2 and str(Defs.route("nut")[1]["op"]) == "drilling", "гайка: точение и сверловка с резьбой")
	var prof: Array = Defs.profiles["mech"]["products"]
	check(prof.has("bolt") and prof.has("nut") and prof.has("stud"), "механический завод делает крепёж")
	var tv4 := Thing.new()
	tv4.def_id = "lathe_tv4"
	check(tv4.fits_part("bolt") and tv4.fits_part("stud"), "крепёж — на малых станках (ТВ-4)")
	for p2 in ["bolt", "nut", "stud"]:
		var pr2: Array = Defs.products[p2]["price"]
		var mat := float(Defs.materials[str(Defs.products[p2]["material"])]["price"])
		var mins := 0.0
		for o: Dictionary in Defs.route(p2):
			mins += float(o["time"])
		var per_min := ((float(pr2[0]) + float(pr2[1])) * 0.5 - mat) / mins
		check(per_min >= 70.0, "%s окупает станок: %.0f ₽ за минуту" % [p2, per_min])

	print("— управление человеком")
	var g := Scenario.new_game("garage", "mech", "calm", 191)
	g.story.enabled = false
	g.progress.tutorial = -1
	g.bmats.enabled = false
	g.money = 5000000.0
	run(g, 60.0)
	var w: Worker = null
	for x in g.workers:
		if x.present and not x.is_itr() and x.prof == "laborer":
			w = x
	if w == null:
		for x2 in g.workers:
			if x2.present and not x2.is_itr():
				w = x2
	check(w != null, "есть рабочий на смене")
	var cells := _free_cells(g, 3, 6)
	check(cells.size() == 3, "свободные клетки на участке: %s" % str(cells))
	if w and cells.size() == 3:
		var msg := g.brain.take_control(w)
		check(w.controlled and g.brain.controlled_worker() == w, "взят под управление: %s" % msg)
		run(g, 40.0, func() -> bool: return w.activity == "Ждёт вашей команды")
		check(w.activity == "Ждёт вашей команды", "под управлением сам работу не ищет: %s" % w.activity)
		# чертежи: дальний — по команде
		var fid := 1
		for fk in Defs.floor_by_id.keys():
			if int(fk) > 0:
				fid = int(fk)
				break
		g.place_floor_bp(cells[0], fid)
		g.place_floor_bp(cells[1], fid)
		var far := cells[1] if w.cell().distance_to(cells[1]) > w.cell().distance_to(cells[0]) else cells[0]
		var opts := g.brain.order_options(w, far)
		var keys := opts.map(func(o: Dictionary) -> String: return str(o["key"]))
		check(keys.has("bp") and keys.has("go"), "меню у чертежа: %s" % str(keys))
		var txt := g.brain.give_order(w, far, "bp")
		check(not w.order.is_empty() and int(w.order["bp"]) == g.world.idx(far), "команда «Строить сейчас»: %s" % txt)
		var fi := g.world.idx(far)
		run(g, 240.0, func() -> bool: return not g.bp_cells.has(fi))
		check(not g.bp_cells.has(fi) and g.world.flr[fi] == fid, "дальний чертёж построен по команде")
		run(g, 10.0)
		check(w.order.is_empty() and w.controlled, "сделал — ждёт следующей команды (%s)" % w.activity)
		# груз на полу — отнести
		var it := g.new_item("part", "pin", "ok")
		g.put_on_ground(it, cells[2])
		var opts2 := g.brain.order_options(w, cells[2])
		var has_item := false
		for o2: Dictionary in opts2:
			if str(o2["key"]).begins_with("item:"):
				has_item = true
				g.brain.give_order(w, cells[2], str(o2["key"]))
		check(has_item, "меню у груза: «Отнести сейчас»")
		run(g, 120.0, func() -> bool: return it.loc != Item.Loc.GROUND)
		check(it.loc != Item.Loc.GROUND, "груз унесён по команде (лежит: %d)" % it.loc)
		# идти
		g.brain.give_order(w, cells[0], "go")
		run(g, 60.0, func() -> bool: return w.cell() == cells[0])
		check(w.cell().distance_to(cells[0]) <= 1.5, "пошёл, куда велели")
		# сохранение
		var d: Dictionary = JSON.parse_string(JSON.stringify(g.to_dict()))
		var g2 := Sim.from_dict(d)
		check(g2.brain.controlled_worker() != null and g2.brain.controlled_worker().id == w.id, "управление сохраняется")
		g2.dispose()
		g.brain.release_control(w)
		check(not w.controlled and g.brain.controlled_worker() == null, "отпустили — снова работает сам")
		# второй под управление — первый отпускается
		var others := g.workers.filter(func(x3: Worker) -> bool: return x3 != w and x3.present and not x3.is_itr())
		if not others.is_empty():
			g.brain.take_control(w)
			g.brain.take_control(others[0])
			check(not w.controlled and (others[0] as Worker).controlled, "под управлением всегда один")
			g.brain.release_control(others[0])
	g.dispose()

	print("— старое сохранение: Сайдвей был токарным")
	var g3 := Scenario.new_game("sandbox", "mech", "calm", 192)
	g3.story.enabled = false
	var sd: Thing = g3.place_thing("cnc_sidway", Vector2i(int(g3.world.plot.get_center().x), int(g3.world.plot.get_center().y)), true, false)
	check(sd != null, "Сайдвей поставлен")
	if sd:
		sd.product = "pin"
		sd.progress = 0.4
		var bar := g3.new_item("mat", "bar45", "ok")
		g3.put_in_thing(bar, sd, 0)
		var d3: Dictionary = JSON.parse_string(JSON.stringify(g3.to_dict()))
		d3["version"] = 10
		var g4 := Sim.from_dict(d3)
		var sd2: Thing = g4.things.get(sd.id)
		check(sd2 != null and sd2.product == "" and sd2.progress == 0.0, "токарная работа снята с фрезерного Сайдвея")
		check(g4.count_slot(sd2, 0) == 0, "заготовки сложены рядом")
		g4.dispose()
	g3.dispose()

	print("")
	if fails.is_empty():
		print("РЕЗУЛЬТАТ: OK")
	else:
		print("РЕЗУЛЬТАТ: ОШИБКИ: " + ", ".join(fails))
	quit(0 if fails.is_empty() else 1)
