extends SceneTree
## Тест этапа 2: помещения, электросеть, настроение, смены.
## godot --headless --path . -s res://tests/stage2_test.gd

var fails: Array[String] = []


func check(cond: bool, what: String) -> void:
	print(("  ✓ " if cond else "  ✗ ") + what)
	if not cond:
		fails.append(what)


func room_box(sim: Sim, r: Rect2i, floor_id: int, door: Vector2i) -> void:
	var w := sim.world
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			var c := Vector2i(x, y)
			var i := w.idx(c)
			w.flr[i] = floor_id
			var edge := x == r.position.x or x == r.end.x - 1 or y == r.position.y or y == r.end.y - 1
			if edge and w.wall[i] == World.W_NONE:
				w.wall[i] = World.W_BRICK
	w.wall[w.idx(door)] = World.W_DOOR
	w.refresh_all()


func run_until(sim: Sim, minute: float) -> void:
	while sim.minute < minute:
		sim.tick(0.5)
		accept_some(sim)


## Как игрок: по утрам берём заказ, если в работе меньше двух.
func accept_some(sim: Sim) -> void:
	if int(sim.minute) % 1440 != 420 or sim.orders.active_count() >= 2:
		return
	for o: Dictionary in sim.orders.list:
		if str(o["status"]) == "offer":
			sim.orders.accept(int(o["id"]), true)
			return


