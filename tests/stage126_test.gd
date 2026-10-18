extends SceneTree
## Тест версии 1.26 «Большой завод»: договор на год (аванс, срывы, неустойка, премия),
## старые здания на купленных участках, одно уведомление на все станки вне цеха, кэш поиска работы.
## godot --headless --path . -s res://tests/stage126_test.gd

const S := preload("res://tests/setups.gd")

var fails: Array[String] = []


func check(cond: bool, what: String) -> void:
	print(("  ✓ " if cond else "  ✗ ") + what)
	if not cond:
		fails.append(what)


func _shop() -> Sim:
	var g := Scenario.new_garage(126)
	g.story.enabled = false
	g.progress.tutorial = -1
	g.bmats.enabled = false
	S.big_shop(g)
	S.hire(g, "turner", "turning", 5)
	S.hire(g, "laborer", "haul", 3)
	return g


func _year(g: Sim) -> Dictionary:
	var c := g.sales._new_contract()
	if c.is_empty():
		return c
	g.sales._make_year(c)
	g.sales.contracts.append(c)
	return c


func _close(g: Sim, c: Dictionary, ok: bool) -> void:
	g.sales.on_order_closed({"contract": int(c["id"]), "price": float(c["price"]), "qty": int(c["per_week"])}, ok)


func _count(g: Sim, part: String) -> int:
	var n := 0
	for e: Dictionary in g.events:
		if str(e["text"]).contains(part):
			n += 1
	return n


