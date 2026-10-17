extends SceneTree
## Тест этапа 3: многооперационные маршруты, печь партиями, сварка, сборка узлов, расходники, поломки.
## godot --headless --path . -s res://tests/stage3_test.gd -- [дней]

var fails: Array[String] = []


func check(cond: bool, what: String) -> void:
	print(("  ✓ " if cond else "  ✗ ") + what)
	if not cond:
		fails.append(what)


func hire(sim: Sim, prof: String, skill_key: String, lvl: int) -> Worker:
	var w := People.make(sim.rng, prof)
	w.skills[skill_key] = lvl
	w.traits = []
	sim.add_worker(w)
	return w


func _init() -> void:
	var days := 16
	var a := OS.get_cmdline_user_args()
	if a.size() > 0:
		days = int(a[0])
	var sim := Scenario.new_garage(4242)
	sim.sales.enabled = false   # проверяем только свои сложные заказы
	sim.story.enabled = false   # тест механик производства: без случайных событий
	sim.auto_supply = true
	sim.money = 5000000.0
	var notes := {}
	sim.notified.connect(func(t: String, _l: int, _c: Vector2i) -> void:
		var k := t.substr(0, 40)
		if not notes.has(k):
			notes[k] = true
			print("    [%s %s] %s" % [sim.date_str(), sim.time_str(), t]))
	# большой цех справа от гаража: бетонный пол и стены, дверь в гараж, ворота наружу
	var w := sim.world
	var shop := Rect2i(29, 3, 17, 17)
	for y in range(shop.position.y, shop.end.y):
		for x in range(shop.position.x, shop.end.x):
			var c := Vector2i(x, y)
			var i := w.idx(c)
			w.flr[i] = 1
			var edge := x == shop.position.x or x == shop.end.x - 1 or y == shop.position.y or y == shop.end.y - 1
			if edge and w.wall[i] == World.W_NONE:
				w.wall[i] = World.W_BRICK
	w.wall[w.idx(Vector2i(29, 14))] = World.W_DOOR
	w.wall[w.idx(Vector2i(29, 15))] = World.W_DOOR
	for x in [36, 37, 38]:
		w.wall[w.idx(Vector2i(x, 19))] = World.W_GATE
	w.refresh_all()
	sim.place_thing("mill", Vector2i(31, 5), true, false)
	sim.place_thing("drill", Vector2i(35, 5), true, false)
	sim.place_thing("lathe", Vector2i(38, 5), true, false)
	sim.place_thing("weld_post", Vector2i(31, 9), true, false)
	sim.place_thing("assembly_table", Vector2i(35, 9), true, false)
	sim.place_thing("furnace", Vector2i(31, 13), true, false)
	sim.place_thing("paint_booth", Vector2i(35, 13), true, false)
	sim.place_thing("wip_rack", Vector2i(42, 5), true, false)
	sim.place_thing("wip_rack", Vector2i(42, 7), true, false)
	sim.place_thing("rack", Vector2i(42, 9), true, false)
	sim.place_thing("rack", Vector2i(42, 11), true, false)
	sim.place_thing("pallet", Vector2i(42, 13), true, false)
	sim.place_thing("pallet", Vector2i(43, 13), true, false)
	sim.place_thing("pallet", Vector2i(44, 13), true, false)
	sim.place_thing("qc_table", Vector2i(39, 9), true, false)
	sim.place_thing("crane", Vector2i(44, 4), true, false)
	sim.place_thing("cart", Vector2i(40, 17), true, false)
	sim.place_thing("toilet", Vector2i(44, 17), true, false)
	sim.place_thing("extinguisher", Vector2i(30, 4), true, false)   # пожарный надзор не остановит цех (ход проверок зависит от случая)
	var ktp := sim.place_thing("ktp", Vector2i(40, 21), true, false)
	sim.power.grid_level = 2
	Scenario.autowire(sim)
	Scenario._route(sim, ktp.cells())
	sim.world.cable_rev += 1
	sim.rooms.update()
	var sr := sim.rooms.room_at(Vector2i(37, 10))
	if sr:
		sim.rooms.assign(sr, "workshop")
	sim.rooms.paint(Rect2i(43, 16, 2, 3), "wc")   # 1.13: зоны обязательны
	sim.rooms.legacy[ktp.id] = true                # подстанция на улице, как в старых сохранениях
	hire(sim, "turner", "turning", 6)
	hire(sim, "miller", "milling", 6)
	hire(sim, "welder", "welding", 6)
	hire(sim, "heat_treater", "heat", 5)
	hire(sim, "painter", "paint", 5)
	hire(sim, "assembler", "assembly", 6)
	hire(sim, "laborer", "haul", 7)
	hire(sim, "laborer", "haul", 6)
	hire(sim, "qc", "qc", 6)
	for k in sim.cons.keys():
		sim.cons[k] = 80.0
	sim.power.tick(0.1)
	var unpowered := 0
	for m in sim.things_of("machine"):
		if not sim.power.powered(m):
			unpowered += 1
			print("    без питания: ", m.title())
	check(unpowered == 0, "все станки под напряжением")
	# заказы на сложные изделия
	var want := {"bracket": 10, "housing": 4, "frame": 3, "spline_shaft": 4, "drive_unit": 2}
	for p in want.keys():
		var o := sim.orders.make_offer(p)
		o["qty"] = want[p]
		o["lead"] = days
		o["status"] = "offer"
		sim.orders.list.append(o)
		sim.orders.accept(int(o["id"]), true)
	var batches := 0
	var max_wip := 0
	while sim.day() <= days:
		sim.tick(0.5)
		if int(sim.minute) % 60 == 0:
			var nw := 0
			for it: Item in sim.items.values():
				if it.q == "wip":
					nw += 1
			max_wip = maxi(max_wip, nw)
	for m in sim.things_of("machine"):
		print("    %s: сделано %d, состояние %d%%, сломан %s, задание '%s'/%d" % [m.title(), m.parts_made, int(m.condition), m.broken, m.product, m.job_step])
	check(max_wip > 0, "детали проходили через НЗП (максимум %d)" % max_wip)
	for o: Dictionary in sim.orders.list:
		if want.has(str(o["product"])):
			print("    заказ %s: %s, отгружено %d/%d, на складе годных %d" % [sim.orders.short(o), o["status"], int(o["shipped"]), int(o["qty"]), sim.ok_in_storage(str(o["product"]))])
	for p in want.keys():
		var done := false
		for o: Dictionary in sim.orders.list:
			if str(o["product"]) == p and str(o["status"]) in ["done", "ready", "shipping"]:
				done = true
		check(done, "заказ на «%s» выполнен" % Defs.product_name(p))
	for v in sim.vehicles:
		print("    машина %s: %s, нужно %d, погружено %d, резерв %d, заказ %d" % [v.kind, v.state, v.need, v.loaded, v.reserved_load, v.order_id])
	for it: Item in sim.items.values():
		if it.def_id == "drive_unit":
			print("    узел: q=%s loc=%d holder=%d reserved=%d cell=%s" % [it.q, it.loc, it.holder, it.reserved_by, it.cell])
	for wk in sim.workers:
		print("    ", wk.first, " ", wk.prof, ": ", wk.activity)
	print("  расходники: ", sim.cons)
	print("  деньги: ", Defs.money_str(sim.money))
	var d := sim.to_dict()
	var s2 := Sim.from_dict(JSON.parse_string(JSON.stringify(d)))
	check(s2.things_of("machine").size() == sim.things_of("machine").size(), "сохранение и загрузка")
	sim.dispose()
	s2.dispose()
	print("РЕЗУЛЬТАТ: ", "OK" if fails.is_empty() else "ПРОВАЛ: " + "; ".join(fails))
	quit(0 if fails.is_empty() else 1)
