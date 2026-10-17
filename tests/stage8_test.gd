extends SceneTree
## Тест версии 0.8: поворот объектов, доставка оборудования фургоном в ящиках, зона разгрузки,
## склад оборудования (демонтаж и повторная установка), отмена заказа.
## godot --headless --path . -s res://tests/stage8_test.gd

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
		if until.is_valid() and int(t * 2.0) % 20 == 0 and bool(until.call()):
			break
	return t


## Свободное место внутри гаража для объекта.
func free_spot(sim: Sim, def_id: String, rot: int = 0) -> Vector2i:
	for y in range(9, 19):
		for x in range(15, 29):
			var c := Vector2i(x, y)
			if sim.can_place(def_id, c, rot) == "":
				# не загораживать проходы: соседние клетки снизу свободны
				return c
	return Vector2i(-1, -1)


func _init() -> void:
	print("— поворот")
	var s := Scenario.new_game("sandbox", "mech", "calm", 5, {"money": 5000000, "all_open": true})
	var l1 := s.place_thing("lathe", Vector2i(10, 10), true, false, 1)
	check(l1.size() == Vector2i(1, 3) and l1.spots()[0]["cell"] == Vector2i(9, 11) and str(l1.spots()[0]["face"]) == "right", "токарный на 90°: 1×3, рабочий слева лицом к станку")
	check(Thing.sprite_for("lathe", 1)[0] == "lathe_v" and bool(Thing.sprite_for("lathe", 3)[1]), "боковой спрайт и отражение на 270°")
	check(Thing.rotations("forklift") == 2 and Thing.rotations("toilet") == 4, "вытянутые без бокового вида — только разворот")
	var d := Sim.from_dict(JSON.parse_string(JSON.stringify(s.to_dict())))
	var l2: Thing = d.things.get(l1.id)
	check(l2 != null and l2.rot == 1 and d.world.occ[d.world.idx(Vector2i(10, 12))] == l1.id, "поворот сохраняется")
	d.dispose()
	s.dispose()

	print("— доставка оборудования")
	var g := Scenario.new_game("garage", "mech", "calm", 21)
	g.story.enabled = false
	g.money += 2000000.0
	var nz := g.set_area(Rect2i(16, 23, 6, 3), 1)
	check(nz == 18 and g.logi.has_zone(), "зона разгрузки отмечена: %d кл." % nz)
	var c1 := free_spot(g, "locker")
	var lk := g.place_thing("locker", c1, false, true)
	var c2 := free_spot(g, "plant")
	var pl := g.place_thing("plant", c2, false, true)
	var c3 := free_spot(g, "workbench")
	var dr := g.place_thing("workbench", c3, false, true)
	check(c3.x >= 0 and lk.crates_need == 1 and pl.crates_need == 1 and dr.crates_need == 2 and not g.logi.equip.is_empty(), "заказано у поставщика: %d позиций" % g.logi.equip.size())
	var saw_zone := false
	var saw_van := false
	var t0 := 0.0
	while t0 < 1440.0 * 2:
		g.tick(0.5)
		t0 += 0.5
		for v in g.vehicles:
			if not v.equip.is_empty() or (v.kind == "delivery" and v.state == "parked"):
				saw_van = true
		for gid in g.ground_items:
			var it: Item = g.items.get(gid)
			if it and it.kind == "crate" and g.logi.in_zone(it.cell):
				saw_zone = true
		if lk.built and pl.built and dr.built:
			break
	print("    за %.0f мин: шкафчик %s, цветок %s, верстак %s" % [t0, lk.built, pl.built, dr.built])
	check(saw_van, "приехал фургон с оборудованием")
	check(saw_zone, "ящики разгрузили в зону разгрузки")
	check(lk.built and pl.built and dr.built, "все объекты принесли и смонтировали")

	print("— склад оборудования")
	lk.demolish = true
	g.thing_rev += 1
	run(g, 1440.0, func() -> bool: return not g.things.has(lk.id) and g.logi.spare_count("locker") >= 1)
	check(not g.things.has(lk.id), "шкафчик демонтирован")
	check(g.logi.spare_count("locker") == 1, "шкафчик в ящике на складе оборудования")
	var m0 := g.money
	var lk2 := g.place_thing("locker", free_spot(g, "locker"), false, true)
	check(is_equal_approx(g.money, m0) and lk2.crates_need == 1, "поставили снова — со склада, бесплатно")
	run(g, 1440.0, func() -> bool: return lk2.built)
	check(lk2.built, "шкафчик со склада смонтирован")
	var m1 := g.money
	var fr := g.place_thing("fridge", free_spot(g, "fridge"), false, true)
	check(g.money < m1, "холодильник куплен")
	g.cancel_thing(fr)
	check(is_equal_approx(g.money, m1) and g.logi.equip.is_empty(), "отмена до отправки — деньги вернули")
	# продажа комплекта со склада
	var s2 := g.place_thing("plant", free_spot(g, "plant"), true, false)
	g.logi.on_demolished(s2)
	g.remove_thing(s2, 0.0)
	var m2 := g.money
	check(g.logi.sell_spare("plant") == "" and g.money > m2, "продали цветок со склада за полцены")
	var d2 := Sim.from_dict(JSON.parse_string(JSON.stringify(g.to_dict())))
	check(d2.world.area[d2.world.idx(Vector2i(17, 24))] == 1, "зона разгрузки сохраняется")
	d2.dispose()
	g.dispose()
	print("— сети: розетки, свет, вода, кран-балка")
	var n := Scenario.new_game("sandbox", "mech", "calm", 8, {"money": 9000000, "all_open": true})
	n.story.enabled = false
	Scenario.box(n, Rect2i(10, 6, 14, 10), 1, [Vector2i(16, 15)])
	n.world.refresh_all()
	n.rooms.update()
	var hall := n.rooms.room_at(Vector2i(15, 10))
	check(hall != null, "цех построен")
	n.rooms.assign(hall, "workshop")
	var cab := n.things_of("power")[0]
	# станок: кабель у левого края — не подключён, у розетки (задний правый угол) — подключён
	var lt := n.place_thing("lathe", Vector2i(12, 8), true, false)
	Scenario._route(n, [Vector2i(11, 8)])
	n.world.cable_rev += 1
	n.power.tick(0.1)
	check(lt.inlet_cell() == Vector2i(14, 8), "розетка токарного — задний правый угол: %s" % str(lt.inlet_cell()))
	check(not n.power.connected(lt), "кабель не у розетки — станок не подключён")
	Scenario._route(n, [lt.inlet_cell()])
	n.world.cable_rev += 1
	n.power.tick(0.1)
	check(n.power.connected(lt), "кабель подведён к розетке — подключён")
	# свет: светильник в 3 клетках от кабеля
	var lamp := n.place_thing("lamp_tube", Vector2i(17, 11), true, false)
	n.power.update_topology()
	var linked := n.power.light_link.has(lamp.id)
	check(not linked or Vector2(Vector2i(n.power.light_link[lamp.id]) - lamp.cell).length() <= 3.2, "светильник подключается к кабелю в радиусе 3 клеток")
	Scenario._route(n, [Vector2i(17, 9)])
	n.world.cable_rev += 1
	n.power.update_topology()
	check(n.power.light_link.has(lamp.id), "светильник подключён тонким проводом")
	n.minute = 1440.0 + 21.0 * 60.0
	var wk := n.workers[0]
	wk.present = true
	n.power.tick(0.5)
	check(bool(n.power.lamp_on.get(lamp.id, false)), "вечером, когда люди на месте, лампа горит")
	check(n.rooms.is_lit(Vector2i(17, 12)) and not n.rooms.is_lit(Vector2i(11, 14)), "освещено рядом с лампой, в дальнем углу — темно")
	# вода: туалет без трубы не работает
	Scenario.box(n, Rect2i(24, 6, 5, 5), 2, [Vector2i(24, 8)])
	n.world.refresh_all()
	n.rooms.update()
	var wc := n.rooms.room_at(Vector2i(26, 8))
	n.rooms.assign(wc, "wc")
	var toilet := n.place_thing("toilet", Vector2i(25, 7), true, false)
	n.place_thing("sink", Vector2i(26, 7), true, false)
	n.rooms.update()
	wc = n.rooms.room_at(Vector2i(26, 8))
	check(not n.water.has_water(toilet) and not wc.valid and wc.missing.any(func(m: String) -> bool: return m.begins_with("вода")), "туалет без воды: помещение не оборудовано")
	n.place_thing("water_inlet", Vector2i(30, 7), true, false)
	Scenario.autopipe(n)
	n.rooms.update()
	wc = n.rooms.room_at(Vector2i(26, 8))
	check(n.water.has_water(toilet) and wc.valid, "труба от ввода водопровода — вода есть, туалет работает")
	# кран-балка: в помещении, от стены до стены
	check(n.can_place("crane", Vector2i(5, 25)) != "", "кран-балку нельзя повесить на улице")
	check(n.can_place("crane", Vector2i(15, 12)) == "", "кран-балка в цеху — можно")
	var cr := n.place_thing("crane", Vector2i(15, 12), true, false)
	check(n.can_place("crane", Vector2i(18, 12)) != "", "вторая кран-балка в том же цеху — нельзя")
	lt.product = "shaft"
	hall = n.rooms.room_at(Vector2i(15, 10))
	check(n.prod.crane_k(lt) == 1.0 and n.prod.crane_in(hall) == cr, "тяжёлые детали в цеху с краном — без потерь")
	var d3 := Sim.from_dict(JSON.parse_string(JSON.stringify(n.to_dict())))
	check(d3.world.pipe[d3.world.idx(Vector2i(29, 7))] == 1 or d3.water.has_water(d3.things[toilet.id]), "водопровод сохраняется")
	check(d3.ceiling_at(lamp.cell) != null, "светильник под потолком сохраняется")
	d3.dispose()
	n.dispose()
	print("РЕЗУЛЬТАТ: ", "OK" if fails.is_empty() else "ОШИБКИ: " + ", ".join(fails))
	quit(0 if fails.is_empty() else 1)
