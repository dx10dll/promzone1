extends SceneTree
## Тест 1.57 «Логистика: грузчики ходят пешком»: машина встаёт у ворот, грузчики водителя носят поддоны/ящики
## от неё до зоны и обратно (груз виден в руках, не телепортируется), чем дальше зона — тем дольше; грузчики не наши
## (не персонал); у далёкой зоны — предупреждение «Далеко от дороги: погрузка ×N»; старый сейв грузится.
## godot --headless --path . --audio-driver Dummy -s res://tests/stage157_test.gd

var fails: Array[String] = []

const NEAR_UNLOAD := Rect2i(20, 25, 4, 2)
const FAR_UNLOAD := Rect2i(3, 3, 4, 2)
const NEAR_SHIP := Rect2i(24, 25, 4, 2)
const FAR_SHIP := Rect2i(8, 3, 4, 2)


func check(cond: bool, what: String) -> void:
	print(("  ✓ " if cond else "  ✗ ") + what)
	if not cond:
		fails.append(what)


func _game(seed_v: int) -> Sim:
	var g := Scenario.new_game("garage", "mech", "calm", seed_v)
	g.story.enabled = false
	g.progress.tutorial = -1
	g.bmats.enabled = false
	g.workers.clear()
	return g


## Заменить зону целиком: новая отмечается первой, старая стирается.
func _move_zone(g: Sim, area: int, r: Rect2i) -> void:
	var old: Array[Vector2i] = g.logi.zone_cells() if area == Logistics.A_UNLOAD else g.logi.ship_cells()
	var old_c := old.duplicate()
	g.set_area(r, area)
	for c: Vector2i in old_c:
		if not r.has_point(c):
			g.set_area(Rect2i(c, Vector2i(1, 1)), 0)
	_no_raw(g)


## Поддоны заготовок убираем: металл ляжет на пол зоны, а не на поддон, оставшийся у ворот.
func _no_raw(g: Sim) -> void:
	for t: Thing in g.things.values().duplicate():
		if t.def_id == Logistics.RAW_PALLET:
			g.remove_thing(t, 0.0)


func _pickup(g: Sim) -> Vehicle:
	for v: Vehicle in g.vehicles:
		if v.kind == "pickup":
			return v
	return null


## Разгрузка 60 прутков: сколько минут от приезда до отъезда + слежение за грузом.
func _unload_run(g: Sim) -> Dictionary:
	g.money = 900000.0
	var err := g.order_material("bar45", 60)
	for sp: Dictionary in g.supply:
		sp["eta"] = g.minute
	var arrived := -1.0
	var left := -1.0
	var t := 0.0
	var prev_loc := {}
	var teleports := 0
	var carried_steps := 0
	var crew_seen := 0
	var jump := 0.0
	var prev_cell := {}
	var carried_cells := {}
	var hands_ours := false
	var crew_ids := {}
	while t < 900.0:
		g.tick(0.5)
		t += 0.5
		var parked := false
		for v: Vehicle in g.vehicles:
			if v.kind == "delivery" and v.state == "parked":
				parked = true
				if arrived < 0.0:
					arrived = t
				crew_seen = maxi(crew_seen, g.logi.crew_of(v).size())
				for c: Dictionary in g.logi.crew_of(v):
					crew_ids[(c["w"] as Worker).id] = true
		for it: Item in g.items.values():
			if it.kind != "mat":
				continue
			var pl: int = int(prev_loc.get(it.id, -1))
			if pl == Item.Loc.VEHICLE and (it.loc == Item.Loc.GROUND or it.loc == Item.Loc.THING):
				teleports += 1
			prev_loc[it.id] = it.loc
			if it.loc == Item.Loc.WORKER:
				carried_steps += 1
				var cl := g.item_cell(it)
				carried_cells[cl] = true
				if prev_cell.has(it.id):
					jump = maxf(jump, Vector2(cl).distance_to(Vector2(prev_cell[it.id])))
				prev_cell[it.id] = cl
				if g.get_worker(it.holder) != null:
					hands_ours = true
			else:
				prev_cell.erase(it.id)
		if arrived >= 0.0 and not parked and left < 0.0:
			left = t
			break
	var in_zone := 0
	for it2: Item in g.items.values():
		if it2.kind == "mat" and it2.def_id == "bar45":
			if it2.loc == Item.Loc.THING or (it2.loc == Item.Loc.GROUND and g.logi.in_zone(it2.cell)):
				in_zone += 1
	return {"err": err, "time": left - arrived if left >= 0.0 and arrived >= 0.0 else -1.0, "teleports": teleports,
		"carried": carried_steps, "cells": carried_cells.size(), "jump": jump, "crew": crew_seen, "in_zone": in_zone,
		"hands_ours": hands_ours, "crew_ids": crew_ids.keys()}


