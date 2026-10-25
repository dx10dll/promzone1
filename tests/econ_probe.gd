extends SceneTree
## 1.39: замер начала игры. Играет первые дни каждого сценария «как обычный игрок»: строит
## готовые помещения (цех 10×6, раздевалка, туалет; в гараже ещё и склад 6×4 из обучения),
## покупает базовые объекты (стеллаж, верстак, недорогой станок), нанимает людей под станок,
## заказы берёт сбыт сам. Печатает деньги по дням, траты по статьям, день ухода в минус и день
## первой оплаты. Функцию run() использует регрессионный тест stage139_test.
## godot --headless --path . --audio-driver Dummy -s res://tests/econ_probe.gd -- [дней] [сид] [режимы,через,запятую] [build|nobuild] [сценарии]
## (Недельные статьи с ботом-директором — tests/econ_weeks.gd.)
## 1.40: режим «завод» — … -- [дней] [сид] [режимы] plant: цех этапа 3 с доп. станками, заводоуправление и
## 30–40 человек (станочники, ИТР, обслуга); заказы берутся, пока успеваем. Печатает недельные статьи и итог
## (run_plant(), им пользуется тест stage140f2_test).

const SCNS := ["garage", "field", "sandbox"]
const MODES := ["calm", "market", "wild"]


## Свободное место под шаблон: контур и клетка вокруг на участке, без стен, объектов, зон и чертежей,
## не на проезде от ворот. Ближайшее к anchor.
static func find_spot(sim: Sim, tid: String, anchor: Vector2) -> Vector2i:
	var w := sim.world
	var s := Templates.size(tid)
	var lane := Rect2i(sim.gate_x - 2, w.plot.position.y, 8, w.plot.size.y)
	var best := Vector2i(-1, -1)
	var bd := INF
	for y in range(w.plot.position.y + 1, w.plot.end.y - s.y - 2):
		for x in range(w.plot.position.x + 1, w.plot.end.x - s.x - 1):
			var r := Rect2i(x, y, s.x, s.y)
			var d := (Vector2(r.get_center()) - anchor).length_squared()
			if d >= bd or r.intersects(lane):
				continue
			if not _free(sim, r.grow(1)):
				continue
			if Templates.check(sim, tid, r.position) != "":
				continue
			bd = d
			best = r.position
	return best


static func _free(sim: Sim, r: Rect2i) -> bool:
	var w := sim.world
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			var c := Vector2i(x, y)
			if not w.in_plot(c):
				return false
			var i := w.idx(c)
			if w.wall[i] != World.W_NONE or w.occ[i] >= 0 or w.area[i] != 0 or sim.bp_cells.has(i):
				return false
			if w.bp_floor[i] != World.BP_NONE or w.bp_wall[i] != World.BP_NONE or sim.plan.ok_zones.has(i):
				return false
	return true


## Поставить шаблон у anchor. Возвращает начало контура или (-1,-1).
static func put_template(sim: Sim, tid: String, anchor: Vector2, log: Array) -> Vector2i:
	var o := find_spot(sim, tid, anchor)
	if o.x < 0:
		log.append("нет места под %s" % tid)
		return o
	var cost := Templates.cost(sim, tid, o)
	var err := Templates.place(sim, tid, o)
	log.append("%s в %s: %s (%s)" % [str(Defs.templates[tid]["name"]), str(o), Defs.money_str(cost), "ok" if err == "" else err])
	return o if err == "" else Vector2i(-1, -1)


## Купить объект в первой свободной клетке прямоугольника (внутри помещения).
static func buy_in(sim: Sim, def_id: String, r: Rect2i, log: Array) -> bool:
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			var c := Vector2i(x, y)
			if sim.can_place(def_id, c) == "":
				var cost := sim.thing_cost(def_id)
				if not sim.can_afford(cost):
					log.append("не хватает на %s (%s)" % [def_id, Defs.money_str(cost)])
					return false
				sim.place_thing(def_id, c, false, true)
				log.append("куплен %s за %s" % [str(Defs.objects[def_id]["name"]), Defs.money_str(cost)])
				return true
	log.append("нет места под %s" % def_id)
	return false


static func _cand(sim: Sim, prof: String) -> int:
	for i in sim.candidates.size():
		if str((sim.candidates[i] as Dictionary).get("prof", "")) == prof:
			return i
	return -1


static func hire_prof(sim: Sim, prof: String, log: Array) -> void:
	var idx := _cand(sim, prof)
	if idx < 0:
		sim.post_ad(prof)
		idx = _cand(sim, prof)
	if idx < 0 and not sim.candidates.is_empty():
		idx = 0
	if idx < 0:
		log.append("некого нанять (%s)" % prof)
		return
	var nm := str(Worker.PROF_NAMES.get(str((sim.candidates[idx] as Dictionary).get("prof", "")), "?"))
	var err := sim.hire(idx)
	log.append("нанят: %s%s" % [nm, "" if err == "" else " — " + err])