func _init() -> void:
	Defs.load_all()

	print("— договор на год")
	var g := _shop()
	g.progress.stage = 3
	g.reputation = 70.0
	check(not g.sales.year_ok(), "до «Среднего предприятия» договора на год нет")
	g.progress.stage = 4
	g.reputation = 40.0
	check(not g.sales.year_ok(), "с низкой репутацией — нет")
	g.reputation = 70.0
	check(g.sales.year_ok(), "большой завод с репутацией — можно")
	var c := _year(g)
	check(not c.is_empty(), "предложение составлено")
	if not c.is_empty():
		check(bool(c["year"]) and int(c["weeks"]) >= 12, "срок — игровой год (%d нед.)" % int(c["weeks"]))
		check(Sales.max_fails(c) == 3 and Sales.max_fails({}) == 2, "годовой терпит два срыва, обычный — один")
		check(float(c["prem"]) < 0.14, "наценка меньше обычной (%d%%)" % int(float(c["prem"]) * 100.0))
		check(g.sales.contract_text(c).contains("аванс"), "в письме — про аванс и неустойку")
		check(not g.sales.year_ok(), "второй договор на год, пока есть первый, не предложат")
		var m0 := g.money
		check(g.sales.sign(int(c["id"])) == "", "подписан")
		check(absf(g.money - m0 - Sales.total(c) * 0.1) < 2.0, "аванс 10%% пришёл (%s)" % Defs.money_str(Sales.total(c) * 0.1))
		var r0 := g.reputation
		_close(g, c, false)
		_close(g, c, false)
		check(str(c["status"]) != "broken", "два срыва — договор ещё в силе")
		var m1 := g.money
		_close(g, c, false)
		check(str(c["status"]) == "broken", "третий срыв — расторгнут")
		check(g.reputation <= r0 - 15.0, "репутация сильно упала")
		check(g.money < m1 - float(c["price"]) * int(c["per_week"]) * 0.3, "неустойка сверх штрафа за партию")

		print("— договор выполнен")
		g.reputation = 70.0
		var c2 := _year(g)
		check(not c2.is_empty(), "новый договор на год после расторжения")
		if not c2.is_empty():
			c2["weeks"] = 3
			g.sales.sign(int(c2["id"]))
			var m2 := g.money
			for i in 3:
				_close(g, c2, true)
			check(str(c2["status"]) == "done", "все партии сданы — выполнен")
			check(g.money > m2 + Sales.total(c2) * 0.07, "премия 8%")
			check(int(g.stats.get("year_contracts_done", 0)) == 1, "счётчик выполненных договоров на год")
		var again := Sim.from_dict(JSON.parse_string(JSON.stringify(g.to_dict())))
		check(again.sales.contracts.size() == g.sales.contracts.size(), "договоры сохраняются")

	print("— старые здания на соседних участках")
	var f := Scenario.new_game("garage", "mech", "calm", 126, {"lots": true, "flora": true})
	f.story.enabled = false
	f.money = 50000000.0
	check(f.world.lots.size() >= 3, "соседних участков: %d" % f.world.lots.size())
	var built := 0
	for k in mini(3, f.world.lots.size()):
		var b := OldBuild.plan(f, k)
		var nt := f.things.size()
		check(f.buy_lot(k), "участок %d куплен" % k)
		var walls := 0
		var gates := 0
		for y in range(b.position.y, b.end.y):
			for x in range(b.position.x, b.end.x):
				var wv := f.world.wall[f.world.idx(Vector2i(x, y))]
				if wv == World.W_BRICK:
					walls += 1
				elif wv == World.W_GATE:
					gates += 1
		if walls > 10:
			built += 1
		check(walls > 10 and (gates > 0 or k == 1), "%s: стены и ворота (%d / %d)" % [OldBuild.NAMES[k], walls, gates])
		check(f.things.size() > nt, "%s: остались вещи прежних хозяев" % OldBuild.NAMES[k])
		check(str(f.events[0]["text"]).contains(OldBuild.NAMES[k]), "в сообщении о покупке названо здание")
	check(built == mini(3, f.world.lots.size()), "на каждом участке своё здание")
	var t0 := f.minute
	while f.minute < t0 + 600.0:
		f.tick(0.5)
	check(is_finite(f.money), "завод со старыми зданиями живёт")
	var f2 := Sim.from_dict(JSON.parse_string(JSON.stringify(f.to_dict())))
	check(f2.things.size() == f.things.size(), "старые здания сохраняются")

	print("— одно уведомление на все станки вне цеха")
	var h := _shop()
	var out := 0
	for yy in range(22, 26):
		for xx in range(14, 27):
			h.world.flr[h.world.idx(Vector2i(xx, yy))] = 1
	h.world.refresh_all()
	for x in [15, 18, 21, 24]:
		var why := h.can_place("drill", Vector2i(x, 23))
		if why == "" or why.begins_with("Нужна ступень"):
			h.place_thing("drill", Vector2i(x, 23), true, false)
			out += 1
		else:
			print("    (", x, ": ", why, ")")
	Scenario.autowire(h)
	h.power.update_topology()
	h.power.tick(0.1)
	for m in h.things_of("machine"):
		m.product = "bracket"
	h.events.clear()
	h.brain._ready_machines(h.things_of("machine"))
	h.minute += 1.0
	h.brain._ready_machines(h.things_of("machine"))
	var nz := _count(h, "вне цеха")
	check(out >= 2 and nz == 1, "станков вне цеха %d — уведомлений %d" % [out, nz])

	print("— кэш поиска работы")
	var u := _shop()
	var a := u.usable_of("machine")
	check(a == u.usable_of("machine"), "в пределах шага список тот же")
	var nm := a.size()
	u.place_thing("lathe", Vector2i(31, 17), true, false)
	check(u.usable_of("machine").size() == nm + 1, "новый станок сразу виден")
	var t2 := u.minute
	while u.minute < t2 + 240.0:
		u.tick(0.5)
	var made := 0
	for m in u.things_of("machine"):
		made += m.parts_made
	check(is_finite(u.money), "завод работает с кэшем")

	print("")
	if fails.is_empty():
		print("РЕЗУЛЬТАТ: OK")
	else:
		print("РЕЗУЛЬТАТ: ОШИБКИ (%d)" % fails.size())
		for ff in fails:
			print("  - " + ff)
	quit(0 if fails.is_empty() else 1)
