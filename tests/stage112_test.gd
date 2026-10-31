extends SceneTree
## Тест версии 1.12 «Зоны и меню»: зоны рисуются клетками и сливаются, в одном зале — несколько зон
## с общими теплом, светом, шумом и пожарной безопасностью; зона отгрузки; новые стены, двери и полы;
## перевод сохранений.
## godot --headless --path . -s res://tests/stage112_test.gd

const S := preload("res://tests/setups.gd")

var fails: Array[String] = []


func check(cond: bool, what: String) -> void:
	print(("  ✓ " if cond else "  ✗ ") + what)
	if not cond:
		fails.append(what)


func _types(sim: Sim, rect: Rect2i) -> Array[String]:
	var out: Array[String] = []
	for r in sim.rooms.list:
		if rect.has_point(r.cells[0]):
			out.append(r.type)
	return out


func _init() -> void:
	Defs.load_all()
	Director.skip_office = true   # зал теста стоит на месте конторы директора
	var sim := Scenario.new_game("garage", "mech", "calm", 112)
	Director.skip_office = false
	sim.story.enabled = false
	sim.money = 5000000.0
	sim.progress.all_open = true

	print("— зоны рисуются клетками")
	var hall := Rect2i(30, 3, 14, 10)        # стены по контуру, внутри 12×8
	S._box(sim, hall, 1, Vector2i(30, 7))
	sim.world.refresh_all()
	sim.rooms.update()
	var inner := Rect2i(31, 4, 12, 8)
	check(sim.rooms.space_id_at(Vector2i(35, 6)) >= 0, "зал — помещение-постройка")
	var n := sim.rooms.fill(Vector2i(35, 6), "workshop")
	check(n == 96, "щелчок заливает весь зал: %d кл." % n)
	check(sim.rooms.room_at(Vector2i(32, 5)).type == "workshop" and sim.rooms.room_at(Vector2i(42, 11)).type == "workshop", "весь зал — цех")
	var n2 := sim.rooms.paint(Rect2i(39, 4, 4, 8), "storage")
	check(n2 == 32, "прямоугольник 4×8 — склад: %d кл." % n2)
	var ws := sim.rooms.room_at(Vector2i(32, 5))
	var st := sim.rooms.room_at(Vector2i(41, 6))
	check(ws.type == "workshop" and st.type == "storage" and ws.id != st.id, "в одном зале две зоны: цех и склад")
	check(ws.space == st.space and sim.rooms.space_rooms(ws.space).size() == 2, "у обеих зон один зал")
	check(ws.area() == 64 and st.area() == 32, "площадь зон: %d и %d кл." % [ws.area(), st.area()])
	sim.rooms.paint(Rect2i(37, 4, 2, 8), "storage")
	check(sim.rooms.room_at(Vector2i(37, 6)).id == sim.rooms.room_at(Vector2i(41, 6)).id and sim.rooms.room_at(Vector2i(41, 6)).area() == 48, "соседние клетки одной зоны сливаются (48 кл.)")
	sim.rooms.paint(Rect2i(31, 10, 2, 2), "storage")
	var far := sim.rooms.room_at(Vector2i(31, 10))
	check(far.type == "storage" and far.id != sim.rooms.room_at(Vector2i(41, 6)).id, "несвязанные клетки — отдельная зона того же назначения")
	sim.rooms.paint(Rect2i(31, 10, 2, 2), "")
	check(sim.rooms.room_at(Vector2i(31, 10)).type == "", "стёртая разметка — неразмеченная часть зала")
	sim.rooms.paint(Rect2i(31, 10, 2, 2), "workshop")
	check(sim.rooms.paint(Rect2i(20, 25, 3, 3), "workshop") == 0, "на улице без пола зону не нарисовать")
	check(sim.rooms.paint(Rect2i(30, 3, 1, 3), "workshop") == 0, "на стене — тоже")
	# пол без стен: разметка остаётся, но с предупреждением
	for y in range(24, 27):
		for x in range(38, 42):
			sim.world.flr[sim.world.idx(Vector2i(x, y))] = 1
	sim.world.refresh_all()
	sim.rooms.update()
	sim.rooms.paint(Rect2i(38, 24, 4, 3), "storage")
	check(sim.rooms.open_zones.size() == 1 and str(sim.rooms.open_zones[0]["type"]) == "storage", "зона на полу без стен — в списке предупреждений")

	print("— зал общий: тепло, шум, свет, огнетушитель")
	sim.season.update_rooms()
	check(absf(float(sim.season.room_temp[ws.id]) - float(sim.season.room_temp[sim.rooms.room_at(Vector2i(41, 6)).id])) < 0.01, "у зон одного зала одна температура")
	var m := sim.place_thing("mill", Vector2i(32, 5), true, false)
	m.working = true
	var near_other := sim.season.noise_at(Vector2i(39, 6))
	check(near_other > 60.0, "шум станка из цеха слышен в складской зоне того же зала (%.0f дБ)" % near_other)
	sim.rooms.update()
	var viol: Array = sim.inspect.violations("fire")
	var no_ext := viol.filter(func(v: Dictionary) -> bool: return str(v["key"]) == "no_ext")
	var halls_without := 0
	for sp in sim.rooms.spaces:
		var r0 := sim.rooms.space_main(sp.id)
		if r0 and r0.type in ["wc", "shower"]:
			continue   # 1.15: туалету и душевой огнетушитель не нужен
		if sp.cells.size() >= 6 and r0 and sim.rooms.space_count(sp.id, "extinguisher") == 0:
			halls_without += 1
	check(no_ext.size() == halls_without, "без огнетушителя — замечание на зал, а не на каждую зону (%d)" % no_ext.size())
	sim.place_thing("extinguisher", Vector2i(36, 11), true, false)
	sim.rooms.update()
	var viol2: Array = sim.inspect.violations("fire")
	var hall_bad := viol2.filter(func(v: Dictionary) -> bool: return str(v["key"]) == "no_ext" and int(v.get("room", -1)) in [ws.id, sim.rooms.room_at(Vector2i(41, 6)).id])
	check(hall_bad.is_empty(), "один огнетушитель в зале — хватает всем его зонам")
	var crane := sim.place_thing("crane", Vector2i(40, 6), true, false)
	sim.rooms.update()
	check(crane != null and sim.prod.crane_in(sim.rooms.room_at(Vector2i(32, 5))) == crane, "кран-балка из складской части зала обслуживает и цех")

	print("— зона отгрузки")
	var g := Scenario.new_game("garage", "mech", "calm", 113)
	g.story.enabled = false
	var gy := g.world.plot.end.y - 3
	var ship0 := g.logi.ship_cells().size()   # 1.29: зона отгрузки уже есть с начала игры
	var nz := g.set_area(Rect2i(g.gate_x - 2, gy, 4, 2), Logistics.A_SHIP)
	check(nz >= 6 and g.logi.has_ship(), "отмечена зона отгрузки: %d кл." % nz)
	check(g.logi.ship_cells().size() == nz + ship0, "клетки отгрузки в отдельном слое")
	check(not g.logi.in_zone(g.logi.ship_cells()[0]), "это не зона разгрузки")
	# готовый заказ: детали на складе
	var o := g.orders.make_offer("pin")
	o["qty"] = 4
	g.orders.list.append(o)
	g.orders.accept(int(o["id"]), false)
	var rack: Thing = null
	for t: Thing in g.things.values():
		if t.is_storage() and t.built:
			rack = t
			break
	for i in 4:
		var it := g.new_item("part", "pin", "ok")
		g.put_on_ground(it, Vector2i(24, 15))
	g.orders._t = 0.0
	g.orders.tick(1.0)
	check(str(o["status"]) == "ready", "заказ готов, клиент выслал машину")
	o["pickup_eta"] = g.minute + 10000.0   # машина задерживается — есть время вынести детали
	var w0: Worker = g.workers[0]
	var cands: Array = []
	g.logi.add_ship_jobs(g.brain, w0, cands, 0.0)
	check(not cands.is_empty() and str(cands[0]["k"]) == "haul_cell" and g.logi.in_ship(cands[0]["cell"]), "есть работа: отнести деталь в зону отгрузки")
	var guard := 0
	while g.logi.staged("pin") < 4 and guard < 4000:
		g.tick(1.0)
		guard += 1
	check(g.logi.staged("pin") >= 4, "все 4 детали ждут машину в зоне отгрузки (%d за %d мин.)" % [g.logi.staged("pin"), guard])
	for k in 200:
		g.tick(1.0)
	check(g.logi.staged("pin") >= 4, "детали не уносят обратно на склад, пока заказ не уехал")
	o["pickup_eta"] = g.minute
	guard = 0
	while str(o["status"]) != "done" and guard < 6000:
		g.tick(1.0)
		guard += 1
	check(str(o["status"]) == "done" and g.logi.staged_for(o) == 0, "машина забрала заказ из зоны отгрузки")   # 1.56: у другого заказа на штифты свой поддон

	print("— новые стены, двери, полы")
	for k in ["concrete_wall", "sandwich", "partition", "metal_door"]:
		check(Defs.walls.has(k) and bool(Defs.walls[k].get("buildable", false)), "можно строить: %s" % str(Defs.walls.get(k, {}).get("name", k)))
	for k2 in ["epoxy", "tile_blue", "parquet"]:
		check(Defs.floors.has(k2) and ResourceLoader.exists("res://assets/tiles/%s.svg" % k2), "новый пол: %s" % str(Defs.floors.get(k2, {}).get("name", k2)))
	var h := Scenario.new_game("garage", "mech", "calm", 114)
	h.story.enabled = false
	var box := Rect2i(31, 4, 6, 5)
	for y in range(box.position.y, box.end.y):
		for x in range(box.position.x, box.end.x):
			var c := Vector2i(x, y)
			var i := h.world.idx(c)
			h.world.flr[i] = 6
			var edge := x == box.position.x or x == box.end.x - 1 or y == box.position.y or y == box.end.y - 1
			if edge:
				h.world.wall[i] = World.W_SANDWICH if y == box.position.y else World.W_PARTITION
	h.world.wall[h.world.idx(Vector2i(33, 8))] = World.W_METAL_DOOR
	h.world.refresh_all()
	h.rooms.update()
	var hr := h.rooms.room_at(Vector2i(33, 6))
	check(hr != null and hr.doors == 1, "сэндвич-панели, перегородки и стальная дверь — тоже помещение (дверей: %d)" % (hr.doors if hr else -1))
	check(h.world.passable(Vector2i(33, 8)) and h.world.is_door(Vector2i(33, 8)), "через стальную дверь проходят")
	check(not h.world.passable(Vector2i(31, 6)), "сквозь перегородку — нет")
	h.place_thing("office_desk", Vector2i(32, 5), true, false)
	h.place_thing("safe", Vector2i(35, 5), true, false)
	h.rooms.update()
	h.rooms.assign(h.rooms.room_at(Vector2i(33, 6)), "accounting")
	check(h.rooms.room_at(Vector2i(33, 6)).valid, "бухгалтерия на паркете — пол подходит")
	var c0 := Vector2i(34, 7)
	h.world.flr[h.world.idx(c0)] = 1
	h.upkeep.add_dirt(c0, 30.0)
	var d1 := h.upkeep.dirt_at(c0)
	var c1 := Vector2i(35, 7)
	h.world.flr[h.world.idx(c1)] = 4
	h.upkeep.add_dirt(c1, 30.0)
	var d2 := h.upkeep.dirt_at(c1)
	check(d2 < d1, "на наливном полу грязи меньше (%d против %d)" % [d2, d1])

	print("— сохранение")
	var dd: Dictionary = JSON.parse_string(JSON.stringify(sim.to_dict()))
	var s2 := Sim.from_dict(dd)
	s2.rooms.update()
	check(s2.rooms.room_at(Vector2i(41, 6)).type == "storage" and s2.rooms.room_at(Vector2i(32, 5)).type == "workshop", "разметка зон сохраняется")
	var gd: Dictionary = JSON.parse_string(JSON.stringify(g.to_dict()))
	var g2 := Sim.from_dict(gd)
	check(g2.logi.ship_cells().size() == nz + ship0, "зона отгрузки сохраняется")

	print("РЕЗУЛЬТАТ: " + ("OK" if fails.is_empty() else "ОШИБКИ: " + ", ".join(fails)))
	quit(0 if fails.is_empty() else 1)