## Погрузка 40 деталей заказа с поддона в зоне отгрузки.
func _load_run(g: Sim) -> Dictionary:
	var o := g.orders.make_offer("pin")
	o["qty"] = 40
	o["status"] = "offer"
	g.orders.list.append(o)
	g.orders.accept(int(o["id"]), false)
	var cell: Vector2i = g.logi.ship_cells()[0]
	for i in 40:
		var it := g.new_item("part", "pin", "ok")
		it.ord_id = int(o["id"])
		g.put_on_ground(it, cell)
	g.orders._t = 0.0
	g.orders.tick(1.0)
	o["pickup_eta"] = g.minute
	g.orders._t = 0.0
	g.orders.tick(1.0)
	var parked_t := -1.0
	var loaded_t := -1.0
	var t := 0.0
	var carried := 0
	var teleports := 0
	var prev_loc := {}
	while str(o["status"]) != "done" and t < 900.0:
		g.tick(0.5)
		t += 0.5
		var v := _pickup(g)
		if v and v.state == "parked" and parked_t < 0.0:
			parked_t = t
		if v and v.loaded >= v.need and loaded_t < 0.0:
			loaded_t = t
		for it2: Item in g.items.values():
			if it2.kind != "part":
				continue
			var pl: int = int(prev_loc.get(it2.id, -1))
			if pl == Item.Loc.GROUND and it2.loc == Item.Loc.VEHICLE:
				teleports += 1
			prev_loc[it2.id] = it2.loc
			if it2.loc == Item.Loc.WORKER:
				carried += 1
	return {"time": loaded_t - parked_t if loaded_t >= 0.0 and parked_t >= 0.0 else -1.0, "teleports": teleports, "carried": carried,
		"done": str(o["status"]) == "done"}


