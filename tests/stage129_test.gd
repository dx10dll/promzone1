extends SceneTree
## Тест версии 1.29 «Склад и зоны»: обязательные зоны разгрузки и отгрузки, поддоны заготовок,
## готовый заказ идёт через зону отгрузки, дешёвые поддоны, миграция старых сохранений.
## godot --headless --path . -s res://tests/stage129_test.gd

var fails: Array[String] = []


func check(cond: bool, what: String) -> void:
	print(("  ✓ " if cond else "  ✗ ") + what)
	if not cond:
		fails.append(what)


func _things(g: Sim, def_id: String) -> Array[Thing]:
	var out: Array[Thing] = []
	for t: Thing in g.things.values():
		if t.def_id == def_id and t.built:
			out.append(t)
	return out


func _parts_on(g: Sim, ts: Array[Thing], p: String) -> int:
	var n := 0
	for t in ts:
		for iid in g.slot_ids(t, 0):
			var it: Item = g.items.get(iid)
			if it and it.def_id == p:
				n += 1
	return n


func _game(scn: String, seed_v: int) -> Sim:
	var g := Scenario.new_game(scn, "mech", "calm", seed_v)
	g.story.enabled = false
	g.progress.tutorial = -1
	g.bmats.enabled = false
	return g


func _init() -> void:
	Defs.load_all()

	print("— данные")
	check(Defs.objects.has("pallet_raw") and str(Defs.objects["pallet_raw"]["name"]) == "Поддон заготовок", "новый объект «Поддон заготовок»")
	var pr: Dictionary = Defs.objects.get("pallet_raw", {})
	check(str(pr.get("cat", "")) == "Склад" and (pr.get("storage", {}).get("accept", []) as Array).has("mat"), "в категории «Склад», принимает металл")
	check(float(pr.get("cost", 0)) <= 400.0, "поддон заготовок дешёвый: %s" % Defs.money_str(float(pr.get("cost", 0))))
	check(float(Defs.objects["pallet"]["cost"]) == 300.0, "поддон готовой продукции подешевел: 1500 → 300")
	check(Defs.sprites.has("pallet_raw") and ResourceLoader.exists("res://assets/objects/pallet_raw.svg"), "у поддона заготовок есть картинка")

	print("— новые игры: зоны и поддоны с самого начала")
	for scn in ["garage", "field", "sandbox"]:
		var s := _game(scn, 129)
		var raw := _things(s, "pallet_raw")
		var in_zone := raw.filter(func(t: Thing) -> bool: return s.logi.in_zone(t.cell))
		check(s.logi.has_zone() and s.logi.has_ship(), "%s: есть зона разгрузки (%d кл.) и зона отгрузки (%d кл.)" % [scn, s.logi.zone_cells().size(), s.logi.ship_cells().size()])
		check(in_zone.size() >= 1 and in_zone.size() <= 2, "%s: поддоны заготовок в зоне разгрузки: %d" % [scn, in_zone.size()])
		check(_things(s, "pallet").size() >= 1, "%s: есть поддоны готовой продукции: %d" % [scn, _things(s, "pallet").size()])
		var gate_y := s.world.plot.end.y
		var near := true
		for c in s.logi.zone_cells() + s.logi.ship_cells():
			if absi(c.y - gate_y) > 6 or absi(c.x - s.gate_x) > 16 or not s.world.passable(c) and s.world.occ[s.world.idx(c)] < 0:
				near = false
		check(near, "%s: зоны у ворот, на свободной земле" % scn)
		s.dispose()

	print("— зоны обязательны")
	var g := _game("garage", 1291)
	var zn := g.logi.zone_cells().size()
	var sn := g.logi.ship_cells().size()
	var all := g.world.plot
	check(g.set_area(all, 0) == -1 and g.area_refusal.contains("обязательна"), "стереть все зоны нельзя: «%s»" % g.area_refusal)
	check(g.logi.zone_cells().size() == zn and g.logi.ship_cells().size() == sn, "зоны на месте")
	var zr := Rect2i(g.logi.zone_cells()[0], Vector2i.ONE)
	for c in g.logi.zone_cells():
		zr = zr.merge(Rect2i(c, Vector2i.ONE))
	check(g.set_area(zr, Logistics.A_SHIP) == -1 and g.area_refusal.contains("разгрузки"), "закрасить всю разгрузку отгрузкой тоже нельзя")
	check(g.set_area(Rect2i(zr.position, Vector2i.ONE), 0) == 1 and g.logi.zone_cells().size() == zn - 1, "одну клетку убрать можно")
	var sr := Rect2i(g.logi.ship_cells()[0], Vector2i.ONE)
	for c2 in g.logi.ship_cells():
		sr = sr.merge(Rect2i(c2, Vector2i.ONE))
	check(g.set_area(sr, 0) == -1 and g.area_refusal.contains("машина клиента"), "последнюю отгрузку не стереть: объяснение про машину клиента")
	# перенос: сначала новая зона, потом старую можно убрать
	var nr := Rect2i(sr.end.x + 2, sr.position.y, 2, 2)
	check(g.set_area(nr, Logistics.A_SHIP) == 4, "отметили новую зону отгрузки")
	check(g.set_area(sr, 0) == sn and g.logi.ship_cells().size() == 4, "теперь старую можно убрать — зона перенесена")

	print("— металл из фургона — на поддоны заготовок")
	var m := _game("garage", 1292)
	m.money += 500000.0
	check(m.order_material("bar45", 10) == "", "заказали металл")
	for s0: Dictionary in m.supply:
		s0["eta"] = m.minute
	var raw_pal := _things(m, "pallet_raw")
	var on_raw := 0
	var guard := 0.0
	while guard < 1440.0 * 2:
		m.tick(1.0)
		guard += 1.0
		on_raw = 0
		for t in raw_pal:
			on_raw += m.count_slot(t, 0)
		if on_raw >= 10 or (on_raw > 0 and m.supply.is_empty() and _van_empty(m)):
			break
	check(on_raw >= 1, "металл разгрузили на поддоны заготовок: %d прутков (за %.0f мин)" % [on_raw, guard])
	var on_floor := 0
	for gid in m.ground_items:
		var it0: Item = m.items.get(gid)
		if it0 and it0.kind == "mat" and m.logi.in_zone(it0.cell):
			on_floor += 1
	check(on_raw >= on_floor, "поддоны в приоритете перед полом зоны (на поддонах %d, на полу %d)" % [on_raw, on_floor])
	m.dispose()

	print("— готовый заказ: склад → зона отгрузки → машина клиента")
	var h := _game("garage", 1293)
	var pallets := _things(h, "pallet")
	check(pallets.size() >= 2, "поддоны готовой продукции на складе: %d" % pallets.size())
	var o := h.orders.make_offer("pin")
	o["qty"] = 4
	h.orders.list.append(o)
	h.orders.accept(int(o["id"]), false)
	for i in 8:
		var it := h.new_item("part", "pin", "ok")
		h.put_in_thing(it, pallets[i % 2], 0)
	check(_parts_on(h, pallets, "pin") == 8, "8 готовых деталей на поддонах, заказ — на 4")
	h.orders._t = 0.0
	h.orders.tick(1.0)
	check(str(o["status"]) == "ready", "заказ готов, клиент выслал машину")
	o["pickup_eta"] = h.minute   # машина едет сразу — грузить можно только из зоны отгрузки
	var staged_max := 0
	var loaded_from_store := false
	guard = 0.0
	while str(o["status"]) != "done" and guard < 6000.0:
		h.tick(1.0)
		guard += 1.0
		staged_max = maxi(staged_max, h.logi.staged("pin"))
		for v: Vehicle in h.vehicles:
			if v.kind == "pickup" and v.state == "parked" and v.parked_time < 90.0 and v.loaded > 0 and _parts_on(h, pallets, "pin") < 4:
				loaded_from_store = true
	check(staged_max >= 1, "детали носили в зону отгрузки (до %d одновременно)" % staged_max)
	check(str(o["status"]) == "done", "машина забрала заказ (за %.0f мин)" % guard)
	check(_parts_on(h, pallets, "pin") == 4 and not loaded_from_store, "грузили только из зоны отгрузки: на поддонах осталось %d" % _parts_on(h, pallets, "pin"))

	print("— запасной путь: зона отгрузки недоступна — заказ не застревает")
	var k := _game("garage", 1294)
	var kp := _things(k, "pallet")
	var ko := k.orders.make_offer("pin")
	ko["qty"] = 3
	k.orders.list.append(ko)
	k.orders.accept(int(ko["id"]), false)
	for i2 in 3:
		k.put_in_thing(k.new_item("part", "pin", "ok"), kp[0], 0)
	# зона отгрузки закрыта сплошной стеной — туда не пройти
	for c3 in k.logi.ship_cells():
		k.world.wall[k.world.idx(c3)] = World.W_BRICK
	k.world.refresh_all()
	k.orders._t = 0.0
	k.orders.tick(1.0)
	ko["pickup_eta"] = k.minute
	guard = 0.0
	while str(ko["status"]) != "done" and guard < 4000.0:
		k.tick(1.0)
		guard += 1.0
	check(str(ko["status"]) == "done", "заказ отгружен со склада (за %.0f мин)" % guard)
	k.dispose()

	print("— сохранение и миграция")
	var d: Dictionary = JSON.parse_string(JSON.stringify(h.to_dict()))
	var h2 := Sim.from_dict(d)
	check(h2.logi.zone_cells().size() == h.logi.zone_cells().size() and h2.logi.ship_cells().size() == h.logi.ship_cells().size(), "зоны сохраняются")
	check(_things(h2, "pallet_raw").size() == _things(h, "pallet_raw").size(), "поддоны заготовок сохраняются")
	h2.dispose()
	# старое сохранение без зон и без поддонов заготовок
	var old: Dictionary = JSON.parse_string(JSON.stringify(h.to_dict()))
	old["version"] = 12
	var zero := PackedByteArray()
	zero.resize(h.world.w * h.world.h)
	zero.fill(0)
	(old["world"] as Dictionary)["area"] = Marshalls.raw_to_base64(zero)
	var things_d: Variant = old.get("things", [])
	if things_d is Array:
		old["things"] = (things_d as Array).filter(func(td: Variant) -> bool: return not (td is Dictionary and str((td as Dictionary).get("def", (td as Dictionary).get("def_id", ""))) == "pallet_raw"))
	var h3 := Sim.from_dict(old)
	check(h3.logi.has_zone() and h3.logi.has_ship(), "миграция: зоны добавлены у ворот (%d и %d кл.)" % [h3.logi.zone_cells().size(), h3.logi.ship_cells().size()])
	var told := false
	for e: Dictionary in h3.events:
		if str(e["text"]).contains("1.29"):
			told = true
	check(told, "игроку сказали об обязательных зонах")
	var h4 := Sim.from_dict(JSON.parse_string(JSON.stringify(h3.to_dict())))
	check(h4.logi.zone_cells().size() == h3.logi.zone_cells().size(), "повторная загрузка ничего не меняет")
	h4.dispose()
	h3.dispose()
	h.dispose()
	g.dispose()

	print("РЕЗУЛЬТАТ: " + ("OK" if fails.is_empty() else "ОШИБКИ: " + ", ".join(fails)))
	quit(0 if fails.is_empty() else 1)


func _van_empty(g: Sim) -> bool:
	for v: Vehicle in g.vehicles:
		if v.kind == "delivery" and not (g.veh_items.get(v.id, []) as Array).is_empty():
			return false
	return true
