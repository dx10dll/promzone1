extends SceneTree
## Тест 1.56 «Логистика, этап 1»: тара (поддоны/ящики), заказ комплектуется на поддон с биркой и идёт по цепочке
## статусов, машину клиента грузят её грузчики (наши не лезут в кузов), металл разгружают грузчики поставщика,
## станочник груз не носит при разнорабочем на смене, старый сейв грузится.
## godot --headless --path . --audio-driver Dummy -s res://tests/stage156_test.gd

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
	g.bmats.enabled = false
	return g


func _things(g: Sim, def_id: String) -> Array[Thing]:
	var out: Array[Thing] = []
	for t: Thing in g.things.values():
		if t.def_id == def_id and t.built:
			out.append(t)
	return out


func _pickup(g: Sim) -> Vehicle:
	for v: Vehicle in g.vehicles:
		if v.kind == "pickup":
			return v
	return null


func _initialize() -> void:
	Defs.load_all()

	print("— тара: данные")
	var sizes: Array = []
	for k in ["s", "m", "l"]:
		sizes.append(int((Defs.tare["parts"] as Dictionary)[k]))
	check(sizes.all(func(n: int) -> bool: return n >= 20 and n <= 50) and sizes[0] > sizes[1] and sizes[1] > sizes[2], "поддон на 20–50 штук, мелкая деталь — больше: %s" % str(sizes))
	var pin := Item.new()
	pin.kind = "part"
	pin.def_id = "pin"
	var shaft := Item.new()
	shaft.kind = "part"
	shaft.def_id = "shaft"
	check(Logistics.tare_of(pin) == 50 and Logistics.tare_of(shaft) == 30, "в таре: штифтов %d, валов %d" % [Logistics.tare_of(pin), Logistics.tare_of(shaft)])
	check(Logistics.cap_for(pin, "cart", 6) == 50 and Logistics.cap_for(pin, "", 6) < 50 and Logistics.cap_for(pin, "", 6) > 6, "рохля несёт поддон (50), без неё — ящик (%d) вместо пачки в 6" % Logistics.cap_for(pin, "", 6))
	check(str(Defs.objects["cart"]["name"]) == "Тележка-рохля", "тележка-рохля есть как объект «Логистика»")

	print("— заказ: комплектуется на поддон с биркой, статусы по цепочке")
	var g := _game("garage", 1561)
	S.hire(g, "laborer", "haul", 6)
	for w: Worker in g.workers:
		w.present = true
		w.pos = Vector2(g.logi.ship_cells()[0]) + Vector2(0.5, -1.5)
	var pallets := _things(g, "pallet")
	var o := g.orders.make_offer("pin")
	o["qty"] = 20
	o["status"] = "offer"
	g.orders.list.append(o)
	g.orders.accept(int(o["id"]), false)
	var seen := {}
	seen[g.orders.stage(o)] = true
	check(g.orders.stage(o) == 0 and g.orders.stage_name(0) == "В производстве", "принят: «%s»" % g.orders.stage_name(g.orders.stage(o)))
	for i in 24:
		g.put_in_thing(g.new_item("part", "pin", "ok"), pallets[i % pallets.size()], 0)
	g.orders._t = 0.0
	g.orders.tick(1.0)
	check(str(o["status"]) == "ready", "заказ готов")
	o["pickup_eta"] = g.minute
	var pallets_seen := 0
	var staged_at_arrival := -1
	var worker_loaded := false
	var vehicle_parked_t := -1.0
	var park_min := 0.0
	var t := 0.0
	var tag := ""
	while str(o["status"]) != "done" and t < 3000.0:
		g.tick(0.5)
		t += 0.5
		seen[g.orders.stage(o)] = true
		for w2: Worker in g.workers:
			if w2.task and w2.task.kind == "load":
				worker_loaded = true
		var v := _pickup(g)
		if v and v.state == "parked":
			if vehicle_parked_t < 0.0:
				vehicle_parked_t = t
				staged_at_arrival = g.logi.staged_for(o)
		pallets_seen = maxi(pallets_seen, int(g.logi.pallets_of(o)[0]))
		if tag == "" and g.logi.staged_for(o) > 0:
			tag = g.orders.tag(o)
	check(str(o["status"]) == "done", "заказ отгружен (за %.0f мин)" % t)
	check(seen.has(0) and seen.has(1) and seen.has(2) and seen.has(3), "статусы прошли по цепочке: %s" % str(seen.keys()))
	check(g.orders.stage(o) == 4 and g.orders.stage_name(4) == "Уехал", "в конце: «%s»" % g.orders.stage_name(g.orders.stage(o)))
	check(pallets_seen >= 1 and tag.contains("Заказ №") and tag.contains("20 шт."), "бирка на поддоне: %s (поддонов: %d)" % [tag, pallets_seen])
	check(staged_at_arrival >= 20, "машина приехала к собранному поддону (%d из 20)" % staged_at_arrival)
	check(not worker_loaded, "наши в кузов не лезли (задач «погрузка» не было)")
	check(g.orders.chain_text(o).contains("→") and g.orders.chain_text(o).contains("Уехал"), "цепочка одной строкой: %s" % g.orders.chain_text(o))
	g.dispose()

	print("— погрузка: грузчики машины, минуты, без наших")
	var h := _game("garage", 1562)
	h.workers.clear()
	var ho := h.orders.make_offer("pin")
	ho["qty"] = 40
	ho["status"] = "offer"
	h.orders.list.append(ho)
	h.orders.accept(int(ho["id"]), false)
	for i2 in 40:
		var it := h.new_item("part", "pin", "ok")
		it.ord_id = int(ho["id"])
		h.put_on_ground(it, h.logi.ship_cells()[0])
	check(h.logi.staged_for(ho) == 40 and int(h.logi.pallets_of(ho)[0]) == 1, "40 деталей на одном поддоне")
	h.orders._t = 0.0
	h.orders.tick(1.0)
	ho["pickup_eta"] = h.minute
	h.orders._t = 0.0
	h.orders.tick(1.0)
	check(str(ho["status"]) == "shipping", "машина клиента выехала сразу: поддон уже собран")
	var pt := -1.0
	var lt := -1.0
	var tt := 0.0
	var no_hands := true
	while str(ho["status"]) != "done" and tt < 600.0:
		h.tick(0.5)
		tt += 0.5
		var hv := _pickup(h)
		if hv and hv.state == "parked" and pt < 0.0:
			pt = tt
		for it2: Item in h.items.values():
			if it2.loc == Item.Loc.VEHICLE and it2.reserved_by >= 0:
				no_hands = false
		if hv and hv.loaded >= hv.need and lt < 0.0:
			lt = tt
	check(pt >= 0.0 and lt >= 0.0 and lt - pt <= 40.0, "40 деталей погружены за %.1f игр. мин после приезда (не более 40: грузчики ходят пешком, 1.57)" % (lt - pt))
	check(no_hands and str(ho["status"]) == "done", "рабочих на заводе нет — машину всё равно загрузили; заказ закрыт")
	h.dispose()

	print("— разгрузка поставщика: грузчики кладут тарой в зону")
	var m := _game("garage", 1563)
	m.money = 900000.0
	m.workers.clear()
	var err := m.order_material("bar45", 60)
	check(err == "", "металл заказан %s" % err)
	for sp: Dictionary in m.supply:
		sp["eta"] = m.minute
	var arrived := -1.0
	var left := -1.0
	var mt := 0.0
	var hands := false
	while mt < 600.0:
		m.tick(0.5)
		mt += 0.5
		for v2: Vehicle in m.vehicles:
			if v2.kind == "delivery" and v2.state == "parked":
				if arrived < 0.0:
					arrived = mt
				for iid in (m.veh_items.get(v2.id, []) as Array):
					var vi: Item = m.items.get(iid)
					if vi and vi.reserved_by >= 0:
						hands = true
		if arrived >= 0.0 and m.vehicles.is_empty() and left < 0.0:
			left = mt
			break
	var in_zone := 0
	var on_raw := 0
	for it3: Item in m.items.values():
		if it3.kind != "mat" or it3.def_id != "bar45":
			continue
		if it3.loc == Item.Loc.GROUND and m.logi.in_zone(it3.cell):
			in_zone += 1
		elif it3.loc == Item.Loc.THING:
			var th: Thing = m.things.get(it3.holder)
			if th and th.def_id == "pallet_raw":
				on_raw += 1
	check(arrived >= 0.0 and left >= 0.0 and left - arrived <= 45.0, "машина разгружена и уехала за %.1f мин" % (left - arrived))
	check(on_raw + in_zone >= 60 and not hands, "металл в зоне разгрузки: %d на поддонах заготовок + %d на полу; наши груз из кузова не брали" % [on_raw, in_zone])
	m.dispose()

	print("— станочник груз не носит, пока на смене есть разнорабочий")
	var res := [0, 0]
	for with_lab in [true, false]:
		var b := _game("garage", 1564)
		S.big_shop(b, false)
		for o0: Dictionary in b.orders.list.duplicate():
			b.orders.list.erase(o0)
		var turner := S.hire(b, "turner", "turning", 6)
		var cnc := S.hire(b, "miller", "milling", 6)
		for w4: Worker in b.workers.duplicate():
			if w4.prof == "laborer":
				b.workers.erase(w4)
		if with_lab:
			S.hire(b, "laborer", "haul", 7)
		for w3: Worker in b.workers:
			w3.present = true
			w3.pos = Vector2(34.5, 14.5)
		for i3 in 14:
			b.put_on_ground(b.new_item("mat", "bar45", "raw"), Vector2i(32 + i3 % 6, 16 + i3 / 6))
		var bad := 0
		var tt2 := 0.0
		while tt2 < 240.0:
			b.tick(0.5)
			tt2 += 0.5
			for mw in [turner, cnc]:
				var tk: Task = (mw as Worker).task
				if tk == null:
					continue
				if tk.kind == "haul_cell" or tk.kind == "deliver" or tk.kind == "load":
					bad += 1
				elif tk.kind == "haul":
					var last: Dictionary = tk.toils[tk.toils.size() - 1]
					var dt: Thing = b.things.get(int(last.get("thing", -1)))
					if dt == null or dt.kind() != "machine":
						bad += 1
		res[0 if with_lab else 1] = bad
		b.dispose()
	check(int(res[0]) == 0, "с разнорабочим станочники носили груз не к станку %d раз" % int(res[0]))
	check(int(res[1]) > 0, "а без разнорабочего те же станочники носят груз сами (%d раз) — правило работает именно из-за него" % int(res[1]))

	print("— старый сейв грузится")
	var s := _game("garage", 1565)
	var so := s.orders.make_offer("pin")
	so["qty"] = 5
	so["status"] = "offer"
	s.orders.list.append(so)
	s.orders.accept(int(so["id"]), false)
	for i4 in 5:
		s.put_on_ground(s.new_item("part", "pin", "ok"), s.logi.ship_cells()[0])
	var d: Dictionary = JSON.parse_string(JSON.stringify(s.to_dict()))
	for idc: Dictionary in d["items"]:
		idc.erase("ord")
	for ov: Dictionary in d["vehicles"]:
		ov.erase("crew_t")
		ov.erase("crew_idle")
		ov.erase("crew_off")
	for od: Dictionary in (d["orders"] as Dictionary).get("list", []) if d["orders"] is Dictionary else d["orders"]:
		od.erase("num")
	var s2 := Sim.from_dict(d)
	var legacy := 0
	for it5: Item in s2.items.values():
		if it5.kind == "part" and it5.ord_id == -1:
			legacy += 1
	check(legacy == 5, "детали старого формата на месте (%d), без бирки" % legacy)
	var so2: Dictionary = s2.orders.get_order(int(so["id"]))
	check(s2.logi.staged_for(so2) == 5, "детали без бирки в зоне отгрузки засчитаны заказу")
	s2.orders._t = 0.0
	s2.orders.tick(1.0)
	so2["pickup_eta"] = s2.minute
	var st2 := 0.0
	while str(so2["status"]) != "done" and st2 < 1500.0:
		s2.tick(0.5)
		st2 += 0.5
	check(str(so2["status"]) == "done" and s2.orders.num(so2) >= 1, "заказ из старого сейва отгружен (за %.0f мин), номер присвоен: №%d" % [st2, s2.orders.num(so2)])
	s2.dispose()
	s.dispose()

	print("")
	if fails.is_empty():
		print("ВСЕ ПРОВЕРКИ ПРОЙДЕНЫ")
	else:
		print("ПРОВАЛЕНО: %d" % fails.size())
		for f in fails:
			print("  - " + f)
	quit(0 if fails.is_empty() else 1)
