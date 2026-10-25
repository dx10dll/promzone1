extends SceneTree
## Тест 1.47 «Приоритеты»: срочный заказ бьёт несрочный (станок бросает несрочную втулку), среди срочных
## раньше срок, станочник не идёт на стройку, пока у его станков есть работа, а строитель строит.
## godot --headless --path . --audio-driver Dummy -s res://tests/stage147_test.gd

const S := preload("res://tests/setups.gd")

var fails: Array[String] = []


func check(cond: bool, what: String) -> void:
	print(("  ✓ " if cond else "  ✗ ") + what)
	if not cond:
		fails.append(what)


func _order(g: Sim, p: String, qty: int, lead: int) -> Dictionary:
	var o := g.orders.make_offer(p)
	o["qty"] = qty
	o["lead"] = lead
	o["status"] = "offer"
	g.orders.list.append(o)
	g.orders.accept(int(o["id"]), true)
	return o


func _setup(seed_n: int) -> Sim:
	var g := Scenario.new_game("garage", "mech", "calm", seed_n)
	g.story.enabled = false
	S.big_shop(g, false)
	for o0: Dictionary in g.orders.list.duplicate():
		g.orders.list.erase(o0)
	for i in 14:
		g.put_on_ground(g.new_item("mat", "bar45", "raw"), Vector2i(32 + i % 6, 16 + i / 6))
	return g


func _run(g: Sim, mins: float) -> void:
	var t := 0.0
	while t < mins:
		g.tick(0.5)
		t += 0.5


## Сколько деталей и заготовок изделия существует (в станках, на складах, на полу, в руках).
func _stock(g: Sim) -> int:
	var n := 0
	for it: Item in g.items.values():
		if it.kind == "part" or (it.kind == "mat" and it.def_id == "bar45"):
			n += 1
	return n


