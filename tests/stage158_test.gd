extends SceneTree
## Тест 1.58 «Логистика, этапы 2–3»: расписание машин (кто и когда приедет сегодня и завтра, машины приезжают в это время)
## и буфер «держать N заготовок у станка» (разнорабочие держат запас рядом со станком, станочник при разнорабочем не носит,
## старый сейв грузится с «как раньше»).
## godot --headless --path . --audio-driver Dummy -s res://tests/stage158_test.gd

const S := preload("res://tests/setups.gd")

var fails: Array[String] = []


func check(cond: bool, what: String) -> void:
	print(("  ✓ " if cond else "  ✗ ") + what)
	if not cond:
		fails.append(what)


func _game(seed_v: int) -> Sim:
	var g := Scenario.new_game("garage", "mech", "calm", seed_v)
	g.story.enabled = false
	g.progress.tutorial = -1
	g.bmats.enabled = false
	return g


func _veh(g: Sim, kind: String) -> Vehicle:
	for v: Vehicle in g.vehicles:
		if v.kind == kind:
			return v
	return null


## Цех с одним токарным станком (38,5) под заказ на штифты: токарь, при want_lab — разнорабочий, 40 прутков на полу.
func _shop(seed_v: int, n: int, want_lab: bool) -> Dictionary:
	var g := _game(seed_v)
	S.big_shop(g, false)
	for o0: Dictionary in g.orders.list.duplicate():
		g.orders.list.erase(o0)
	for w0: Worker in g.workers.duplicate():
		if w0.prof == "laborer":
			g.workers.erase(w0)
	var tw := S.hire(g, "turner", "turning", 6)
	var lab: Worker = S.hire(g, "laborer", "haul", 7) if want_lab else null
	for w: Worker in g.workers:
		w.present = true
		w.pos = Vector2(34.5, 14.5)
	for m0: Thing in g.things_of("machine"):
		if m0.def_id == "lathe" and m0.cell != Vector2i(38, 5):
			m0.enabled = false
	var m: Thing = null
	for m1: Thing in g.things_of("machine"):
		if m1.def_id == "lathe" and m1.cell == Vector2i(38, 5):
			m = m1
	var o := g.orders.make_offer("pin")
	o["qty"] = 200
	o["status"] = "offer"
	g.orders.list.append(o)
	g.orders.accept(int(o["id"]), true)
	var pals: Array[Thing] = []
	for pc in [Vector2i(33, 17), Vector2i(35, 17)]:
		pals.append(g.place_thing("pallet_raw", pc, true, false))
	for i in 40:
		g.put_in_thing(g.new_item("mat", "bar45", "raw"), pals[i % 2], 0)   # металл лежит на поддонах заготовок, не на полу
	for k in 20:
		g.tick(0.5)   # станку назначают изделие
	return {"g": g, "m": m, "turner": tw, "lab": lab}