## Сыграть сценарий. Возвращает {money: [на утро каждого дня], cats, neg_day, first_pay, min, log, start, staff, done}.
static func run(scn: String, mode: String, seed_value: int, days: int, build: bool = true) -> Dictionary:
	var sim := Scenario.new_game(scn, "mech", mode, seed_value, {"tutorial": scn == "garage", "money": 1000000, "lots": true, "flora": true})
	sim.progress.tutorial = -1   # подсказки не нужны, стройку обучения повторяем руками
	var log: Array = []
	var start := sim.money
	var anchor := Vector2(Scenario.GARAGE.get_center()) if scn == "garage" else Vector2(sim.world.plot.get_center())
	if scn == "field":
		anchor = Vector2(16, 20)
	var shop_o := Vector2i(-1, -1)
	if build:
		if scn == "garage":
			# обучение: стеллаж в гараже и «Склад 6×4», найм одного человека
			buy_in(sim, "rack", Rect2i(Scenario.GARAGE.position + Vector2i(1, 1), Scenario.GARAGE.size - Vector2i(2, 2)), log)
			put_template(sim, "storage", anchor, log)
			hire_prof(sim, "laborer", log)
		shop_o = put_template(sim, "workshop", anchor, log)
		put_template(sim, "locker", anchor, log)
		put_template(sim, "wc", anchor, log)
	var money_days: Array = [sim.money]
	var neg_day := -1
	var first_pay := -1
	var mn := sim.money
	var last := sim.day()
	var bought := false
	while sim.day() <= days:
		sim.tick(0.5)
		mn = minf(mn, sim.money)
		if sim.money < 0.0 and neg_day < 0:
			neg_day = sim.day()
		if first_pay < 0 and _sales(sim) > 0.0:
			first_pay = sim.day()
		if sim.day() == last:
			continue
		last = sim.day()
		money_days.append(sim.money)
		# день 2: обставляем новый цех — верстак, недорогой станок, стеллаж; люди под станок
		if build and not bought and shop_o.x >= 0:
			bought = true
			var inner := Rect2i(shop_o + Vector2i(2, 2), Templates.inner("workshop") - Vector2i(2, 2))
			buy_in(sim, "workbench", inner, log)
			buy_in(sim, "lathe_tv4", inner, log)
			buy_in(sim, "rack", inner, log)
			Scenario.autowire(sim)
			Scenario.autopipe(sim)
			sim.world.cable_rev += 1
			hire_prof(sim, "turner", log)
			if scn != "garage":
				hire_prof(sim, "turner", log)
				hire_prof(sim, "qc", log)
	var cats := {}
	for wk: Dictionary in sim.office.weeks:
		var wc: Dictionary = wk["cats"]
		for c: String in wc.keys():
			cats[c] = float(cats.get(c, 0.0)) + float(wc[c])
	return {"money": money_days, "cats": cats, "neg_day": neg_day, "first_pay": first_pay, "min": mn, "log": log, "start": start,
		"staff": sim.workers.size(), "done": sim.orders.by_status(["done"]).size()}


const PLANT_STAFF := {"turner": 8, "miller": 5, "welder": 2, "heat_treater": 1, "painter": 1, "assembler": 3, "laborer": 3,
	"qc": 2, "fitter": 1, "setter": 1, "foreman": 1, "chief": 1, "accountant": 1, "buyer": 1, "dispatcher": 1, "hr": 1,
	"technologist": 1, "cleaner": 1, "guard": 1, "cook": 1}
const PLANT_SKILL := {"turner": "turning", "miller": "milling", "welder": "welding", "heat_treater": "heat", "painter": "paint",
	"assembler": "assembly", "laborer": "haul", "qc": "qc", "fitter": "fitting", "setter": "setup"}


static func _accept_fit(sim: Sim) -> void:
	for o: Dictionary in sim.orders.by_status(["offer"]):
		if sim.orders.active_count() >= sim.orders.max_active():
			break
		if not sim.prod.can_make(str(o["product"])):
			continue
		if sim.office.load_days(str(o["product"]), int(o["qty"])) > float(int(o.get("lead", 3))) * 0.85:
			continue
		sim.orders.accept(int(o["id"]), true)