func _init() -> void:
	var sim := Scenario.new_garage(777)
	sim.auto_supply = true
	sim.notified.connect(func(t: String, _l: int, _c: Vector2i) -> void: print("    [%s %s] %s" % [sim.date_str(), sim.time_str(), t]))
	sim.rooms.update()
	var garage := sim.rooms.room_at(Vector2i(20, 12))
	check(garage != null, "гараж распознан как помещение")
	check(garage != null and garage.type == "workshop" and garage.valid, "гараж — цех, требования выполнены")
	sim.power.tick(0.1)
	var lathe: Thing = null
	for t: Thing in sim.things.values():
		if t.def_id == "lathe":
			lathe = t
	check(sim.power.powered(lathe), "станок под напряжением")
	# пристройка справа: бытовка, столовая, туалет (стена гаража x=29 общая)
	room_box(sim, Rect2i(29, 8, 6, 5), 3, Vector2i(29, 10))     # бытовка 4×3 внутри
	room_box(sim, Rect2i(29, 12, 6, 5), 3, Vector2i(29, 14))    # столовая
	room_box(sim, Rect2i(34, 8, 4, 4), 2, Vector2i(34, 9))      # туалет (дверь из бытовки)
	for c in [Vector2i(30, 9), Vector2i(31, 9), Vector2i(32, 9)]:
		sim.place_thing("locker", c, true, false)
	sim.place_thing("bench", Vector2i(31, 11), true, false)
	sim.place_thing("dining_table", Vector2i(31, 14), true, false)
	sim.place_thing("chair", Vector2i(31, 13), true, false)
	sim.place_thing("chair", Vector2i(32, 13), true, false)
	sim.place_thing("chair", Vector2i(31, 15), true, false)
	sim.place_thing("fridge", Vector2i(33, 13), true, false)
	sim.place_thing("toilet", Vector2i(35, 9), true, false)
	sim.place_thing("sink", Vector2i(36, 9), true, false)
	# вода: свой ввод водопровода у туалета, труба под стеной и раковиной
	sim.place_thing("water_inlet", Vector2i(38, 9), true, false)
	for pc in [Vector2i(38, 9), Vector2i(37, 9), Vector2i(36, 9), Vector2i(35, 9)]:   # 1.18: труба заходит в клетку прибора
		sim.world.pipe[sim.world.idx(pc)] = 1
	sim.world.pipe_rev += 1
	# свет: лампы под потолком новых помещений
	for lc in [Vector2i(31, 10), Vector2i(30, 14), Vector2i(35, 10)]:
		sim.place_thing("lamp_bulb", lc, true, false)
	sim.rooms.update()
	var lr := sim.rooms.room_at(Vector2i(31, 10))
	var cr := sim.rooms.room_at(Vector2i(31, 15))
	var wr := sim.rooms.room_at(Vector2i(35, 10))
	check(lr != null and cr != null and wr != null, "новые помещения распознаны")
	if lr:
		sim.rooms.assign(lr, "locker")
	if cr:
		sim.rooms.assign(cr, "canteen")
	if wr:
		sim.rooms.assign(wr, "wc")
	lr = sim.rooms.room_at(Vector2i(31, 10))
	cr = sim.rooms.room_at(Vector2i(31, 15))
	wr = sim.rooms.room_at(Vector2i(35, 10))
	check(lr.valid, "бытовка оборудована: " + ", ".join(lr.missing))
	check(cr.valid, "столовая оборудована: " + ", ".join(cr.missing))
	check(wr.valid, "туалет оборудован: " + ", ".join(wr.missing))
	# свет в пристройке: кабель от сети гаража до каждой лампы
	for lc2 in [Vector2i(31, 10), Vector2i(30, 14), Vector2i(35, 10)]:
		Scenario._route_layer(sim, "cable", [lc2])
	sim.world.cable_rev += 1
	run_until(sim, 9.5 * 60.0)
	check(sim.rooms.room_at(Vector2i(31, 10)).powered, "бытовка под напряжением")
	var olga: Worker = null
	var denis: Worker = null
	var viktor: Worker = null
	for wk in sim.workers:
		match wk.first:
			"Ольга":
				olga = wk
			"Денис":
				denis = wk
			"Виктор":
				viktor = wk
	check(viktor.dressed and viktor.locker_id >= 0, "Виктор переоделся у шкафчика")
	var has_locker_thought := viktor.thoughts.any(func(t: Dictionary) -> bool: return t["id"] == "changed_locker")
	check(has_locker_thought, "мысль «переоделся в бытовке»")
	run_until(sim, 13.6 * 60.0)
	var ate := olga.thoughts.any(func(t: Dictionary) -> bool: return str(t["id"]).begins_with("ate_"))
	check(ate, "Ольга пообедала, есть мысль про обед: " + str(olga.thoughts.map(func(t: Dictionary) -> String: return t["id"])))
	var canteen := olga.thoughts.any(func(t: Dictionary) -> bool: return t["id"] == "ate_canteen")
	check(canteen, "обед в столовой")
	print("  настроение: Виктор %d, Ольга %d, Денис %d" % [int(viktor.mood), int(olga.mood), int(denis.mood)])
	# второй станок → перегрузка ввода 15 кВт: вместо подстанции — старый малый трансформатор (как в сохранениях до 1.18)
	var sub: Thing = sim.things.get(sim.power.grid_input_id())
	var cab_cell := sub.cell
	for sc: Vector2i in sub.cells():
		if sim.world.cable[sim.world.idx(sc)] == 1:
			cab_cell = sc
	sim.remove_thing(sub, 0.0)
	sim.place_thing("cabinet", cab_cell, true, false)
	var l2 := sim.place_thing("lathe", Vector2i(23, 17), true, false)
	sim.place_cable(Vector2i(23, 16), true)
	sim.place_cable(Vector2i(24, 16), true)
	sim.place_cable(Vector2i(25, 16), true)
	sim.place_cable(l2.inlet_cell(), true)   # 1.18: кабель заводят прямо в розетку станка
	for y in range(10, 17):
		sim.place_cable(Vector2i(23, y), true)
	var t2 := People.make(sim.rng, "turner")
	t2.skills["turning"] = 6
	sim.add_worker(t2)
	t2.shift_anchor = -1.0
	var tripped := false
	var reset := false
	var until := sim.minute + 1.0 * 1440.0
	while sim.minute < until:
		sim.tick(0.5)
		if sim.power.any_tripped():
			tripped = true
		elif tripped:
			reset = true
	check(tripped, "два станка перегрузили сеть 15 кВт — автомат выбило")
	check(reset, "автомат сбросили")
	l2.enabled = false
	# 1.15: договоров с сетевой компанией нет — ставим второй трансформатор рядом с кабелем
	var cab0: Thing = sim.things.get(sim.power.grid_input_id())
	var tr2: Thing = null
	for r in range(1, 6):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var c := cab0.cell + Vector2i(dx, dy)
				if tr2 == null and sim.can_place("cabinet", c) == "":
					var near_cable := false
					for d4 in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
						if sim.world.inb(c + d4) and sim.world.cable[sim.world.idx(c + d4)] != 0:
							near_cable = true
					if near_cable:
						tr2 = sim.place_thing("cabinet", c, true, false)
	check(tr2 != null, "второй трансформатор поставлен у кабеля")
	sim.money -= 45000.0
	var trips_off := 0
	sim.tick(0.5)
	var was := sim.power.any_tripped()
	var until2 := sim.minute + 6.0 * 1440.0
	while sim.minute < until2:
		sim.tick(0.5)
		var tr := sim.power.any_tripped()
		if tr and not was:
			trips_off += 1
		was = tr
		accept_some(sim)
		if int(sim.minute) % 1440 == 600 and sim.is_workday():
			for o: Dictionary in sim.orders.list:
				if str(o["status"]) in ["active", "ready", "shipping"]:
					print("   заказ ", sim.orders.short(o), " ", o["status"], " ok=", sim.ok_in_storage(str(o["product"])), " металл=", sim.free_material(sim.planner.material_of(str(o["product"]))), "/", sim.material_total(sim.planner.material_of(str(o["product"]))))
			for m in sim.things_of("machine"):
				print("   станок ", m.id, " '", m.product, "' on=", m.enabled, " pow=", sim.power.powered(m), " лоток=", sim.count_slot(m, 0), " выход=", sim.count_slot(m, 1), " user=", m.user)
			for wk in sim.workers:
				print("   ", wk.first, ": ", wk.activity, " dressed=", wk.dressed, " mood=", int(wk.mood))
	check(trips_off == 0, "с выключенным вторым станком сеть не выбивает (%d)" % trips_off)
	check(sim.power.total_kw() >= 30.0, "мощность увеличена до %d кВт" % int(sim.power.total_kw()))
	l2.enabled = true
	var done_before := int(sim.stats["orders_done"])
	# вторая смена
	sim.set_shift(denis, 1)
	var start := sim.minute
	var seen_evening := false
	while sim.minute < start + 3.0 * 1440.0:
		sim.tick(0.5)
		accept_some(sim)
		var t := sim.tod()
		if denis.present and (t >= 18.0 * 60.0 or t < 60.0):
			seen_evening = true
	check(denis.shift == 1, "Денис во второй смене")
	if not seen_evening:
		print("    Денис: ", denis.activity, " sick=", denis.sick_until, " away=", denis.away_why, " skip=", denis.skip_shift, " день ", sim.day(), " ", sim.weekday_name(), " старт дня ", int(start / 1440.0) + 1)
	check(seen_evening or denis.sick_until > start, "Денис работает вечером (или ушёл на больничный — тогда смену не проверить)")
	check(int(sim.stats["orders_done"]) > 0, "заказы выполняются (%d)" % int(sim.stats["orders_done"]))
	# сохранение
	var d := sim.to_dict()
	var s2 := Sim.from_dict(JSON.parse_string(JSON.stringify(d)))
	check(s2.workers.size() == sim.workers.size() and s2.power.grid_level == sim.power.grid_level, "сохранение и загрузка")
	for wk in sim.workers:
		print("  %s: настроение %d (%s), черты: %s" % [wk.first, int(wk.mood), Mood.label(wk.mood), ", ".join(wk.trait_names())])
		for p in Mood.breakdown(sim, wk):
			print("      %+d %s" % [int(p[1]), p[0]])
	print("Заказов выполнено: %d, деньги %s" % [int(sim.stats["orders_done"]), Defs.money_str(sim.money)])
	sim.dispose()
	s2.dispose()
	print("РЕЗУЛЬТАТ: ", "OK" if fails.is_empty() else "ПРОВАЛ: " + "; ".join(fails))
	quit(0 if fails.is_empty() else 1)