func _initialize() -> void:
	Defs.load_all()

	print("— расписание: металл")
	var g := _game(1581)
	g.money = 900000.0
	check(g.order_material("bar45", 20) == "", "металл заказан")
	var sp: Dictionary = g.supply[0]
	sp["eta"] = g.minute + 90.0
	g.order_material("bar45", 8)
	g.supply[1]["eta"] = (g.day() + 3) * 1440.0 + 600.0   # через три дня — в «сегодня и завтра» не попадает
	var sch := g.logi.schedule()
	var metal := sch.filter(func(e: Dictionary) -> bool: return e["kind"] == "metal")
	check(metal.size() == 1 and absf(float(metal[0]["t"]) - float(sp["eta"])) < 0.01 and str(metal[0]["text"]).contains("металл"), "в расписании одна машина с металлом на %s: «%s»" % [g.logi.when_text(float(sp["eta"])), str(metal[0]["text"]) if not metal.is_empty() else ""])
	check(g.logi.when_text(float(sp["eta"])).begins_with("сегодня ") and g.logi.when_text(g.minute + 1440.0).begins_with("завтра "), "время подписано: «сегодня hh:mm» / «завтра hh:mm»")
	var arrive := -1.0
	var spawned := -1.0
	var t := 0.0
	while t < 400.0 and arrive < 0.0:
		g.tick(0.5)
		t += 0.5
		var v := _veh(g, "delivery")
		if v and spawned < 0.0:
			spawned = g.minute
		if v and v.state == "parked":
			arrive = g.minute
	var eta0 := float(sp["eta"])
	print("    срок %.1f, выехала %.1f, встала у ворот %.1f" % [eta0, spawned, arrive])
	check(spawned >= eta0 and spawned - eta0 <= 2.0, "машина выехала в назначенное время (%.1f мин после срока)" % (spawned - eta0))
	check(arrive >= eta0 and arrive - eta0 <= 15.0, "и встала у ворот не позже чем через 15 мин (%.1f)" % (arrive - eta0))
	var sch2 := g.logi.schedule()
	check(sch2.any(func(e: Dictionary) -> bool: return bool(e["here"])) and not sch2.any(func(e: Dictionary) -> bool: return e["kind"] == "metal" and absf(float(e["t"]) - eta0) < 1.0), "машина у ворот в списке как «на воротах», из будущих убрана")
	g.dispose()

	print("— расписание: клиент за заказом, оборудование, порядок")
	var p := _game(1582)
	p.money = 900000.0
	var o := p.orders.make_offer("pin")
	o["qty"] = 10
	o["status"] = "offer"
	p.orders.list.append(o)
	p.orders.accept(int(o["id"]), false)
	var cell: Vector2i = p.logi.ship_cells()[0]
	for i in 10:
		var it := p.new_item("part", "pin", "ok")
		it.ord_id = int(o["id"])
		p.put_on_ground(it, cell)
	p.orders._t = 0.0
	p.orders.tick(1.0)
	check(str(o["status"]) == "ready", "заказ готов")
	o["pickup_eta"] = p.minute + 120.0
	p.supply.append({"id": p.new_id(), "mat": "bar45", "qty": 12, "eta": p.minute + 60.0, "spawned": false, "done": false})
	p.logi.equip.append({"id": p.new_id(), "thing": -1, "def": "bench", "eta": p.minute + 240.0, "spawned": false})
	var s3 := p.logi.schedule()
	var kinds: Array = s3.map(func(e: Dictionary) -> String: return str(e["kind"]))
	check(kinds == ["metal", "pickup", "equip"], "по времени: металл, клиент, оборудование (%s)" % str(kinds))
	var pk: Dictionary = s3[1]
	check(str(pk["text"]).contains("забирает заказ №%d" % p.orders.num(o)), "клиент: «%s»" % str(pk["text"]))
	var arr2 := -1.0
	var t2 := 0.0
	while t2 < 600.0 and arr2 < 0.0:
		p.tick(0.5)
		t2 += 0.5
		var v2 := _veh(p, "pickup")
		if v2 and v2.state == "parked":
			arr2 = p.minute
	var pe := float(pk["t"])
	print("    клиент: срок %.1f, у ворот %.1f" % [pe, arr2])
	check(arr2 >= pe and arr2 - pe <= 15.0, "машина клиента приехала в назначенное время (+%.1f мин)" % (arr2 - pe))
	p.dispose()

	print("— старый сейв с полем «buf» (1.59: буфер убран, поле игнорируется)")
	var sv := _shop(1585, 0, true)
	var sg: Sim = sv["g"]
	var d: Dictionary = JSON.parse_string(JSON.stringify(sg.to_dict()))
	for td: Dictionary in d["things"]:
		td["buf"] = 7
	var s5 := Sim.from_dict(d)
	for k in 40:
		s5.tick(0.5)
	check(s5.logi.schedule() is Array, "старый сейв с «buf» грузится и идёт дальше, расписание строится")
	s5.dispose()
	sg.dispose()

	print("")
	if fails.is_empty():
		print("ВСЕ ПРОВЕРКИ ПРОЙДЕНЫ")
	else:
		print("ПРОВАЛЕНО: %d" % fails.size())
		for f in fails:
			print("  - " + f)
	quit(0 if fails.is_empty() else 1)