func _initialize() -> void:
	Defs.load_all()
	print("— срочный заказ прерывает несрочную втулку")
	var g := _setup(147)
	var lathe: Thing = null
	for m: Thing in g.things_of("machine"):
		if m.process() == "turning":
			lathe = m
	var turner := S.hire(g, "turner", "turning", 6)
	var lab := S.hire(g, "laborer", "haul", 7)
	for w: Worker in g.workers:
		w.present = true
		w.pos = Vector2(34.5, 14.5)
	var oa := _order(g, "bushing", 8, 6)
	var ob := _order(g, "stud", 8, 6)
	g.planner.tick(10.0)
	var seen_bushing := false
	var t := 0.0
	while t < 240.0 and not seen_bushing:
		g.tick(0.5)
		t += 0.5
		seen_bushing = lathe.product == "bushing" and lathe.progress > 0.05 and lathe.progress < 0.7
	if not seen_bushing:
		# заказ B сам мог оказаться первым по сроку — тогда меняем роли
		seen_bushing = lathe.product != "" and lathe.progress > 0.05 and lathe.progress < 0.7
	var first := lathe.product
	check(seen_bushing and first != "", "токарь взялся за несрочное изделие «%s» (прогресс %.2f)" % [first, lathe.progress])
	var urgent_o: Dictionary = ob if first == "bushing" else oa
	var urgent_p := str(urgent_o["product"])
	var before := _stock(g)
	var items_before := g.items.size()
	urgent_o["prio"] = 1
	var sw := -1.0
	var t2 := 0.0
	while t2 < 5.0:
		g.tick(0.5)
		t2 += 0.5
		if sw < 0.0 and lathe.product == urgent_p:
			sw = t2
	check(sw >= 0.0, "станок переключился на срочное «%s» за %.1f игр. мин (не более 5)" % [urgent_p, sw])
	check(_stock(g) == before, "заготовки и детали не пропали и не прибавились сами: было %d, стало %d" % [before, _stock(g)])
	_run(g, 120.0)
	var made_urgent := 0
	for it: Item in g.items.values():
		if it.kind == "part" and it.def_id == urgent_p:
			made_urgent += 1
	check(made_urgent > 0, "срочных деталей сделано: %d" % made_urgent)
	var lost := false
	for it: Item in g.items.values():
		if it.loc == Item.Loc.THING and not g.things.has(it.holder):
			lost = true
	check(not lost, "предметов «в никуда» нет; заготовки и детали на месте (%d → %d предметов)" % [items_before, g.items.size()])

	print("— два срочных: первым идёт ранний срок")
	var g2 := _setup(148)
	var lathe2: Thing = null
	for m2: Thing in g2.things_of("machine"):
		if m2.process() == "turning":
			lathe2 = m2
	S.hire(g2, "turner", "turning", 6)
	S.hire(g2, "laborer", "haul", 7)
	for w2: Worker in g2.workers:
		w2.present = true
		w2.pos = Vector2(34.5, 14.5)
	var late := _order(g2, "bushing", 8, 9)
	var early := _order(g2, "stud", 8, 4)
	late["prio"] = 1
	early["prio"] = 1
	g2.planner.tick(10.0)
	check(float(early["deadline"]) < float(late["deadline"]), "у «шпильки» срок раньше")
	check(g2.planner.urgent_deadline("stud") < g2.planner.urgent_deadline("bushing"), "планировщик видит срочность обоих")
	_run(g2, 4.0)
	check(lathe2.product == "stud", "станок взял срочную шпильку с ранним сроком, а не «%s»" % lathe2.product)
	# теперь у втулки срок раньше — станок переключается, если шпилька ещё не почти готова
	late["deadline"] = float(early["deadline"]) - 1440.0
	_run(g2, 6.0)
	check(lathe2.product == "bushing", "срок втулки стал раньше — станок перешёл на неё (сейчас «%s»)" % lathe2.product)

	print("— станочник не идёт на стройку, строитель строит")
	var g3 := _setup(149)
	S.hire(g3, "laborer", "haul", 7)
	var tn := S.hire(g3, "turner", "turning", 6)
	var bl := S.hire(g3, "builder", "build", 6)
	for w3: Worker in g3.workers:
		w3.present = true
		w3.pos = Vector2(34.5, 14.5)
	_order(g3, "bushing", 8, 6)
	var rk := g3.place_thing("rack", Vector2i(33, 17), false, false)
	check(rk != null and not rk.built, "стеллаж ждёт стройки")
	g3.planner.tick(10.0)
	var bad := 0
	var good := 0
	for i in 6:
		g3.planner.tick(10.0)
		var tt: Task = g3.brain._find_work(tn)
		if tt != null:
			if tt.kind in ["build_bp", "build_thing", "demolish", "lay_net"]:
				bad += 1
			g3.brain.abort(tn)
		var tb: Task = g3.brain._find_work(bl)
		if tb != null:
			if tb.kind in ["build_bp", "build_thing"]:
				good += 1
			g3.brain.abort(bl)
		g3.tick(0.5)
	check(bad == 0, "токарь при заказе не берёт стройку (%d раз)" % bad)
	check(good > 0, "строитель берёт стройку (%d раз из 6)" % good)
	# нет заказов — станочнику стройка разрешена
	var g4 := _setup(150)
	for it3: Item in g4.items.values().duplicate():
		g4.delete_item(it3)
	var tn4 := S.hire(g4, "turner", "turning", 6)
	tn4.present = true
	tn4.pos = Vector2(34.5, 14.5)
	var rk4 := g4.place_thing("rack", Vector2i(33, 17), false, false)
	g4.tick(0.5)
	var tt2: Task = g4.brain._find_work(tn4)
	check(rk4 != null and tt2 != null and tt2.kind in ["build_thing", "build_bp"], "без заказов токарь может строить (%s)" % (tt2.kind if tt2 else "—"))
	print("— люди обходят высокие объекты, через поддон перелезают только если иначе не пройти")
	var g5 := _setup(151)
	for it5: Item in g5.items.values().duplicate():
		g5.delete_item(it5)
	var rk5 := g5.place_thing("rack", Vector2i(34, 16), true, false)
	var p5 := g5.world.find_path(Vector2i(32, 16), Vector2i(37, 16))
	check(rk5 != null and not p5.is_empty() and not p5.has(Vector2i(34, 16)) and not p5.has(Vector2i(35, 16)), "путь мимо стеллажа есть и идёт в обход")
	var pl := g5.place_thing("pallet", Vector2i(34, 14), true, false)
	var p6 := g5.world.find_path(Vector2i(34, 13), Vector2i(34, 15))
	check(pl != null and pl.is_low() and not p6.is_empty() and not p6.has(Vector2i(34, 14)), "поддон есть обход — идут в обход, а не поверху")
	var pocket := Vector2i(37, 17)
	for dd: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		g5.place_thing("pallet", pocket + dd, true, false)
	check(g5.world.reachable(Vector2i(34, 13), pocket), "клетка в кольце из поддонов достижима (перелезают, не застревают)")
	# узкий коридор: высокий объект в нём перекрыл бы проход — ставить нельзя
	for x7 in range(31, 42):
		for y7 in [16, 18]:
			g5.world.wall[g5.world.idx(Vector2i(x7, y7))] = World.W_BRICK
	g5.world.wall[g5.world.idx(Vector2i(41, 17))] = World.W_BRICK
	g5.world.refresh_all()
	var why := g5.can_place("safe", Vector2i(34, 17))
	check(why.contains("Перекроет"), "сейф посреди тупикового коридора не поставить: «%s»" % why)

	print("— замкнутость помещения не зависит от пола")
	var g6 := _setup(152)
	var box := Rect2i(31, 24, 8, 6)
	S._box(g6, box, 1, Vector2i(35, 24))
	g6.world.flr[g6.world.idx(Vector2i(34, 27))] = 0
	g6.world.flr[g6.world.idx(Vector2i(35, 27))] = 0
	g6.rooms.rebuild()
	var rr := g6.rooms.room_at(Vector2i(33, 26))
	check(rr != null, "помещение с двумя клетками земли внутри распознано")
	if rr:
		check(g6.rooms.space_of[g6.world.idx(Vector2i(34, 27))] >= 0, "клетки без пола входят в помещение")
		g6.rooms.assign(rr, "storage")
		g6.rooms.rebuild()
		var rr2 := g6.rooms.room_at(Vector2i(33, 26))
		check(rr2 != null and rr2.type == "storage", "помещение назначено складом")
	check(g6.rooms.space_of[g6.world.idx(Vector2i(2, 2))] < 0, "улица помещением не стала")

	print("— срок выполнен, когда заказ готов, а не когда приехала машина")
	var g7 := _setup(153)
	var o7 := _order(g7, "bushing", 4, 3)
	o7["deadline"] = g7.minute + 120.0
	o7["status"] = "ready"
	o7["ready_at"] = g7.minute + 60.0   # готов за час до срока
	g7.minute += 300.0                   # машина приехала уже после срока
	var v7 := Vehicle.new()
	v7.order_id = int(o7["id"])
	v7.loaded = 4
	g7.orders.on_pickup_done(v7)
	var full7 := float(o7["price"]) * 4 - float(o7.get("paid_part", 0.0))
	check(str(o7["status"]) == "done" and int(o7["late_days"]) == 0, "заказ не просрочен, хотя машина приехала после срока")
	check(absf(float(o7["paid"]) - full7) < 1.0, "оплата полная: %d из %d" % [int(float(o7["paid"])), int(full7)])

	print("— метка «захламлено» снимается сама")
	var g8 := _setup(154)
	for i8 in 14:
		g8.put_on_ground(g8.new_item("mat", "bar45", "raw"), Vector2i(32 + i8 % 6, 16 + i8 / 6))
	g8.inspect.marks.append({"cell": [32, 16], "text": "Захламлены проходы: грузы на полу", "until": g8.minute + 5000.0, "type": "fire", "key": "clutter"})
	_run(g8, 3.0)
	var kept := g8.inspect.marks.size()
	for it8: Item in g8.items.values().duplicate():
		if it8.loc == Item.Loc.GROUND:
			g8.delete_item(it8)
	_run(g8, 3.0)
	check(kept == 1 and g8.inspect.marks.is_empty(), "пока мусор лежит метка есть (%d), убрали — метки нет (%d)" % [kept, g8.inspect.marks.size()])

	print("— замечание инспекции «захламлено» устраняют в первую очередь")
	var g9 := _setup(155)
	for it9: Item in g9.items.values().duplicate():
		g9.delete_item(it9)
	for i9 in 14:
		g9.put_on_ground(g9.new_item("mat", "bar45", "raw"), Vector2i(32 + i9 % 6, 16 + i9 / 6))
	g9.place_thing("rack", Vector2i(33, 12), false, false)
	var lab9 := S.hire(g9, "laborer", "haul", 6)
	lab9.present = true
	lab9.pos = Vector2(34.5, 14.5)
	g9.inspect.marks.append({"cell": [32, 16], "text": "Захламлены проходы: грузы на полу", "until": g9.minute + 5000.0, "type": "fire", "key": "clutter"})
	var tk9: Task = g9.brain._find_work(lab9)
	var picks_ground := false
	if tk9 != null and tk9.kind == "haul":
		for iid in tk9.res_items:
			var hi: Item = g9.items.get(iid)
			if hi != null and hi.loc == Item.Loc.GROUND:
				picks_ground = true
	check(picks_ground, "разнорабочий сразу берётся убирать захламлённый пол (%s)" % (tk9.kind if tk9 else "—"))

	print("РЕЗУЛЬТАТ: ", "OK" if fails.is_empty() else "ОШИБКИ: %s" % str(fails))
	quit(0 if fails.is_empty() else 1)
