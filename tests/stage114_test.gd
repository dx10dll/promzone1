extends SceneTree
## Тест версии 1.14 «Живой завод»: тяжёлые детали краном или волоком, разные машины, душевая,
## инспектора сопровождают, инструктаж у доски, разговоры, ругань и драки.
## godot --headless --path . -s res://tests/stage114_test.gd

const S := preload("res://tests/setups.gd")

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
		if until.is_valid() and bool(until.call()):
			break
	return t


func _init() -> void:
	Defs.load_all()

	print("— тяжёлые детали: краном или волоком")
	var g := Scenario.new_game("garage", "mech", "calm", 141)
	g.story.enabled = false
	S.big_shop(g)
	var heavy := ""
	for p in Defs.products.keys():
		if bool(Defs.products[p].get("heavy", false)):
			heavy = str(p)
			break
	check(heavy != "", "есть тяжёлые изделия: %s" % heavy)
	var it := g.new_item("part", heavy, "ok")
	check(g.brain.carry_cap(it) == 1, "тяжёлую деталь несут по одной")
	var pal: Thing = null
	for t: Thing in g.things.values():
		if t.def_id == "pallet" and g.rooms.space_id_at(t.cell) == g.rooms.space_id_at(Vector2i(37, 10)):
			pal = t
			break
	g.put_on_ground(it, Vector2i(33, 16))
	var w0: Worker = g.workers[0]
	w0.present = true
	w0.dressed = true
	w0.pos = Vector2(34.5, 16.5)
	var tk := g.brain._make_task(w0, {"k": "haul", "item": it, "dest": pal, "slot": 0})
	check(tk != null and str(tk.data.get("prop", "")) == "pendant" and tk.label.begins_with("Ведёт краном"), "в зале с кран-балкой деталь ведут краном: «%s»" % (tk.label if tk else "—"))
	g.brain.abort(w0)
	var it2 := g.new_item("part", heavy, "ok")
	var outside := g.world.nearest_passable(Vector2i(26, 15))
	g.put_on_ground(it2, outside)
	var w1: Worker = g.workers[1]
	w1.present = true
	w1.pos = Vector2(outside) + Vector2(0.5, 0.5)
	var tk2 := g.brain._make_task(w1, {"k": "haul", "item": it2, "dest": pal, "slot": 0})
	check(tk2 != null and tk2.label.begins_with("Тащит") and str(tk2.data.get("prop", "")) != "pendant", "без крана — тащат волоком: «%s»" % (tk2.label if tk2 else "—"))
	g.brain.abort(w1)

	print("— разные машины")
	var v := Scenario.new_game("garage", "mech", "calm", 142)
	v.story.enabled = false
	v.money = 5000000.0
	v.order_material("bar45", 30)
	v.order_material("hex27", 4)
	var bodies := {}
	run(v, 900.0, func() -> bool:
		for vh in v.vehicles:
			bodies[vh.body] = true
		return false)
	check(bodies.has("truck"), "большую партию металла привёз грузовик (%s)" % str(bodies.keys()))
	var o := v.orders.make_offer("bushing")
	o["kind"] = "export"
	o["status"] = "ready"
	o["pickup_eta"] = v.minute - 300.0   # 1.56: машина приезжает к собранному поддону; здесь поддона нет — срок комплектации вышел
	o["pickup_spawned"] = false
	v.orders.list.append(o)
	v.orders.tick(1.0)
	var semi := false
	for vh2 in v.vehicles:
		if vh2.kind == "pickup" and vh2.body == "semi":
			semi = true
	check(semi, "экспортную партию забирает фура")

	print("— душевая")
	var d := Scenario.new_game("sandbox", "mech", "calm", 143, {"money": 5000000, "all_open": true})
	d.story.enabled = false
	S._box(d, Rect2i(10, 3, 6, 5), 2, Vector2i(12, 7))
	d.rooms.update()
	var sh := d.place_thing("shower", Vector2i(11, 4), true, false)
	d.place_thing("sink", Vector2i(13, 4), true, false)
	d.place_thing("water_inlet", Vector2i(9, 8), true, false)
	for x in range(9, 15):
		d.world.pipe[d.world.idx(Vector2i(x, 8))] = 1
	for y in range(5, 9):
		d.world.pipe[d.world.idx(Vector2i(12, y))] = 1
	d.world.pipe[d.world.idx(Vector2i(11, 5))] = 1
	d.world.pipe[d.world.idx(Vector2i(13, 5))] = 1
	d.world.pipe[d.world.idx(Vector2i(11, 4))] = 1   # 1.18: труба заходит в клетку прибора
	d.world.pipe[d.world.idx(Vector2i(13, 4))] = 1
	d.world.pipe_rev += 1
	d.rooms.fill(Vector2i(12, 5), "shower")
	d.rooms.update()
	check(d.rooms.room_at(Vector2i(12, 5)).type == "shower" and d.rooms.room_at(Vector2i(12, 5)).valid, "душевая оборудована")
	check(d.water.has_water(sh) and d.rooms.zone_ok(sh), "у кабины вода, она в своей зоне")
	var bw: Worker = d.workers[0]
	bw.present = true
	bw.dressed = true
	bw.pos = Vector2(14.5, 10.5)
	d.brain._go_home(bw)
	check(bw.task.label.begins_with("Моется"), "после смены — в душ: «%s»" % bw.task.label)
	run(d, 60.0, func() -> bool: return bw.thoughts.any(func(x: Dictionary) -> bool: return str(x["id"]) == "showered"))
	check(bw.thoughts.any(func(x: Dictionary) -> bool: return str(x["id"]) == "showered"), "помылся — доволен")
	var nw: Worker = d.workers[1]
	nw.present = true
	nw.dressed = true
	d.place_thing("pallet", Vector2i(11, 4), false, false)
	sh.spot_users[0] = 999
	d.brain._go_home(nw)
	check(nw.thoughts.any(func(x: Dictionary) -> bool: return str(x["id"]) == "no_shower"), "кабина занята — ушёл грязным")

	print("— инспектор и сопровождающий")
	var ins := Scenario.new_game("garage", "mech", "calm", 144)
	ins.story.enabled = false
	ins.money = 3000000.0
	var fm := Scenario.hire_prof(ins, "foreman", 4, 6)
	fm.present = true
	fm.dressed = true
	fm.pos = Vector2(20.5, 14.5)
	ins.minute = 1440.0 + 10.0 * 60.0
	ins.inspect.schedule("fire", ins.minute, true)
	var esc := {"w": null}
	run(ins, 120.0, func() -> bool:
		var e: Worker = ins.inspect.escort()
		if e and e.task and e.task.kind == "escort":
			esc["w"] = e
		return esc["w"] != null)
	var ew: Worker = esc["w"]
	check(ew != null, "начальник бросил дела и сопровождает инспектора: %s" % (ew.prof if ew else "—"))
	var v2 := ins.inspect.visitor()
	run(ins, 20.0)
	check(v2 != null and ew != null and ew.pos.distance_to(v2.pos) < 3.5, "идёт рядом (%.1f кл.)" % (ew.pos.distance_to(v2.pos) if v2 and ew else -1.0))

	print("— инструктаж у доски")
	var tb := Scenario.new_game("garage", "mech", "calm", 145)
	tb.story.enabled = false
	tb.money = 3000000.0
	var lead := Scenario.hire_prof(tb, "foreman", 4, 6)
	for wk in tb.workers:
		wk.present = true
		wk.dressed = true
	lead.pos = Vector2(20.5, 12.5)
	tb.minute = 1440.0 + 9.0 * 60.0
	check(tb.training.start_tb() == "", "инструктаж начат")
	check(tb.training.tb_lead() == lead, "ведёт мастер")
	var spot := tb.training.tb_spot()
	check(spot.x >= 0, "место у доски: %s" % str(spot))
	var seen := {"brief": false, "study": 0}
	run(tb, 60.0, func() -> bool:
		if lead.task and lead.task.kind == "brief":
			seen["brief"] = true
		var n := 0
		for wk2 in tb.workers:
			if wk2.task and wk2.task.kind == "study":
				n += 1
		seen["study"] = maxi(int(seen["study"]), n)
		return bool(seen["brief"]) and int(seen["study"]) >= 2)
	check(bool(seen["brief"]), "мастер стоит у доски и рассказывает")
	check(int(seen["study"]) >= 2, "слушают сразу несколько человек (%d)" % int(seen["study"]))

	print("— разговоры, ругань, драка")
	var so := Scenario.new_game("garage", "mech", "calm", 146)
	so.story.enabled = false
	var a: Worker = so.workers[0]
	var b: Worker = so.workers[2]
	for p2 in [a, b]:
		p2.present = true
		p2.dressed = true
	a.pos = Vector2(20.5, 12.5)
	b.pos = Vector2(22.5, 12.5)
	var r0 := so.training.rel(a, b)
	so.social.start(a, b, "chat")
	check(a.task.kind == "social" and b.task.label.begins_with("Болтает"), "болтают: «%s»" % b.task.label)
	run(so, 15.0, func() -> bool: return so.social.events.is_empty())
	check(so.training.rel(a, b) > r0, "поболтали — сдружились (%.0f → %.0f)" % [r0, so.training.rel(a, b)])
	so.training._add_rel(a, b, -80.0)
	so.social.start(a, b, "argue")
	check(a.bubble == "argue", "ругаются — значок над головой")
	run(so, 10.0, func() -> bool: return so.social.events.is_empty())
	check(a.thoughts.any(func(x: Dictionary) -> bool: return str(x["id"]) == "argued"), "после ругани настроение хуже")
	var letters0 := so.story.letters.size()
	so.social.last_fight = -99999.0
	so.social.start(a, b, "fight")
	check(a.task.label.begins_with("Дерётся") and a.bubble == "fight", "дерутся")
	run(so, 10.0, func() -> bool: return so.social.events.is_empty())
	check(so.story.letters.size() > letters0 and str(so.story.letters[-1]["ev"]) == "fight", "после драки — решение директора")
	check(int(so.stats.get("fights", 0)) >= 1, "драка записана: %d" % int(so.stats.get("fights", 0)))
	so.story.resolve(int(so.story.letters[-1]["id"]), 2)

	print("— поток: разговоры возникают сами")
	var fl := Scenario.new_game("garage", "mech", "calm", 147)
	fl.story.enabled = false
	S.big_shop(fl)
	fl.minute = 1440.0 + 7.0 * 60.0
	var cnt := {"chat": 0, "inplace": 0, "seen": {}}
	run(fl, 1440.0, func() -> bool:
		for e: Dictionary in fl.social.events:
			var key := "%d-%d-%d" % [int(e["a"]), int(e["b"]), int(float(e["end"]))]
			if str(e["kind"]) == "chat" and not cnt["seen"].has(key):
				cnt["seen"][key] = true
				cnt["chat"] += 1
				if bool(e.get("inplace", false)):
					cnt["inplace"] += 1
		return false)
	check(int(cnt["chat"]) >= 2, "за день люди сами болтают: %d раз, из них за столом или в курилке %d" % [int(cnt["chat"]), int(cnt["inplace"])])

	print("РЕЗУЛЬТАТ: " + ("OK" if fails.is_empty() else "ОШИБКИ: " + ", ".join(fails)))
	quit(0 if fails.is_empty() else 1)
