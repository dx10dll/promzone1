extends SceneTree
## Тест версии 1.30 «Машины и пожарные»: ночной пожар — вызывают 01, по встречной полосе приезжает
## пожарная машина, трое пожарных выходят, тушат (сила огня падает), возвращаются и машина уезжает;
## сохранение и загрузка посреди тушения. Ломовоз: приезжает за стружкой и браком, водитель
## обходит контейнеры, лом в кузове, оплата, машина уезжает; сохранение посреди погрузки.
## godot --headless --path . -s res://tests/stage130b_test.gd

var fails: Array[String] = []


func check(cond: bool, what: String) -> void:
	print(("  ✓ " if cond else "  ✗ ") + what)
	if not cond:
		fails.append(what)


func run(sim: Sim, minutes: float, stop: Callable = Callable()) -> bool:
	var t := 0.0
	while t < minutes:
		sim.tick(0.5)
		t += 0.5
		if stop.is_valid() and stop.call():
			return true
	return false


func fire_truck(sim: Sim) -> Vehicle:
	for v in sim.vehicles:
		if v.kind == "fire":
			return v
	return null


func scrap_truck(sim: Sim) -> Vehicle:
	for v in sim.vehicles:
		if v.kind == "scrap":
			return v
	return null


func firemen(sim: Sim) -> int:
	var n := 0
	for v in sim.visitors:
		if str(v.get_meta("who", "")) == "Пожарный":
			n += 1
	return n


func power(sim: Sim) -> float:
	var s := 0.0
	for i: int in sim.story.fires.keys():
		s += float(sim.story.fires[i])
	return s


func roundtrip(sim: Sim) -> Sim:
	return Sim.from_dict(JSON.parse_string(JSON.stringify(sim.to_dict())))