func _initialize() -> void:
	Defs.load_all()

	print("— предупреждение «далеко от дороги»")
	var near := _game(1571)
	_move_zone(near, Logistics.A_UNLOAD, NEAR_UNLOAD)
	_move_zone(near, Logistics.A_SHIP, NEAR_SHIP)
	var far := _game(1571)
	_move_zone(far, Logistics.A_UNLOAD, FAR_UNLOAD)
	_move_zone(far, Logistics.A_SHIP, FAR_SHIP)
	var kn := near.logi.slowdown(Logistics.A_UNLOAD)
	var kf := far.logi.slowdown(Logistics.A_UNLOAD)
	print("    зона у дороги: %.0f кл., ×%.2f; далёкая: %.0f кл., ×%.2f" % [near.logi.road_steps(Logistics.A_UNLOAD), kn, far.logi.road_steps(Logistics.A_UNLOAD), kf])
	check(near.logi.far_text(Logistics.A_UNLOAD) == "" and near.logi.far_text(Logistics.A_SHIP) == "", "у дороги предупреждения нет (×%.2f / ×%.2f)" % [kn, near.logi.slowdown(Logistics.A_SHIP)])
	var ft := far.logi.far_text(Logistics.A_UNLOAD)
	check(ft.begins_with("Далеко от дороги: погрузка ×") and kf >= 1.5, "у далёкой зоны: «%s»" % ft)
	check(far.logi.far_text(Logistics.A_SHIP).contains("Далеко от дороги") and far.logi.far_hint(Logistics.A_UNLOAD).contains("пешком"), "и у зоны отгрузки; подсказка: %s" % far.logi.far_hint(Logistics.A_UNLOAD))
	check(ft.ends_with("%.1f" % snappedf(kf, 0.1)), "число в подписи — замедление, округлённое до 0.1")

	print("— разгрузка: у дороги и далеко")
	var rn := _unload_run(near)
	var rf := _unload_run(far)
	print("    у дороги: %s\n    далеко: %s" % [str(rn), str(rf)])
	check(rn["err"] == "" and rf["err"] == "", "металл заказан")
	check(float(rn["time"]) > 0.0 and float(rf["time"]) > 0.0, "обе машины разгружены и уехали (%.1f и %.1f мин)" % [float(rn["time"]), float(rf["time"])])
	check(float(rf["time"]) >= float(rn["time"]) * 1.5, "далёкая зона заметно дольше: %.1f против %.1f мин" % [float(rf["time"]), float(rn["time"])])
	check(int(rn["in_zone"]) >= 60 and int(rf["in_zone"]) >= 60, "весь металл в зоне: %d и %d" % [int(rn["in_zone"]), int(rf["in_zone"])])

	print("— груз несут, а не телепортируют")
	check(int(rf["teleports"]) == 0 and int(rn["teleports"]) == 0, "из кузова в зону мимо рук ничто не перелетело")
	check(int(rf["carried"]) > 40 and int(rf["cells"]) >= 8, "груз идёт с грузчиком: %d кл. пути, шагов с грузом %d" % [int(rf["cells"]), int(rf["carried"])])
	check(float(rf["jump"]) <= 1.6, "за полминуты груз смещается не больше чем на клетку (макс. скачок %.2f)" % float(rf["jump"]))
	check(int(rf["crew"]) >= 2 and not bool(rf["hands_ours"]), "носят %d грузчика водителя, наши груз не брали" % int(rf["crew"]))

	print("— грузчики — не персонал")
	var staff_ok := far.workers.is_empty()
	var ids: Array = rf["crew_ids"]
	var not_ours := true
	for id in ids:
		if far.get_worker(int(id)) != null:
			not_ours = false
	check(staff_ok and not_ours and ids.size() >= 2, "в списке работников пусто, грузчиков %d среди работников нет" % ids.size())
	var crew_w: Worker = null
	var g3 := _game(1572)
	_move_zone(g3, Logistics.A_UNLOAD, FAR_UNLOAD)
	g3.money = 900000.0
	g3.order_material("bar45", 30)
	for sp: Dictionary in g3.supply:
		sp["eta"] = g3.minute
	var guard := 0
	var wages0 := g3.workers.size()
	while crew_w == null and guard < 400:
		g3.tick(0.5)
		guard += 1
		for v: Vehicle in g3.vehicles:
			for c: Dictionary in g3.logi.crew_of(v):
				crew_w = c["w"]
	check(crew_w != null and crew_w.visitor and crew_w.prof == "guest" and g3.visitors.has(crew_w) and not g3.workers.has(crew_w) and g3.workers.size() == wages0, "грузчик — гость завода (visitor), не в g.workers")
	check(crew_w != null and crew_w.wage == 0.0 or crew_w != null and not g3.workers.has(crew_w), "зарплата им не идёт")
	g3.dispose()

	print("— погрузка: у дороги и далеко")
	var ln := _game(1573)
	_move_zone(ln, Logistics.A_UNLOAD, NEAR_UNLOAD)
	_move_zone(ln, Logistics.A_SHIP, NEAR_SHIP)
	var lf := _game(1573)
	_move_zone(lf, Logistics.A_UNLOAD, FAR_UNLOAD)
	_move_zone(lf, Logistics.A_SHIP, FAR_SHIP)
	var qn := _load_run(ln)
	var qf := _load_run(lf)
	print("    у дороги: %s\n    далеко: %s" % [str(qn), str(qf)])
	check(bool(qn["done"]) and bool(qf["done"]), "оба заказа отгружены")
	check(float(qf["time"]) >= float(qn["time"]) * 1.5 and float(qn["time"]) > 0.0, "погрузка с далёкой зоны дольше: %.1f против %.1f мин" % [float(qf["time"]), float(qn["time"])])
	check(int(qf["teleports"]) == 0 and int(qf["carried"]) > 20, "детали несут в руках до кузова (шагов с грузом %d, перелётов %d)" % [int(qf["carried"]), int(qf["teleports"])])
	ln.dispose()
	lf.dispose()

	print("— старый сейв грузится, груз в руках не теряется")
	var s := _game(1574)
	_move_zone(s, Logistics.A_UNLOAD, FAR_UNLOAD)
	s.money = 900000.0
	s.order_material("bar45", 60)
	for sp2: Dictionary in s.supply:
		sp2["eta"] = s.minute
	var st := 0.0
	var mid := false
	while st < 300.0 and not mid:
		s.tick(0.5)
		st += 0.5
		for it3: Item in s.items.values():
			if it3.loc == Item.Loc.WORKER:
				mid = true
	check(mid, "в середине разгрузки груз в руках у грузчика")
	var total := 0
	for it4: Item in s.items.values():
		if it4.kind == "mat" and it4.def_id == "bar45":
			total += 1
	var d: Dictionary = JSON.parse_string(JSON.stringify(s.to_dict()))
	var in_veh := 0
	var lost := 0
	for idc: Dictionary in d["items"]:
		if int(idc["loc"]) == Item.Loc.WORKER:
			lost += 1
	for ov: Dictionary in d["vehicles"]:
		check(ov.has("crew_n"), "в сейве у машины есть crew_n")
		ov.erase("crew_n")
		ov.erase("crew_t")
		ov.erase("crew_idle")
		ov.erase("crew_off")
	check(lost == 0, "груз грузчика в сейв пишется не «в руках» (таких записей %d)" % lost)
	var s2 := Sim.from_dict(d)
	var total2 := 0
	for it5: Item in s2.items.values():
		if it5.kind == "mat" and it5.def_id == "bar45":
			total2 += 1
	check(total2 == total, "после загрузки весь металл на месте: %d из %d" % [total2, total])
	var t2 := 0.0
	var gone := false
	while t2 < 900.0:
		s2.tick(0.5)
		t2 += 0.5
		if s2.vehicles.is_empty():
			gone = true
			break
	var z2 := 0
	for it6: Item in s2.items.values():
		if it6.kind == "mat" and it6.def_id == "bar45" and (it6.loc == Item.Loc.THING or (it6.loc == Item.Loc.GROUND and s2.logi.in_zone(it6.cell))):
			z2 += 1
	check(gone and z2 >= 60, "старый сейв доразгружен грузчиками: в зоне %d, машина уехала (%.0f мин)" % [z2, t2])
	check(s2.visitors.is_empty(), "после отъезда грузчиков на экране нет")
	s2.dispose()
	s.dispose()
	near.dispose()
	far.dispose()

	print("")
	if fails.is_empty():
		print("ВСЕ ПРОВЕРКИ ПРОЙДЕНЫ")
	else:
		print("ПРОВАЛЕНО: %d" % fails.size())
		for f in fails:
			print("  - " + f)
	quit(0 if fails.is_empty() else 1)
