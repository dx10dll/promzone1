extends SceneTree
func _init() -> void:
	var p := OS.get_cmdline_user_args()[0]
	var sim := Sim.from_dict(JSON.parse_string(FileAccess.get_file_as_string(p)))
	sim.notified.connect(func(t: String, _l: int, _c: Vector2i) -> void: print("  [%s] %s" % [sim.time_str(), t]))
	var start := int(sim.stats["orders_done"])
	while sim.minute < 6.0 * 1440.0:
		sim.tick(0.5)
		if int(sim.minute) % 1440 == 420:
			for o: Dictionary in sim.orders.list:
				if str(o["status"]) == "offer" and sim.orders.active_count() < 2:
					sim.orders.accept(int(o["id"]), true)
	var cables := 0
	for i in sim.world.cable.size():
		cables += sim.world.cable[i]
	print("кабелей: ", cables, " помещений: ", sim.rooms.list.size(), " тип: ", sim.rooms.list[0].type if not sim.rooms.list.is_empty() else "-")
	for m in sim.things_of("machine"):
		print("станок под током: ", sim.power.powered(m))
	print("заказов выполнено после загрузки: ", int(sim.stats["orders_done"]) - start)
	for w in sim.workers:
		print(w.first, " черты: ", w.trait_names(), " настроение ", int(w.mood))
	quit()
