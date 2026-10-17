extends SceneTree
## Инструмент баланса: гоняет гараж и цех по N дней, принимая выгодные заказы, и печатает
## недельные статьи доходов и расходов. Не тест — ничего не проверяет.
## godot --headless --path . -s res://tests/econ_probe.gd -- [garage|shop] [дней]

const S := preload("res://tests/setups.gd")


func _accept_all(sim: Sim) -> void:
	for o: Dictionary in sim.orders.by_status(["offer"]):
		if sim.orders.active_count() >= sim.orders.max_active():
			break
		if not sim.prod.can_make(str(o["product"])):
			continue
		if sim.office.load_days(str(o["product"]), int(o["qty"])) > float(int(o.get("lead", 3))) * 0.85:
			continue
		sim.orders.accept(int(o["id"]), true)


## Бот-директор (РП-33): раз в день смотрит узкое место и, если у станков узкого места
## не хватает людей, нанимает станочника. Ничего не строит — только кадры.
const MACHINE_OF := {"turning": "lathe", "milling": "mill", "drilling": "drill", "welding": "weld_post", "heat": "furnace", "paint": "paint_booth", "assembly": "assembly_table"}
const SKILL_OF := {"turning": ["turner", "turning"], "milling": ["miller", "milling"], "drilling": ["miller", "milling"],
	"welding": ["welder", "welding"], "heat": ["heat_treater", "heat"], "paint": ["painter", "paint"], "assembly": ["assembler", "assembly"]}


