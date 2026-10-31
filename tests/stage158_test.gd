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
	if n > 0:
		g.logi.set_buffer(m, n)
	return {"g": g, "m": m, "turner": tw, "lab": lab}


func _near_items(g: Sim, m: Thing, r: int) -> int:
	var n := 0
	var rect := m.rect().grow(r)
	for gid in g.ground_items:
		var it: Item = g.items.get(gid)
		if it and it.kind == "mat" and rect.has_point(it.cell):
			n += 1
	return n


## 150 минут работы цеха: максимум заготовок на буферной клетке и «у станка», сколько раз станочник носил на клетку.
func _run_shop(d: Dictionary) -> Dictionary:
	var g: Sim = d["g"]
	var m: Thing = d["m"]
	var tw: Worker = d["turner"]
	var lab: Worker = d["lab"]
	var max_near := 0
	var max_held := 0
	var held_end := 0
	var sum_held := 0
	var n_held := 0
	var tw_cell := 0
	var lab_cell := 0
	var t := 0.0
	while t < 150.0:
		g.tick(0.5)
		t += 0.5
		max_near = maxi(max_near, _near_items(g, m, 2))
		max_held = maxi(max_held, g.logi.buffer_held(m))
		if t > 60.0:
			sum_held += g.logi.buffer_held(m)
			n_held += 1
		if tw.task and tw.task.kind == "haul_cell":
			tw_cell += 1
		if lab and lab.task and lab.task.kind == "haul_cell" and g.logi.is_buffer_cell(_dest_of(lab)):
			lab_cell += 1
	held_end = g.logi.buffer_held(m)
	return {"near": max_near, "held": max_held, "held_end": held_end, "avg": float(sum_held) / maxf(1.0, float(n_held)), "tw_cell": tw_cell, "lab_cell": lab_cell}


func _dest_of(w: Worker) -> Vector2i:
	for tl: Dictionary in w.task.toils:
		if str(tl.get("t", "")) == "drop":
			return tl["cell"]
	return Vector2i(-1, -1)


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

	print("— буфер: разнорабочие держат N заготовок у станка")
	var base := _shop(1583, 0, true)
	var rb := _run_shop(base)
	var bm: Thing = base["m"]
	check(bm.buffer == 0 and (base["g"] as Sim).logi.buffer_cell_of(bm).x < 0, "по умолчанию «авто» (0): буферной клетки нет")
	var buf := _shop(1583, 6, true)
	var bg: Sim = buf["g"]
	var bmm: Thing = buf["m"]
	var bc := bg.logi.buffer_cell_of(bmm)
	check(bc.x >= 0 and bmm.rect().grow(2).has_point(bc) and not bmm.spots().any(func(s: Dictionary) -> bool: return s["cell"] == bc), "буферная клетка рядом со станком, не на рабочем месте: %s" % str(bc))
	var rn := _run_shop(buf)
	print("    без буфера: %s\n    N=6: %s" % [str(rb), str(rn)])
	check(int(rb["near"]) == 0, "без настройки у станка заготовки на полу не копятся (макс. %d)" % int(rb["near"]))
	check(int(rn["near"]) >= 3 and int(rn["held"]) >= 6, "N=6: у станка накопилось %d заготовок на клетке, всего «у станка» до %d" % [int(rn["near"]), int(rn["held"])])
	check(float(rn["avg"]) >= 3.5 and float(rn["avg"]) > float(rb["avg"]) + 1.5, "и запас держится: в среднем у станка %.1f заготовок против %.1f без настройки" % [float(rn["avg"]), float(rb["avg"])])
	check(int(rn["lab_cell"]) > 0, "заготовки на клетку носит разнорабочий (%d шагов)" % int(rn["lab_cell"]))
	check(int(rn["tw_cell"]) == 0 and int(rb["tw_cell"]) == 0, "станочник при разнорабочем на клетку не носит (%d раз)" % int(rn["tw_cell"]))
	var b0 := bg.get_worker((buf["turner"] as Worker).id)
	check(b0 != null, "токарь на месте")
	bg.dispose()
	(base["g"] as Sim).dispose()

	print("— буфер: без разнорабочего станочник носит сам (правило 1.56 держится только при разнорабочем)")
	var nl := _shop(1584, 6, false)
	var rnl := _run_shop(nl)
	print("    без разнорабочего: %s" % str(rnl))
	check(int(rnl["tw_cell"]) > 0 or int(rnl["near"]) > 0, "без разнорабочего станочник сам подтягивает запас (шагов %d, на клетке до %d)" % [int(rnl["tw_cell"]), int(rnl["near"])])
	(nl["g"] as Sim).dispose()

	print("— старый сейв и сохранение настройки")
	var sv := _shop(1585, 7, true)
	var sg: Sim = sv["g"]
	var d: Dictionary = JSON.parse_string(JSON.stringify(sg.to_dict()))
	var s4 := Sim.from_dict(d)
	var got := -1
	for tt: Thing in s4.things.values():
		if tt.def_id == "lathe" and tt.cell == Vector2i(38, 5):
			got = tt.buffer
	check(got == 7, "настройка «держать 7» сохраняется (после загрузки %d)" % got)
	s4.dispose()
	for td: Dictionary in d["things"]:
		td.erase("buf")
	var s5 := Sim.from_dict(d)
	var bad := 0
	for t5: Thing in s5.things.values():
		if t5.buffer != 0:
			bad += 1
	check(bad == 0, "в старом сейве поля нет: у всех станков «авто» (0)")
	for k in 40:
		s5.tick(0.5)
	check(s5.logi.schedule() is Array, "старый сейв идёт дальше, расписание строится")
	s5.dispose()
	sg.dispose()
	check(Logistics.BUFFER_MAX >= 24, "предел настройки — пачка на клетку (%d)" % Logistics.BUFFER_MAX)

	print("")
	if fails.is_empty():
		print("ВСЕ ПРОВЕРКИ ПРОЙДЕНЫ")
	else:
		print("ПРОВАЛЕНО: %d" % fails.size())
		for f in fails:
			print("  - " + f)
	quit(0 if fails.is_empty() else 1)
