extends SceneTree
## Тест версии 1.13 «Сети и стройка»: сети прокладывают рабочие, стены и полы строят из
## привезённых материалов, деревья мешают и их спиливают, соседние участки покупают.
## godot --headless --path . -s res://tests/stage113_test.gd

const S := preload("res://tests/setups.gd")

var fails: Array[String] = []


func check(cond: bool, what: String) -> void:
	print(("  ✓ " if cond else "  ✗ ") + what)
	if not cond:
		fails.append(what)


func run(sim: Sim, minutes: float, until: Callable = Callable()) -> float:
	var t := 0.0
	while t < minutes:
		sim.tick(1.0)
		t += 1.0
		if until.is_valid() and bool(until.call()):
			break
	return t


func _init() -> void:
	Defs.load_all()

	print("— сети прокладывают рабочие")
	var g := Scenario.new_game("garage", "mech", "calm", 131)
	g.story.enabled = false
	g.money = 2000000.0
	g.build_priority = true
	var m0 := g.money
	var line: Array[Vector2i] = []
	for x in range(30, 38):
		line.append(Vector2i(x, 22))
	for c in line:
		g.place_cable(c)
	check(m0 - g.money > 0.0, "кабель оплачен сразу: %s" % Defs.money_str(m0 - g.money))
	check(g.world.net_at("cable", Vector2i(30, 22)) == 2 and not g.world.has_cable(Vector2i(30, 22)), "это чертёж, ток по нему не идёт")
	check(g.net_plan_count() == 8, "чертежей кабеля: %d" % g.net_plan_count())
	var seen := {"lay": false, "truck": false}
	var tl := run(g, 600.0, func() -> bool:
		for w in g.workers:
			if w.task and w.task.kind == "lay_net":
				seen["lay"] = true
		return g.net_plan_count() == 0)
	check(g.net_plan_count() == 0, "кабель проложили за %d мин." % int(tl))
	check(bool(seen["lay"]), "рабочий тянул кабель (задача «Тянет кабель»)")
	var laid := true
	for c in line:
		laid = laid and g.world.has_cable(c)
	check(laid, "все клетки проложены")
	g.place_pipe(Vector2i(31, 24))
	check(g.remove_pipe(Vector2i(31, 24)) and g.world.net_at("pipe", Vector2i(31, 24)) == 0, "чертёж трубы отменяется с возвратом")
	check(g.place_cable(Vector2i(40, 24), true) and g.world.has_cable(Vector2i(40, 24)), "сценарий и тесты кладут сеть сразу")

	print("— стройматериалы")
	var b := Scenario.new_game("garage", "mech", "calm", 132)
	b.story.enabled = false
	b.money = 2000000.0
	b.build_priority = true
	for x in range(32, 38):
		b.place_wall_bp(Vector2i(x, 3), World.W_BRICK)
	for x in range(32, 37):
		for y in range(4, 6):
			b.place_floor_bp(Vector2i(x, y), 2)
	var bp0 := b.bp_cells.size()
	var need := b.bmats.needed()
	check(int(need.get("bm_brick", 0)) == 6 and int(need.get("bm_tile", 0)) == 10, "нужно: кирпич ×%d, плитка ×%d" % [int(need.get("bm_brick", 0)), int(need.get("bm_tile", 0))])
	run(b, 30.0)
	check(not b.bmats.orders.is_empty(), "материал заказан у поставщика")
	var cm := b.bmats.coming()
	check(int(cm.get("bm_brick", 0)) == 6, "кирпич заказан ровно сколько нужно (1.15): %d" % int(cm.get("bm_brick", 0)))
	check(b.bp_cells.size() == bp0, "без материала не строят")
	var t2 := run(b, 2880.0, func() -> bool:
		for v in b.vehicles:
			if v.body == "flatbed":
				seen["truck"] = true
		return b.bp_cells.is_empty())
	check(bool(seen["truck"]), "приехал бортовой грузовик со стройматериалами")
	check(b.bp_cells.is_empty(), "всё построено за %d мин. (осталось %d)" % [int(t2), b.bp_cells.size()])
	var built_ok := b.world.wall[b.world.idx(Vector2i(34, 3))] == World.W_BRICK and b.world.flr[b.world.idx(Vector2i(34, 4))] == 2
	check(built_ok, "стена и плитка на месте")
	var left := int(b.bmats.have().get("bm_brick", 0)) + int(b.bmats.have().get("bm_tile", 0))
	check(left <= BuildMats.pallet("bm_brick") + BuildMats.pallet("bm_tile"), "материал израсходован (остаток %d — до поддона)" % left)
	var has_ground := false
	for gid in b.ground_items:
		var it: Item = b.items.get(gid)
		if it and it.kind == "bmat":
			has_ground = true
	print("    остаток на земле: ", has_ground)

	print("— деревья")
	var f := Scenario.new_game("garage", "mech", "calm", 133, {"flora": true, "lots": true})
	f.story.enabled = false
	f.money = 2000000.0
	f.build_priority = true
	var trees := 0
	var inside := 0
	for i in f.world.w * f.world.h:
		if f.world.flora[i] != 0:
			trees += 1
			if f.world.in_plot(f.world.cell_of(i)):
				inside += 1
	check(trees > 40, "на карте деревья и кусты: %d (на своём участке %d)" % [trees, inside])
	var org := f.things_of("machine")[0].cell - Vector2i(16, 9)   # где теперь левый верхний угол прежней карты
	var tc := Vector2i(40, 22) + org
	f.world.flora[f.world.idx(tc)] = 1
	f.world.flora_rev += 1
	f.world.refresh_cell(tc)
	check(not f.world.passable(tc), "сквозь дерево не пройти")
	check(f.can_place("workbench", tc) != "", "на дереве объект не поставить: «%s»" % f.can_place("workbench", tc))
	check(f.place_demolish(tc), "дерево отмечено под спил")
	var t3 := run(f, 600.0, func() -> bool: return f.world.flora[f.world.idx(tc)] == 0)
	check(f.world.flora[f.world.idx(tc)] == 0 and f.world.passable(tc), "дерево спилили за %d мин." % int(t3))
	var tc2 := Vector2i(42, 22) + org
	f.world.flora[f.world.idx(tc2)] = 2
	f.world.refresh_cell(tc2)
	f.place_floor_bp(tc2, 1)
	check(f.bp_work_time(f.world.idx(tc2)) > 10.0, "пол на месте дерева — дольше: сначала спилить")

	print("— соседние участки")
	var l := Scenario.new_game("garage", "mech", "calm", 134, {"lots": true})
	l.story.enabled = false
	l.money = 5000000.0
	l.build_priority = true
	check(l.world.lots.size() == 3, "у гаража три соседних участка: справа, слева, сзади")
	var sides: Array[String] = []
	for k in 3:
		sides.append(l.world.lot_side(k))
	check(sides == ["справа", "слева", "сзади"], "стороны: %s" % str(sides))
	var r0 := l.world.lot_rect(0)
	check(r0.size.x >= 16 and l.world.lot_rect(2).size.x > 60, "участки широкие: справа %d×%d, сзади %d×%d" % [r0.size.x, r0.size.y, l.world.lot_rect(2).size.x, l.world.lot_rect(2).size.y])
	# гараж перенесён в середину карты целиком
	var lathe0: Thing = l.things_of("machine")[0]
	check(l.rooms.room_of_thing(lathe0) != null and l.rooms.room_of_thing(lathe0).type == "workshop", "гараж на новом месте — цех цел")
	check(l.world.in_plot(lathe0.cell) and not l.world.in_plot(r0.get_center()), "свой участок — только середина")
	check(l.dev.block_reason("land1") != "", "покупка: «%s»" % l.dev.block_reason("land1"))
	check(l.dev.cost_of("land1") == float(l.world.lots[0]["price"]), "цена ступени — цена земли: %s" % Defs.money_str(l.dev.cost_of("land1")))
	check(not l.dev.on("land1"), "участок не куплен")
	l.dev._finish("land1")
	check(l.dev.on("land1") and l.world.lot_bought(0), "сделка закрыта — участок наш")
	check(l.world.in_plot(r0.get_center()), "на купленной земле можно строить")
	var fence := Vector2i(r0.position.x - 1, r0.get_center().y)
	check(l.world.inner_fence(fence), "старый забор — внутри участка")
	check(l.place_demolish(fence), "старый забор можно снести")
	run(l, 1440.0, func() -> bool: return l.world.wall[l.world.idx(fence)] == World.W_NONE)
	check(l.world.wall[l.world.idx(fence)] == World.W_NONE, "забор снесли")
	check(not l.place_demolish(Vector2i(r0.end.x, r0.get_center().y)), "новую границу участка — нельзя")
	check(not l.world.in_plot(l.world.lot_rect(1).get_center()), "участок слева пока чужой")
	l.dev._finish("land3")
	check(l.world.in_plot(l.world.lot_rect(2).get_center()) and not l.world.in_plot(l.world.lot_rect(1).get_center()), "задний двор купили раньше левого — левый всё ещё чужой")
	var tn := Scenario.new_game("garage", "mech", "calm", 135)
	check(tn.world.lots.is_empty() and tn.dev.block_reason("land1").contains("нет"), "без участков: «%s»" % tn.dev.block_reason("land1"))

	print("— зоны обязательны")
	var z := Scenario.new_game("garage", "mech", "calm", 136)
	z.story.enabled = false
	z.rooms.update()
	var lathe: Thing = z.things_of("machine")[0]
	check(z.rooms.zone_ok(lathe), "станок в цехе — работает")
	var toilet: Thing = z.things_of("toilet")[0]
	check(z.rooms.zone_ok(toilet) and z.rooms.room_of_thing(toilet).type == "wc", "в гараже размечен туалет")
	var table: Thing = z.things_of("table")[0]
	check(z.rooms.room_of_thing(table).type == "canteen", "и столовая")
	z.rooms.paint(Rect2i(24, 9, 5, 5), "storage")
	var dr := z.place_thing("drill", Vector2i(26, 11), true, false)
	z.rooms.update()
	check(not z.rooms.zone_ok(dr) and not z.usable_of("machine").has(dr), "станок в зоне склада — им не пользуются")
	z.rooms.paint(Rect2i(26, 11, 1, 1), "workshop")
	check(z.rooms.zone_ok(dr), "разметили цех под станком — работает")
	var tlc: Vector2i = z.things_of("toilet")[0].cell
	z.rooms.paint(Rect2i(tlc.x, tlc.y, 2, 3), "workshop")
	check(z.usable_of("toilet").is_empty(), "туалет вне зоны «Туалет» — им не пользуются")

	print("— техпомещение, подстанция и аккумуляторы")
	var p := Scenario.new_game("sandbox", "mech", "calm", 137, {"money": 50000000, "all_open": true})
	p.story.enabled = false
	S._box(p, Rect2i(30, 3, 10, 7), 1, Vector2i(34, 9))
	p.rooms.update()
	var ktp := p.place_thing("substation", Vector2i(32, 5), true, false)
	p.rooms.update()
	check(p.power.source_capacity(ktp) == 0.0, "подстанция вне техпомещения не даёт ток")
	p.rooms.fill(Vector2i(31, 4), "tech_room")
	check(p.rooms.room_of_thing(ktp).type == "tech_room" and p.power.source_capacity(ktp) == 40.0, "в техпомещении — %d кВт" % int(p.power.source_capacity(ktp)))
	check(p.can_place("battery", Vector2i(37, 5)) != "", "аккумулятор далеко от подстанции — нельзя")
	var ring := [Vector2i(31, 4), Vector2i(32, 4), Vector2i(33, 4), Vector2i(34, 4), Vector2i(31, 5), Vector2i(34, 5), Vector2i(31, 6), Vector2i(34, 6), Vector2i(31, 7)]
	var bats: Array[Thing] = []
	for rc: Vector2i in ring:
		if p.can_place("battery", rc) == "":
			bats.append(p.place_thing("battery", rc, true, false))
	check(bats.size() == 9, "вокруг подстанции — 9 аккумуляторов")
	check(p.can_place("battery", Vector2i(32, 7)).contains("9"), "десятый не ставится: «%s»" % p.can_place("battery", Vector2i(32, 7)))
	p.world.cable[p.world.idx(Vector2i(32, 6))] = 1
	p.world.cable[p.world.idx(Vector2i(32, 7))] = 1
	p.world.cable_rev += 1
	p.power.update_topology()
	var net := p.power.net_of_thing(ktp)
	check(p.power.source_capacity(ktp) == 220.0, "подстанция с 9 шкафами — %d кВт (40 + 9×20)" % int(p.power.source_capacity(ktp)))
	var bs: Array = p.power.battery_state(net) if net else [0.0, 0]
	check(net != null and int(bs[1]) == 9 and float(bs[0]) == 180.0, "аккумуляторы в сети подстанции: %d шт., +%d кВт" % [int(bs[1]), int(bs[0])])
	bats[0].built = false
	check(p.power.source_capacity(ktp) == 200.0, "недостроенный шкаф не прибавляет: %d кВт" % int(p.power.source_capacity(ktp)))
	bats[0].built = true
	p.place_thing("cabinet", Vector2i(37, 5), true, false)
	check(p.can_place("battery", Vector2i(37, 6)) != "", "к малому трансформатору аккумулятор не прижать")

	print("— напор воды и насосная")
	var wq := Scenario.new_game("sandbox", "mech", "calm", 138, {"money": 50000000, "all_open": true})
	wq.story.enabled = false
	S._box(wq, Rect2i(10, 3, 18, 6), 4, Vector2i(14, 8))
	wq.rooms.update()
	var inlet := wq.place_thing("water_inlet", Vector2i(9, 9), true, false)
	for x4 in range(9, 27):
		wq.world.pipe[wq.world.idx(Vector2i(x4, 9))] = 1
	for x5 in range(11, 26):
		wq.world.pipe[wq.world.idx(Vector2i(x5, 6))] = 1
	for y5 in range(6, 10):
		wq.world.pipe[wq.world.idx(Vector2i(26, y5))] = 1
	wq.world.pipe_rev += 1
	var sinks: Array[Thing] = []
	for x6 in range(11, 25):
		sinks.append(wq.place_thing("sink", Vector2i(x6, 6), true, false))
	wq.rooms.fill(Vector2i(12, 5), "wc")
	wq.water._sig = ""
	var wet := sinks.filter(func(t5: Thing) -> bool: return wq.water.has_water(t5)).size()
	# 1.20: насос тянет все приборы без лимита
	check(inlet != null and wet == sinks.size(), "скважинный насос тянет %d приборов из %d" % [wet, sinks.size()])
	check(not wq.water.weak(sinks[-1]), "напора хватает и дальним")
	var dry := wq.place_thing("sink", Vector2i(12, 5), true, false)
	wq.water._sig = ""
	wq.water.update()
	check(not wq.water.has_water(dry), "труба рядом, но не в клетке раковины — воды нет")
	wq.remove_thing(dry, 0.0)
	S._box(wq, Rect2i(28, 3, 6, 6), 1, Vector2i(30, 8))
	wq.rooms.update()
	var ktp2 := wq.place_thing("substation", Vector2i(31, 4), true, false)
	var pump := wq.place_thing("pump_house", Vector2i(29, 4), true, false)
	wq.rooms.fill(Vector2i(29, 6), "tech_room")
	for y7 in range(5, 10):
		wq.world.pipe[wq.world.idx(Vector2i(29, y7))] = 1
	wq.world.pipe[wq.world.idx(Vector2i(27, 9))] = 1
	wq.world.pipe[wq.world.idx(Vector2i(28, 9))] = 1
	wq.world.pipe_rev += 1
	wq.world.cable[wq.world.idx(Vector2i(31, 4))] = 1
	wq.world.cable[wq.world.idx(Vector2i(30, 4))] = 1
	wq.world.cable_rev += 1
	wq.world.refresh_all()
	wq.rooms.update()
	wq.power.tick(1.0)
	check(wq.power.powered(pump) and wq.rooms.zone_ok(pump), "насосная в техпомещении и под током")
	wq.water._sig = ""
	var wet2 := sinks.filter(func(t6: Thing) -> bool: return wq.water.has_water(t6)).size()
	check(wet2 == sinks.size(), "с насосной вода у всех: %d из %d" % [wet2, sinks.size()])
	check(ktp2 != null, "подстанция для насосной")

	print("— сохранение")
	f.place_cable(Vector2i(30, 24) + org)
	var dd: Dictionary = JSON.parse_string(JSON.stringify(f.to_dict()))
	var f2 := Sim.from_dict(dd)
	var same := 0
	for i in f.world.w * f.world.h:
		if f.world.flora[i] == f2.world.flora[i]:
			same += 1
	check(same == f.world.w * f.world.h, "деревья сохраняются")
	check(f2.world.net_at("cable", Vector2i(30, 24) + org) == 2, "чертёж кабеля сохраняется")
	var ld: Dictionary = JSON.parse_string(JSON.stringify(l.to_dict()))
	var l2 := Sim.from_dict(ld)
	check(l2.world.lot_bought(0) and l2.world.in_plot(l2.world.lot_rect(0).get_center()) and not l2.world.in_plot(l2.world.lot_rect(1).get_center()), "купленный участок сохраняется")
	b.place_wall_bp(Vector2i(32, 8), World.W_BRICK)
	run(b, 15.0)
	var bd: Dictionary = JSON.parse_string(JSON.stringify(b.to_dict()))
	var b2 := Sim.from_dict(bd)
	check(b2.bmats.orders.size() == b.bmats.orders.size(), "заказ стройматериалов сохраняется")

	print("РЕЗУЛЬТАТ: " + ("OK" if fails.is_empty() else "ОШИБКИ: " + ", ".join(fails)))
	quit(0 if fails.is_empty() else 1)