## Средний завод: сцена — гараж с большим цехом и заводоуправлением, ещё станки в цех, люди по PLANT_STAFF.
static func run_plant(mode: String, seed_value: int, days: int) -> Dictionary:
	var S: GDScript = load("res://tests/setups.gd")
	var sim := Scenario.new_game("garage", "mech", mode, seed_value)
	S.big_shop(sim, false)
	S.offices(sim)
	for def: String in ["lathe", "lathe", "lathe", "lathe", "mill", "lathe_tv4", "mill", "lathe_tv4", "mill"]:
		var done := false
		for y in range(5, 18):
			for x in range(31, 44):
				if not done and sim.can_place(def, Vector2i(x, y)) == "":
					sim.place_thing(def, Vector2i(x, y), true, false)
					done = true
	Scenario.autowire(sim)
	sim.world.cable_rev += 1
	sim.rooms.update()
	for pf: String in PLANT_STAFF.keys():
		for i in int(PLANT_STAFF[pf]):
			var w := People.make(sim.rng, pf)
			if PLANT_SKILL.has(pf):
				w.skills[str(PLANT_SKILL[pf])] = maxi(w.skill(str(PLANT_SKILL[pf])), 5)
			w.wage = People.wage_for(w)
			sim.add_worker(w)
	sim.money = 600000.0
	sim.story.enabled = false
	sim.progress.tutorial = -1
	sim.auto_supply = true
	var payroll := 0
	for w in sim.workers:
		payroll += w.wage
	var m0 := sim.money
	var last := -1
	while sim.day() <= days:
		sim.tick(0.5)
		if sim.day() != last and sim.tod() > 480.0:
			last = sim.day()
			_accept_fit(sim)
			print("   день %d: деньги %s, заявок %d, в работе %d, сделано %d, на заводе %d" % [sim.day(), kr(sim.money), sim.orders.by_status(["offer"]).size(), sim.orders.active_count(), sim.orders.by_status(["done"]).size(), sim.workers.filter(func(w: Worker) -> bool: return w.present).size()])
	var weeks: Array = []
	for wk: Dictionary in sim.office.weeks:
		var net := 0.0
		for c: String in (wk["cats"] as Dictionary).keys():
			if c != "capex":
				net += float(wk["cats"][c])
		weeks.append({"week": int(wk["week"]), "cats": wk["cats"], "net": net})
	return {"staff": sim.workers.size(), "payroll": payroll, "m0": m0, "money": sim.money, "weeks": weeks,
		"done": sim.orders.by_status(["done"]).size(), "failed": sim.orders.by_status(["failed"]).size()}


static func print_plant(r: Dictionary, mode: String) -> void:
	print("\n== ЗАВОД / %s: людей %d, ставки за смену %s (неделя ≈ %s)" % [mode, int(r["staff"]), Defs.money_str(float(r["payroll"])), Defs.money_str(float(r["payroll"]) * 5.0)])
	var ws: Array = r["weeks"]
	ws.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["week"]) < int(b["week"]))
	for wk: Dictionary in ws:
		var parts: PackedStringArray = []
		for c: String in Office.CAT_ORDER:
			if (wk["cats"] as Dictionary).has(c):
				parts.append("%s %s" % [c, kr(float(wk["cats"][c]))])
		print("   неделя %d: %s | итог без капвложений %s" % [int(wk["week"]), ", ".join(parts), kr(float(wk["net"]))])
	print("   деньги %s → %s, заказов выполнено %d, сорвано %d" % [kr(float(r["m0"])), kr(float(r["money"])), int(r["done"]), int(r["failed"])])


static func _sales(sim: Sim) -> float:
	var t := 0.0
	for wk: Dictionary in sim.office.weeks:
		t += float((wk["cats"] as Dictionary).get("sales", 0.0))
	return t


static func kr(v: float) -> String:
	return "%d" % int(round(v / 1000.0))


func _initialize() -> void:
	Defs.load_all()
	var args := OS.get_cmdline_user_args()
	var days := int(args[0]) if args.size() > 0 else 14
	var seed_value := int(args[1]) if args.size() > 1 else 3
	var modes: Array = MODES
	if args.size() > 2:
		modes = Array(str(args[2]).split(","))
	var build := not (args.size() > 3 and str(args[3]) == "nobuild")
	var scns: Array = SCNS
	if args.size() > 4:
		scns = Array(str(args[4]).split(","))
	if args.size() > 3 and str(args[3]) == "plant":
		for mode2: String in modes:
			print_plant(run_plant(mode2, seed_value, days), mode2)
		quit(0)
		return
	print("ЗАМЕР НАЧАЛА ИГРЫ: %d дн., сид %d (деньги в тыс. ₽ на утро дня)" % [days, seed_value])
	for scn: String in scns:
		for mode: String in modes:
			var r := run(scn, mode, seed_value, days, build)
			print("\n== %s / %s: старт %s" % [scn, mode, Defs.money_str(float(r["start"]))])
			for l: String in r["log"]:
				print("   " + l)
			var md: PackedStringArray = []
			for v: float in r["money"]:
				md.append(kr(v))
			print("   деньги: " + " ".join(md))
			var parts: PackedStringArray = []
			for c: String in Office.CAT_ORDER:
				if (r["cats"] as Dictionary).has(c):
					parts.append("%s %s" % [c, kr(float(r["cats"][c]))])
			print("   статьи: " + ", ".join(parts))
			var nd := int(r["neg_day"])
			var fp := int(r["first_pay"])
			print("   минимум %s, в минус: %s, первая оплата: %s, людей %d, заказов выполнено %d" % [kr(float(r["min"])),
				("день %d" % nd) if nd > 0 else "нет", ("день %d" % fp) if fp > 0 else "нет", int(r["staff"]), int(r["done"])])
	quit(0)
