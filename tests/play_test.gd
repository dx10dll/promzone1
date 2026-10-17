extends Node
## Прогон игровой сцены целиком (с отображением и интерфейсом) на высокой скорости.
## godot --headless --path . --fixed-fps 10 res://tests/play_test.tscn -- <дней>

var gm: GameMain
var frames := 0
var last_hour := -1
var act_time := {}
var days := 4
var windows := ["orders", "shop", "supply", "staff", "finance", "log", "office", "research", "events", "paper"]


func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	if a.size() > 0:
		days = int(a[0])
	Game.pending = "new"
	Game.pending_scn = "garage"
	Game.pending_profile = "mech"
	Game.pending_opts = {}
	Game.pending_seed = int(a[1]) if a.size() > 1 else 99
	Game.settings["tutorial_done"] = true
	Game.settings["autosave"] = true
	Game.settings["pause_on_event"] = false
	gm = load("res://scenes/game.tscn").instantiate()
	add_child(gm)
	gm.sim.notified.connect(func(t: String, _l: int, _c: Vector2i) -> void: print("  [", gm.sim.date_str(), " ", gm.sim.time_str(), "] ", t))
	gm.set_speed(3)
	var s := gm.sim
	s.build_priority = a.size() > 2 and a[2] == "prio"
	s.money += 400000.0
	# новый цех справа от гаража: пол, стены, дверь, станок, туалет
	var t := gm.tool
	t.set_mode("floor", 1)
	t._apply_floor(Rect2i(30, 9, 9, 10))
	t.set_mode("wall", 1)
	t._apply_wall(Rect2i(29, 8, 11, 12))
	t.set_mode("door", 3)
	t._apply_openings(Rect2i(29, 13, 1, 1))
	t.set_mode("window", 2)
	t._apply_openings(Rect2i(33, 8, 3, 1))
	t.set_mode("object", "lathe")
	t._place_object(Vector2i(32, 10))
	t.set_mode("object", "toilet")
	t._place_object(Vector2i(37, 17))
	t.set_mode("select")
	print("Чертежей: ", s.bp_cells.size(), ", деньги ", Defs.money_str(s.money))
	for o: Dictionary in s.orders.list:
		if str(o["status"]) == "offer":
			print("Принят: ", s.orders.short(o), " ", s.orders.accept(int(o["id"]), true))
			break
	var hired := false
	for i in s.candidates.size():
		if str(s.candidates[i].get("prof", "")) == "turner":
			print("Нанят токарь: ", s.hire(i))
			hired = true
			break
	if not hired:
		s.hire(0)


func _process(_d: float) -> void:
	frames += 1
	var s := gm.sim
	if s.is_work_time():
		for w in s.workers:
			if w.present:
				var key := w.first + " | " + (w.activity.split(":")[0] if w.activity.begins_with("Несёт") or w.activity.begins_with("Точит") else w.activity)
				act_time[key] = float(act_time.get(key, 0.0)) + 1.0
	if frames % 97 == 0:
		gm.hud.open_window(windows[(frames / 97) % windows.size()])
	if frames % 131 == 0:
		gm.hud.close_window()
		gm.hud.toggle_sub("objects" if (frames / 131) % 2 == 0 else "build")
	if frames % 151 == 0 and not s.workers.is_empty():
		gm.tool.select_worker(s.workers[(frames / 151) % s.workers.size()].id)
	if frames % 173 == 0:
		var ids := s.things.keys()
		gm.tool.select_thing(int(ids[(frames / 173) % ids.size()]))
	if frames % 61 == 0 and not s.story.letters.is_empty():
		var l: Dictionary = s.story.letters[0]
		print("   [письмо] ", l["title"], " -> ", l["choices"][int(l["def"])]["text"])
		s.story.resolve(int(l["id"]), int(l["def"]))
	if frames % 400 == 0:
		gm.hud.show_pause_menu()
	if frames % 400 == 5:
		gm.hud.close_modal()
	if frames % 300 == 0:
		# принимаем новые заказы, чтобы завод не простаивал
		if s.orders.active_count() < 3:
			for o: Dictionary in s.orders.list:
				if str(o["status"]) == "offer":
					s.orders.accept(int(o["id"]), true)
					break
	var hh := s.hour()
	if hh != last_hour and (hh == 10 or hh == 15) and s.is_workday():
		for m in s.things_of("machine"):
			print("   станок %d: деталь '%s', токарь %d, в лотке %d, на выходе %d, рабочий: %s" % [m.id, m.product, m.user, s.count_slot(m, 0), s.count_slot(m, 1), s.get_worker(m.user).activity if s.get_worker(m.user) else "-"])
		for o: Dictionary in s.orders.by_status(["active", "ready", "shipping"]):
			print("   заказ ", s.orders.short(o), " ", o["status"], " металл ", s.free_material(s.planner.material_of(str(o["product"]))), "/", s.material_total(s.planner.material_of(str(o["product"]))))
	last_hour = hh
	if frames % 500 == 0:
		print("%s %s | деньги %s | чертежей %d | объектов %d (не смонтировано %d) | заказов: выполнено %d, сорвано %d | %s" % [
			s.date_str(), s.time_str(), Defs.money_str(s.money), s.bp_cells.size(), s.things.size(),
			s.things.values().filter(func(x: Thing) -> bool: return not x.built).size(),
			int(s.stats["orders_done"]), int(s.stats["orders_failed"]),
			", ".join(s.workers.map(func(w: Worker) -> String: return w.first + ": " + w.activity))])
	if frames % 500 == 0 and not s.is_work_time():
		for w in s.workers:
			if w.present:
				print("   застрял? ", w.first, " клетка ", w.cell(), " pos ", w.pos, " выход ", w.exit_cell, " достижим: ", s.world.reachable(w.cell(), w.exit_cell), " проходима: ", s.world.passable(w.cell()), " задача: ", w.task.kind if w.task else "-")
				var c := w.cell()
				for dy in range(-2, 3):
					var row := ""
					for dx in range(-2, 3):
						var cc := c + Vector2i(dx, dy)
						row += "%d%s " % [s.world.get_wall(cc), "#" if not s.world.passable(cc) else "."]
					print("      ", row)
	if s.day() > days:
		var err := Game.save_sim(s, "test_slot", "тест")
		var s2 := Game.load_sim("test_slot")
		print("Сохранение: ", "ok" if err == "" and s2 != null else "ОШИБКА " + err)
		Game.delete_save("test_slot")
		Game.delete_save(Game.AUTOSAVE)
		if s2:
			s2.dispose()
		var shown := 0
		for i in s.bp_cells.keys():
			var c := s.world.cell_of(i)
			print("   чертёж ", c, " пол ", s.world.bp_floor[i], " стена ", s.world.bp_wall[i], " сейчас стена ", s.world.wall[i], " готов ", s.bp_ready(i), " резерв ", s.bp_res.get(i, -1), " проходима ", s.world.passable(c), " достижима ", s.world.reachable(Vector2i(20, 14), c), " occ ", s.world.occ[i])
			shown += 1
			if shown > 12:
				break
		var keys := act_time.keys()
		keys.sort_custom(func(a: String, b: String) -> bool: return a < b)
		for k in keys:
			print("   %-60s %5d" % [k, int(act_time[k])])
		print("ИТОГ: кадров %d, чертежей осталось %d, станков %d, заказов выполнено %d" % [frames, s.bp_cells.size(), s.things_of("machine").size(), int(s.stats["orders_done"])])
		get_tree().quit()
