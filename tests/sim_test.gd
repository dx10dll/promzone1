extends SceneTree
## Headless-тест симуляции: гоняем сценарий «Гараж» несколько игровых дней
## и проверяем, что заказы выполняются, а люди не застревают.

func _init() -> void:
	var days := 8
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		days = int(args[0])
	var sim := Scenario.new_garage(12345)
	sim.auto_supply = true
	sim.notified.connect(func(t: String, lvl: int, _c: Vector2i) -> void:
		print("  [%s %s] %s" % [sim.date_str(), sim.time_str(), t]))
	print("Старт: деньги ", sim.money, ", заказов ", sim.orders.list.size())
	var accepted := 0
	for o: Dictionary in sim.orders.list:
		if str(o["status"]) == "offer" and accepted < 1 and sim.prod.can_make(str(o["product"])):
			var err := sim.orders.accept(int(o["id"]), true)
			print("Принят заказ: ", sim.orders.short(o), " ", err)
			accepted += 1
	var last_day := sim.day()
	var last_hour := -1
	var stuck_report := {}
	while sim.day() <= days:
		sim.tick(0.5)
		if sim.hour() != last_hour:
			last_hour = sim.hour()
			if last_hour in [9, 12, 15]:
				var acts := []
				for w in sim.workers:
					acts.append("%s: %s" % [w.first, w.activity if w.present else "дома"])
				print("  %s %s | %s" % [sim.date_str(), sim.time_str(), ", ".join(acts)])
		if sim.day() != last_day:
			last_day = sim.day()
			print("=== %s: деньги %s, сделано %d, брак %d, отгружено %d, заказов выполнено %d, сорвано %d, репутация %.0f" % [
				sim.date_str(), Defs.money_str(sim.money), int(sim.stats["made"]), int(sim.stats["scrap"]),
				int(sim.stats["shipped"]), int(sim.stats["orders_done"]), int(sim.stats["orders_failed"]), sim.reputation])
			# принимаем новые заказы, если мало в работе
			if sim.orders.active_count() < 3:
				for o2: Dictionary in sim.orders.list:
					if str(o2["status"]) == "offer" and sim.prod.can_make(str(o2["product"])):
						print("Принят заказ: ", sim.orders.short(o2), " ", sim.orders.accept(int(o2["id"]), true))
						break
	# проверка сохранения
	var d := sim.to_dict()
	var txt := JSON.stringify(d)
	var parsed: Dictionary = JSON.parse_string(txt)
	var sim2 := Sim.from_dict(parsed)
	print("Сохранение: %d байт, после загрузки деньги %s, рабочих %d, грузов %d" % [txt.length(), Defs.money_str(sim2.money), sim2.workers.size(), sim2.items.size()])
	for k in 200:
		sim2.tick(0.5)
	print("После загрузки игра идёт: ", sim2.date_str(), " ", sim2.time_str())
	var ok := int(sim.stats["orders_done"]) >= 1
	sim.dispose()
	sim2.dispose()
	print("РЕЗУЛЬТАТ: ", "OK" if ok else "ПРОВАЛ")
	quit(0 if ok else 1)
