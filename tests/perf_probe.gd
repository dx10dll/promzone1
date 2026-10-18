extends SceneTree
## Замер: сколько времени уходит на каждую подсистему за игровые сутки на большом заводе.
## godot --headless --path . -s res://tests/perf_probe.gd -- [людей] [шагов]

const S := preload("res://tests/setups.gd")


func _init() -> void:
	Defs.load_all()
	var g := Scenario.new_game("garage", "mech", "calm", 77)
	g.story.enabled = false
	g.progress.tutorial = -1
	g.bmats.enabled = false
	S.big_shop(g)
	S.offices(g)
	var args := OS.get_cmdline_user_args()
	var want := int(args[0]) if args.size() > 0 else 0
	for p in [["turner", "turning", 5], ["turner", "turning", 5], ["miller", "milling", 5], ["laborer", "haul", 5], ["laborer", "haul", 5], ["qc", "qc", 5], ["foreman", "manage", 6], ["accountant", "office", 5], ["buyer", "office", 5], ["dispatcher", "office", 5]]:
		S.hire(g, str(p[0]), str(p[1]), int(p[2]))
	var profs := [["laborer", "haul"], ["turner", "turning"], ["miller", "milling"], ["laborer", "haul"], ["qc", "qc"], ["cleaner", "clean"], ["builder", "build"]]
	var kk := 0
	while g.workers.size() < want:
		var pp: Array = profs[kk % profs.size()]
		S.hire(g, str(pp[0]), str(pp[1]), 4)
		kk += 1
	S.complex_orders(g, 10)
	print("людей: %d, объектов: %d, предметов: %d" % [g.workers.size(), g.things.size(), g.items.size()])
	# прогрев
	for i in 600:
		g.tick(0.5)
	var names := ["supply", "logi", "bmats_tr", "grants", "vehicles", "rooms", "season", "power", "cons", "machines", "office", "dev", "bmats", "social", "story", "brain", "inspect", "progress", "planner", "orders", "sales", "training", "town", "fauna", "upkeep", "eng", "plan", "faults", "timed"]
	var acc := {}
	for n in names:
		acc[n] = 0
	var steps := int(args[1]) if args.size() > 1 else 2880   # сутки по 0.5 мин
	var t0 := Time.get_ticks_usec()
	for i2 in steps:
		var dt := 0.5
		var prev_day := g.day()
		var prev_tod := g.tod()
		g.minute += dt
		var now_tod := g.tod()
		var a := Time.get_ticks_usec()
		if g.day() != prev_day:
			g._on_new_day()
			prev_tod = -1.0
		g._timed(prev_tod, now_tod)
		var b := Time.get_ticks_usec()
		acc["timed"] = int(acc["timed"]) + b - a
		var calls := [
			["supply", func() -> void: g._tick_supply()], ["logi", func() -> void: g.logi.tick()], ["bmats_tr", func() -> void: g.bmats.tick_trucks()],
			["grants", func() -> void: g.grants.tick(dt)], ["vehicles", func() -> void: g._tick_vehicles(dt)], ["rooms", func() -> void: g.rooms.update()],
			["season", func() -> void: g.season.tick(dt)], ["power", func() -> void: g.power.tick(dt)], ["cons", func() -> void: g._tick_cons_supply()],
			["machines", func() -> void: g._tick_machines(dt)], ["office", func() -> void: g.office.tick(dt)], ["dev", func() -> void: g.dev.tick(dt)],
			["bmats", func() -> void: g.bmats.tick(dt)], ["social", func() -> void: g.social.tick(dt)], ["story", func() -> void: g.story.tick(dt)],
			["brain", func() -> void: g.brain.tick(dt)], ["inspect", func() -> void: g.inspect.tick(dt)], ["progress", func() -> void: g.progress.tick(dt)],
			["planner", func() -> void: g.planner.tick(dt)], ["orders", func() -> void: g.orders.tick(dt)], ["sales", func() -> void: g.sales.tick(dt)],
			["training", func() -> void: g.training.tick(dt)], ["town", func() -> void: g.town.tick(dt)], ["fauna", func() -> void: g.fauna.tick(dt)],
			["upkeep", func() -> void: g.upkeep.tick(dt)], ["eng", func() -> void: g.eng.tick(dt)], ["plan", func() -> void: g.plan.tick(dt)], ["faults", func() -> void: g.faults.tick()]]
		for c: Array in calls:
			var s := Time.get_ticks_usec()
			(c[1] as Callable).call()
			acc[str(c[0])] = int(acc[str(c[0])]) + Time.get_ticks_usec() - s
	var total := Time.get_ticks_usec() - t0
	print("%d шагов: %.0f мс, на шаг %.3f мс" % [steps, total / 1000.0, total / 1000.0 / steps])
	var keys := acc.keys()
	keys.sort_custom(func(x: Variant, y: Variant) -> bool: return int(acc[x]) > int(acc[y]))
	for k in keys:
		print("  %-10s %8.1f мс  %5.1f%%" % [str(k), int(acc[k]) / 1000.0, 100.0 * int(acc[k]) / maxf(1.0, total)])
	quit(0)