func _bot_day(sim: Sim) -> void:
	var li := sim.office.load_info()
	var pr := str(li[1])
	if pr == "" or float(li[0]) < 2.0 or not SKILL_OF.has(pr):
		return
	var machines := 0
	for m in sim.things_of("machine"):
		if m.process() == pr and m.enabled and not m.broken:
			machines += 1
	var ops := 0
	for w in sim.workers:
		if sim.prod.is_operator_for(w, pr):
			ops += 1
	if ops < machines and sim.money > 150000.0:
		var sk: Array = SKILL_OF[pr]
		var w := S.hire(sim, str(sk[0]), str(sk[1]), 5)
		print("  [бот] день %d: узкое место %s (%.1f дн.), нанят %s %s" % [sim.day(), pr, float(li[0]), w.prof_name(), w.first])
		return
	# людей хватает — нужен ещё станок (если есть деньги и место в цеху)
	var def := str(MACHINE_OF.get(pr, ""))
	if def == "" or not Defs.objects.has(def):
		return
	var cost := float(Defs.objects[def].get("cost", 100000))
	if sim.money < cost + 250000.0 or machines >= 4:
		return
	# свободный низ цеха, не перекрывая проходов от дверей
	for c: Vector2i in [Vector2i(31, 17), Vector2i(35, 17), Vector2i(31, 16), Vector2i(35, 16)]:
		if sim.can_place(def, c) == "":
			sim.place_thing(def, c, true, false)
			sim.spend(cost, "Покупка: " + str(Defs.objects[def]["name"]))
			Scenario.autowire(sim)
			sim.world.cable_rev += 1
			print("  [бот] день %d: узкое место %s (%.1f дн.), куплен %s" % [sim.day(), pr, float(li[0]), str(Defs.objects[def]["name"])])
			return


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var mode := str(args[0]) if args.size() > 0 else "garage"
	var days := int(args[1]) if args.size() > 1 else 28
	var seed := int(args[2]) if args.size() > 2 else 3
	var sim: Sim
	if mode == "garage":
		sim = Scenario.new_game("garage", "mech", "calm", seed)
	elif mode == "garage2":
		sim = Scenario.new_game("garage", "mech", "calm", seed)
		var spot := Vector2i(20, 13)
		print("  место: ", sim.can_place("lathe", spot))
		sim.place_thing("lathe", spot, true, false)
		sim.money -= 160000.0 + 90000.0
		sim.power.grid_level = 1
		Scenario.autowire(sim)
		var t2 := S.hire(sim, "turner", "turning", 5)
		print("  второй токарный в ", spot, ", подключён: ", sim.power.connected(sim.things_of("machine")[-1]))
	else:
		sim = Scenario.new_game("garage", "mech", "calm", seed)
		S.big_shop(sim, true)
		sim.money = 600000.0
	sim.story.enabled = false
	sim.progress.tutorial = -1
	sim.auto_supply = true
	var wages := 0
	for w in sim.workers:
		wages += w.wage
		print("  %s %s: ставка %d, разряд %d" % [w.prof_name(), w.first, w.wage, w.grade()])
	print("людей %d, ставки за смену %d ₽, неделя ≈ %d ₽" % [sim.workers.size(), wages, wages * 5])
	var bot := args.size() > 3 and str(args[3]) == "bot"
	var m0 := sim.money
	var last_day := -1
	while sim.day() <= days:
		sim.tick(0.5)
		if sim.day() != last_day and sim.tod() > 480.0:
			last_day = sim.day()
			_accept_all(sim)
			if bot:
				_bot_day(sim)
	var tot := {}
	for wk: Dictionary in sim.office.weeks:
		var cats: Dictionary = wk["cats"]
		var parts: PackedStringArray = []
		for c in Office.CAT_ORDER:
			if cats.has(c):
				parts.append("%s %+d" % [c, int(cats[c])])
				tot[c] = float(tot.get(c, 0.0)) + float(cats[c])
		print("неделя %d: %s" % [int(wk["week"]), ", ".join(parts)])
	var parts2: PackedStringArray = []
	for c in Office.CAT_ORDER:
		if tot.has(c):
			parts2.append("%s %+d" % [c, int(tot[c])])
	print("ИТОГО: ", ", ".join(parts2))
	print("деньги: %d → %d (%+d), заказы: выполнено %d, сорвано %d, в работе %d, репутация %.0f" % [int(m0), int(sim.money), int(sim.money - m0), sim.orders.by_status(["done"]).size(), sim.orders.by_status(["failed"]).size(), sim.orders.active_count(), sim.reputation])
	for m in sim.things_of("machine"):
		print("  станок %s: загрузка %.0f%%, питание %s/%s, люди %s, изделие '%s'" % [m.title(), m.util * 100.0, sim.power.connected(m), sim.power.powered(m), sim.planner.staffed(m), m.product])
	for o: Dictionary in sim.orders.list:
		if str(o["status"]) == "failed" or str(o["status"]) == "active":
			print("  %s: %s ×%d, срок %d, принят день %d, отгружено %d" % [o["status"], o["product"], int(o["qty"]), int(o.get("lead", 0)), int(float(o.get("accepted", 0.0)) / 1440.0) + 1, int(o.get("shipped", 0))])
	var s14 := sim.sales.summary(14)
	print("  сбыт за 14 дн: взято %d на %d, отказано %d на %d" % [int(s14["taken"]), int(s14["taken_sum"]), int(s14["lost"]), int(s14["lost_sum"])])
	var whys := {}
	for e: Dictionary in sim.sales.log:
		var k := str(e["why"]).split(":")[0] if not bool(e["ok"]) else "ВЗЯТО"
		whys[k] = int(whys.get(k, 0)) + 1
	print("  причины: ", whys)
	var fines := 0.0
	for e: Dictionary in sim.ledger:
		if str(e["text"]).contains("Штраф") or str(e["text"]).contains("штраф"):
			fines += float(e["v"])
	print("  штрафы: %d" % int(fines))
	var fk := {}
	for e: Dictionary in sim.ledger:
		var tx := str(e["text"])
		if tx.contains("Штраф") or tx.contains("штраф") or tx.contains("Пени"):
			var key := tx.substr(0, 48)
			fk[key] = float(fk.get(key, 0.0)) + float(e["v"])
	for k in fk.keys():
		print("    %s: %d" % [k, int(fk[k])])
	quit(0)