func _init() -> void:
	var sim := Scenario.new_garage(777, "market")
	sim.sales.enabled = false
	sim.story.enabled = false   # без случайных событий
	sim.auto_supply = true
	sim.notified.connect(func(t: String, _l: int, _c: Vector2i) -> void:
		print("    [%s %s] %s" % [sim.date_str(), sim.time_str(), t]))

	print("— ночной пожар: людей нет, вызывают пожарных")
	run(sim, 1440.0 - sim.tod() + 120.0)   # ночь на второй день: завод пуст
	check(sim.workers.all(func(w: Worker) -> bool: return not w.present), "ночью на заводе никого (%s)" % sim.time_str())
	var fc := Vector2i(24, 15)
	check(sim.world.passable(fc), "клетка для пожара проходима")
	sim.story.ignite(fc, "Тестовый пожар")
	sim.story.ignite(fc + Vector2i(1, 0), "Тестовый пожар")
	check(sim.story.fires.size() == 2, "загорелось")
	var called := run(sim, 40.0, func() -> bool: return sim.story.brigade.dispatch_at >= 0.0 or fire_truck(sim) != null)
	check(called, "вызвали пожарных через %d мин после начала" % int(sim.minute - sim.story.fire_start))
	var arrived := run(sim, 40.0, func() -> bool: return fire_truck(sim) != null and fire_truck(sim).state == "parked")
	var ft := fire_truck(sim)
	check(arrived and ft != null, "пожарная машина приехала и встала")
	if ft:
		check(ft.lane == 1 and ft.body == "fire" and ft.hold, "по встречной полосе, кузов «fire», ждёт расчёт")
		check(absf(ft.x - FireBrigade.TRUCK_LEN * 0.5 - float(fc.x)) < 4.0, "встала напротив очага (x=%.1f, очаг %d)" % [ft.x, fc.x])
	check(firemen(sim) == FireBrigade.CREW, "из машины вышли пожарные: %d" % firemen(sim))
	var p0 := power(sim)
	var cells0 := sim.story.fires.size()
	var spraying := run(sim, 30.0, func() -> bool:
		for c: Dictionary in sim.story.brigade.crew:
			if str(c["st"]) == "spray":
				return true
		return false)
	check(spraying, "пожарные добежали и тушат из рукава")
	var helm := ""
	for v in sim.visitors:
		if str(v.get_meta("who", "")) == "Пожарный":
			helm = "%s/%s/%s" % [v.look.get("hat", ""), v.look.get("outfit", ""), v.prop]
	check(helm == "helmet/fireman/nozzle", "в каске, боёвке и со стволом: %s" % helm)
	run(sim, 2.0)
	print("    огонь: %d клеток, сила %.2f → %d клеток, сила %.2f" % [cells0, p0, sim.story.fires.size(), power(sim)])

	print("— сохранение посреди тушения")
	var s2 := roundtrip(sim)
	check(fire_truck(s2) != null and firemen(s2) == firemen(sim), "машина и пожарные пережили загрузку (%d)" % firemen(s2))
	check(s2.story.brigade.deployed() and s2.story.brigade.vid == sim.story.brigade.vid, "расчёт на месте после загрузки")
	var out := run(s2, 60.0, func() -> bool: return s2.story.fires.is_empty())
	check(out, "пожар потушен (после загрузки)")
	var gone := run(s2, 60.0, func() -> bool: return fire_truck(s2) == null)
	check(gone, "пожарная машина уехала")
	check(firemen(s2) == 0 and not s2.story.brigade.deployed(), "пожарных на карте не осталось")
	check(s2.inspect.queue.any(func(q: Dictionary) -> bool: return str(q["type"]) == "fire"), "назначена проверка пожарного надзора")
	# и без загрузки — тот же исход
	var out1 := run(sim, 60.0, func() -> bool: return sim.story.fires.is_empty())
	run(sim, 60.0, func() -> bool: return fire_truck(sim) == null)
	check(out1 and fire_truck(sim) == null and firemen(sim) == 0, "без загрузки — тоже потушили и уехали")
	s2.dispose()

	print("— запасной выход: к огню не подойти")
	var sb := Scenario.new_garage(778, "market")
	sb.sales.enabled = false
	sb.story.enabled = false
	run(sb, 1440.0 - sb.tod() + 120.0)
	sb.story.ignite(fc, "Тестовый пожар")
	sb.story.brigade.request()
	run(sb, 30.0, func() -> bool: return fire_truck(sb) != null and fire_truck(sb).state == "parked")
	# ворота закрыли стеной — пройти нельзя
	for x in range(0, sb.world.w):
		var c := Vector2i(x, sb.world.plot.end.y)
		if sb.world.inb(c) and sb.world.passable(c):
			sb.world.wall[sb.world.idx(c)] = World.W_BRICK
	sb.world.refresh_all()
	var ended := run(sb, FireBrigade.MAX_ON_SITE + 30.0, func() -> bool: return sb.story.fires.is_empty())
	check(ended, "пожар всё равно кончился")
	var left := run(sb, 60.0, func() -> bool: return fire_truck(sb) == null)
	check(left and firemen(sb) == 0, "расчёт уехал и без прохода")
	sb.dispose()

	print("— ломовоз")
	var g := Scenario.new_garage(779, "market")
	g.sales.enabled = false
	g.story.enabled = false
	run(g, 1440.0 - g.tod() + 600.0)   # день 2, 10:00
	var bin := g.place_thing("chip_bin", Vector2i(26, 12), true, false)
	g.upkeep.bin_kg[bin.id] = 200.0
	var sbins: Array = g.things.values().filter(func(x: Thing) -> bool: return x.def_id == "scrap_bin")
	if sbins.is_empty():
		sbins.append(g.place_thing("scrap_bin", Vector2i(25, 16), true, false))
	var part := g.new_item("part", "bushing", "scrap")
	g.put_in_thing(part, sbins[0], 0)
	var m0 := g.money
	check(g.upkeep.call_truck(), "ломовоз вызван")
	check(not g.upkeep.call_truck(), "второй не едет, пока первый в пути")
	var parked := run(g, 60.0, func() -> bool: return scrap_truck(g) != null and scrap_truck(g).state == "parked")
	check(parked, "ломовоз встал у ворот")
	check(g.upkeep.driver != null and g.visitors.has(g.upkeep.driver), "водитель вышел из машины")
	var carrying := run(g, 60.0, func() -> bool: return g.upkeep.driver != null and g.upkeep.driver.prop == "chips" and g.upkeep.bin_total() < 1.0)
	check(carrying, "водитель несёт стружку к машине")
	check(g.upkeep.bin_total() < 1.0, "контейнер со стружкой опустел")
	print("— сохранение посреди погрузки")
	var g2 := roundtrip(g)
	check(g2.upkeep.driver != null and not g2.upkeep.run.is_empty() and scrap_truck(g2) != null, "водитель и машина пережили загрузку")
	var paid := run(g2, 90.0, func() -> bool: return g2.upkeep.run.is_empty())
	check(paid and g2.money > m0 + 2000.0, "ломовоз заплатил: %s" % Defs.money_str(g2.money - m0))
	check(not g2.items.has(part.id), "брак увезли")
	check(g2.upkeep.pickups == g.upkeep.pickups + 1 and g2.upkeep.driver == null and not g2.visitors.any(func(v: Worker) -> bool: return str(v.get_meta("who", "")) == "Водитель ломовоза"), "водитель уехал")
	var sv := scrap_truck(g2)
	check(sv != null and sv.state == "leaving" and sv.loaded > 0, "машина с ломом уезжает")
	run(g2, 30.0, func() -> bool: return scrap_truck(g2) == null)
	check(scrap_truck(g2) == null, "ломовоз скрылся за краем карты")
	g2.dispose()
	g.dispose()
	sim.dispose()
	print("РЕЗУЛЬТАТ: ", "OK" if fails.is_empty() else "ОШИБКИ: " + ", ".join(fails))
	quit(0 if fails.is_empty() else 1)
