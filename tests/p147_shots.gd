extends Node
## 1.47: снимки интерфейса. xvfb-run -a -s "-screen 0 1920x1080x24" godot --path . --resolution 1920x1080 res://tests/p147_shots.tscn -- --mode=full|crop|hud|card|card150|orders|checklist152|paper152 --out=/файл.png [--lang=ru]

var out := "/tmp/p147.png"
var mode := "full"
var lang := "ru"
var cam_arg := ""      ## 1.48: --cam=x,y,zoom — тайловые координаты центра и масштаб
var fauna := false     ## --fauna: кошка и голуби перед камерой
var crop_arg := ""     ## --crop=x,y,w,h в пикселях экрана


func _ready() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.get_slice("=", 1)
		elif a.begins_with("--mode="):
			mode = a.get_slice("=", 1)
		elif a.begins_with("--cam="):
			cam_arg = a.get_slice("=", 1)
		elif a.begins_with("--fauna"):
			fauna = true
		elif a.begins_with("--crop="):
			crop_arg = a.get_slice("=", 1)
		elif a.begins_with("--lang="):
			lang = a.get_slice("=", 1)
	L.apply(lang)
	Game.pending = "new"
	Game.pending_scn = "garage"
	Game.pending_profile = "mech"
	Game.pending_opts = {"tutorial": false}
	Game.pending_seed = 147
	Game.settings["tutorial_done"] = true
	var big155 := mode.ends_with("155")
	if big155:
		Game.pending_sim = GameBench.build_plant(60)   # 1.55: большой завод, как в замере
	var gm: GameMain = load("res://scenes/game.tscn").instantiate()
	add_child(gm)
	await get_tree().create_timer(1.5).timeout
	if big155:
		await _setup155(gm)
		if cam_arg == "":
			cam_arg = "28,24,1.2" if mode == "night155" else ("28,22,1.0" if mode in ["winter155", "autumn155"] else "34,9,2.6")
	if mode == "hud":
		gm.sim.notify("Выбит автомат — часть завода без тока", Sim.LVL_BAD)
		gm.sim.notify("Новая программа поддержки: «Тепло в цехах» — вернут 40 000 ₽. Финансы → Гранты.", Sim.LVL_GOOD)
		gm.sim.notify("Скоро проверка: пожарная. Приготовьте огнетушители.", Sim.LVL_WARN)
		gm.sim.notify("Принят на работу: Иванов, токарь", Sim.LVL_INFO)
	elif mode == "toasts":
		for i in 4:
			gm.sim.notify("Заказан металл: Круг Ст45 × %d. Привезут сегодня к 08:45." % (24 + i), Sim.LVL_INFO)
		gm.sim.notify("Новая программа поддержки: «Тепло в цехах» — вернут 40 000 ₽. Финансы → Гранты.", Sim.LVL_GOOD)
		gm.sim.notify("Принят на работу: Иванов, токарь", Sim.LVL_INFO)
		for i in 3:
			gm.sim.notify("Станок 1К62 простаивает: нет заготовок", Sim.LVL_WARN)
		gm.sim.notify("Скоро проверка: пожарная. Приготовьте огнетушители и проверьте эвакуационные выходы.", Sim.LVL_WARN)
		gm.sim.notify("Выбит автомат — часть завода без тока", Sim.LVL_BAD)
		gm.sim.notify("Рабочий получил травму: Петров, цех. Нужна аптечка рядом со станками.", Sim.LVL_BAD)
		await get_tree().create_timer(0.8).timeout
	elif mode == "card":
		for w in gm.sim.workers:
			if not w.is_director():
				gm.hud.info.show_worker(gm.sim, w)
				break
	elif mode == "card150":
		# 1.50: карточка человека — «Сейчас делает / Чем недоволен / Что сделать» и пять шкал; недоплата, драка, усталость
		for w in gm.sim.workers:
			if not w.is_director():
				w.wage = int(Mood.market_wage(w) * 0.7)
				Mood.add(gm.sim, w, "fight")
				Mood.add(gm.sim, w, "no_vacation")
				Mood.add(gm.sim, w, "grade_up")
				Mood.add(gm.sim, w, "ate_hot")
				w.needs["rest"] = 8.0
				Mood.refresh(gm.sim, w)
				gm.hud.info.show_worker(gm.sim, w)
				break
		await get_tree().create_timer(0.8).timeout
		gm.hud.info.refresh()
		print("card size ", gm.hud.info.size)
	elif mode == "power153":
		# 1.53: «Финансы → Электричество»: пик, лимит, расход день/ночь, заявка на мощность; плашка кВт вверху
		var pwr := gm.sim.power
		gm.sim.minute = 12.0 * 1440.0 + 10.0 * 60.0
		gm.sim.money = 400000.0
		for i in 7:
			pwr.hist.append({"d": 11 - i, "kd": 120.0 + i * 9.0, "kn": 38.0 + i * 5.0, "cd": (120.0 + i * 9.0) * 7.5, "cn": (38.0 + i * 5.0) * 3.75, "peak": 21.0 + (i % 3) * 3.5})
		pwr.kwh_day = 64.0
		pwr.kwh_night = 21.0
		pwr.peak_day = 23.4
		pwr.peak_prev = 26.1
		pwr.trips_today = 1
		pwr.upgrade = {"step": 1, "due": gm.sim.day() + 2, "cost": 60000.0}
		gm.hud.open_window("finance")
		await get_tree().create_timer(0.4).timeout
		gm.hud.win.select_tab("energy")
	elif mode == "stats154":
		# 1.54: «Финансы → Статистика»: 30 суток синтетической истории (--range=7 — неделя)
		var slg := gm.sim.statlog
		var rng := RandomNumberGenerator.new()
		rng.seed = 154
		var m := 90000.0
		for i in 40:
			var prof := rng.randf_range(-3000.0, 9000.0)
			m += prof
			var made := rng.randi_range(20, 60)
			var scr := rng.randi_range(0, 7)
			slg.days.append({"d": 3 + i, "money": m, "profit": prof, "made": made, "scrap": scr, "defect": float(scr) / float(made + scr),
				"mood": 55.0 + 12.0 * sin(float(i) / 4.0) + rng.randf_range(-3, 3), "staff": 6 + i / 8, "kwh": rng.randf_range(60.0, 110.0)})
		if lang != "ru" or cam_arg == "r7":
			GameWindow.stats_range = 7
		gm.hud.open_window("finance")
		await get_tree().create_timer(0.4).timeout
		gm.hud.win.select_tab("stats")
		await get_tree().create_timer(0.4).timeout
		# наведение мыши на один из графиков — плашка со значением
		var cvs: Array = gm.hud.win.find_children("*", "ChartView", true, false)
		if not cvs.is_empty():
			var c0: ChartView = cvs[1]
			c0.hover = 25
			c0.queue_redraw()
	elif mode == "icons154":
		await _icons154(gm)
	elif mode == "rivals153":
		# 1.53: «Заказы → Конкуренты»: карточки директоров
		var mk := gm.sim.market
		gm.sim.office.all_depts = true
		gm.sim.minute = 40.0 * 1440.0 + 9.0 * 60.0
		var rels := [-62, 38, 6, 71]
		var logs := [["Переманивал наших людей", "Перебивал наших клиентов"], ["Взяли часть их заказа (+5)", "Купили у них станок (+4)"], ["Просил одолжить металл"], ["Согласились на переговоры о слиянии (+10)", "Звал к себе: Петров А."]]
		for i in mk.comps.size():
			var cm: Dictionary = mk.comps[i]
			var dd := Rivals.dir_of(cm)
			dd["rel"] = rels[i % 4]
			for t in logs[i % 4]:
				(dd["log"] as Array).append({"d": 30 + i * 3, "t": t})
		gm.hud.open_window("orders")
		await get_tree().create_timer(0.4).timeout
		gm.hud.win.select_tab("compet")
		await get_tree().create_timer(0.4).timeout
		gm.hud.win.scroll.scroll_vertical = 520
	elif mode == "plan":
		gm.hud.toggle_plan()
	elif mode.begins_with("win:"):
		gm.hud.open_window(mode.substr(4))
	elif mode.begins_with("sub:"):
		gm.hud.toggle_sub(mode.substr(4))
	elif mode == "hire":
		gm.sim.progress.stage = 2
		await get_tree().create_timer(1.0).timeout
	elif mode == "orders":
		gm.hud.open_window("orders")
	elif mode.begins_with("board"):
		# 1.48b: доска заявок — несколько карточек разного риска; board_open — с открытым торгом, board_empty — пустая
		var sl := gm.sim.sales
		sl.mode = "small"
		sl.board.clear()
		sl.log.clear()
		if mode != "board_empty":
			var ps: Array = gm.sim.progress.products()
			var specs := [[0, 4, 2500.0, 14], [1, 30, 2300.0, 4], [2, 40, 3400.0, 3]]
			for i in specs.size():
				var o := gm.sim.orders.make_offer(str(ps[int(specs[i][0]) % ps.size()]))
				o["qty"] = int(specs[i][1])
				o["price"] = float(specs[i][2])
				o["lead"] = int(specs[i][3])
				sl._post(o)
				o["expires"] = gm.sim.minute + [1.8, 0.5, 1.2][i] * 1440.0
			var t := gm.sim.orders.make_offer(str(ps[0]))
			t["qty"] = 3
			t["price"] = 400.0
			sl._take(t)
			if mode == "board_open":
				OrderBoard._hg[int(sl.board[0]["id"])] = {"open": true, "pk": 10, "la": 1}
		gm.hud.open_window("orders")
	elif mode.begins_with("badges"):
		# 1.49: значки проблем над станками — badges (карта) и badges_load (слой «Загрузка станков»)
		var S := preload("res://tests/setups.gd")
		var sm := gm.sim
		sm.story.enabled = false
		S.big_shop(sm)
		S.hire(sm, "turner", "turning", 5)
		S.hire(sm, "laborer", "haul", 3)
		S.hire(sm, "miller", "milling", 5)
		S.hire(sm, "fitter", "fitting", 5)
		S.hire(sm, "welder", "welding", 5)
		S.complex_orders(sm, 3)
		gm.menu_paused = true
		var t0 := sm.minute
		while sm.minute < t0 + 600.0:
			sm.tick(0.5)
		var mc: Array = sm.things_of("machine")
		for wk in sm.workers:
			wk.present = true   # снимок: все на месте, чтобы причины были про заготовки и выход
		var prods: Array = mc.filter(func(t: Thing) -> bool: return t.product != "" and t.cell.x >= 29 and not t.is_batch() and Stall.reason(sm, t).get("k", "") == "")
		if prods.size() >= 3:
			for id in sm.slot_ids(prods[0], 0).duplicate():
				sm.delete_item(sm.items[id])
			var fm := prods[1] as Thing
			for i in fm.slot_cap(1):
				sm.put_in_thing(sm.new_item("part", fm.product, "ok"), fm, 1)
			sm.power.thing_net.erase((prods[2] as Thing).id)
		gm.badges.tracker.refresh(sm)
		sm.minute += 30.0
		gm.badges.tracker.refresh(sm)
		for r: Dictionary in gm.badges.tracker.shown.values():
			print("badge ", r["k"], " ", (r["m"] as Thing).def_id, " ", (r["m"] as Thing).cell)
		if mode == "badges_load":
			gm.hud.forced_overlay = "load"
		if cam_arg == "":
			cam_arg = "37,11,2.2"
	elif mode.begins_with("bubbles150"):
		# 1.50d: облачка над людьми — 12 человек подряд, у каждого своё состояние (bubbles150_tip — ещё подсказка)
		var S2 := preload("res://tests/setups.gd")
		var sm2 := gm.sim
		sm2.story.enabled = false
		S2.big_shop(sm2)
		S2.hire(sm2, "turner", "turning", 5)
		S2.hire(sm2, "laborer", "haul", 6)
		S2.hire(sm2, "miller", "milling", 5)
		S2.hire(sm2, "fitter", "fitting", 5)
		S2.hire(sm2, "welder", "welding", 5)
		gm.menu_paused = true
		var t1 := sm2.minute
		while sm2.minute < t1 + 300.0:
			sm2.tick(0.5)
		var ws: Array = sm2.workers.filter(func(x: Worker) -> bool: return not x.is_director() and not x.visitor)
		var mach: Array = sm2.things_of("machine")
		var turn: Thing = null
		for m2: Thing in mach:
			if m2.process() == "turning":
				turn = m2
		var plan := ["hungry", "wc", "tired", "wait_pay", "injury", "fight", "angry", "op_turning", "haul", "repair", "eat", "smoke", "idle", "study"]
		var cx := 37.0
		var cy := 12.0
		var i2 := 0
		for wk2: Worker in ws:
			if i2 >= plan.size():
				break
			wk2.present = true
			wk2.hidden = false
			wk2.needs["bladder"] = 90.0
			wk2.needs["food"] = 90.0
			wk2.needs["rest"] = 90.0
			wk2.mood = 70.0
			wk2.bubble = ""
			wk2.task = null
			wk2.thoughts.clear()
			var col2 := i2 % 7
			var row2 := i2 / 7
			wk2.pos = Vector2(cx - 3.3 + col2 * 1.1, cy + row2 * 2.6)
			wk2.vprev = wk2.pos
			wk2.path.clear()
			var k2: String = plan[i2]
			match k2:
				"hungry": wk2.needs["food"] = 5.0
				"wc": wk2.needs["bladder"] = 12.0
				"tired": wk2.needs["rest"] = 12.0
				"wait_pay": Mood.add(sm2, wk2, "arrears")
				"injury": wk2.bubble = "injury"
				"fight": wk2.bubble = "fight"
				"angry": wk2.mood = 10.0
				_:
					var tk2 := Task.new()
					tk2.kind = {"op_turning": "operate", "haul": "haul", "repair": "repair", "eat": "eat", "smoke": "smoke", "idle": "wander", "study": "study"}[k2]
					if k2 == "op_turning" and turn != null:
						tk2.res_users.append(turn.id)
					wk2.task = tk2
			i2 += 1
		gm.bubbles.force_mode = "all"
		gm.bubbles.refresh(0.5)
		gm.bubbles.refresh(2.6)
		if mode == "bubbles150_tip" and ws.size() > 3:
			await get_tree().create_timer(0.3).timeout
			gm.bubbles.mouse_override = (ws[0] as Worker).vpos() * World.T + Vector2(0, -20)
		if cam_arg == "":
			cam_arg = "%s,%s,3.2" % [cx + 0.2, cy + 1.2]
	elif mode.begins_with("objbadges"):
		# 1.50c: значки проблем над объектами — objbadges (карта) и objbadges_tip (подсказка над батареей)
		var S2 := preload("res://tests/setups.gd")
		var sm2 := gm.sim
		sm2.story.enabled = false
		S2.big_shop(sm2)
		gm.menu_paused = true
		for i in 6:
			sm2.tick(0.5)
		for ht: Thing in sm2.things_of("heater"):
			sm2.things.erase(ht.id)
		sm2.season.temp_day = -5.0
		sm2.place_thing("radiator", Vector2i(44, 7), true, false)
		sm2.place_thing("toilet", Vector2i(44, 18), true, false)
		sm2.place_thing("fridge", Vector2i(44, 9), true, false)
		sm2.place_thing("battery", Vector2i(45, 11), true, false)
		sm2.place_thing("vent_hood", Vector2i(34, 17), true, false)
		sm2.place_thing("lamp_bulb", Vector2i(45, 5), true, false)
		sm2.place_thing("sink", Vector2i(43, 18), true, false)
		sm2.place_thing("toilet", Vector2i(31, 17), true, false)
		sm2.thing_rev += 1
		sm2.tick(0.1)
		gm.obj_badges.tracker.refresh(sm2)
		sm2.minute += 10.0
		gm.obj_badges.tracker.refresh(sm2)
		for r: Dictionary in gm.obj_badges.tracker.shown.values():
			print("objbadge ", r["k"], " ", (r["m"] as Thing).def_id, " ", (r["m"] as Thing).cell)
		if cam_arg == "":
			cam_arg = "39,12,1.9"
	elif mode == "sheet150b":
		# все облачка по видам: спокойные, жёлтые, красные
		var layer := CanvasLayer.new()
		layer.layer = 50
		add_child(layer)
		var bgr := ColorRect.new()
		bgr.color = Color("#8e8b80")
		bgr.size = Vector2(1920, 1080)
		layer.add_child(bgr)
		var kinds: Array = BubbleLogic.TITLES.keys()
		var gx := 0
		for kd: String in kinds:
			var tr_t := 1
			if ["hungry", "tired", "wc", "cold", "hot", "angry", "no_ppe", "wait_pay", "argue"].has(kd):
				tr_t = 2
			if ["injury", "fight", "strike", "fire"].has(kd):
				tr_t = 3
			var tx: Texture2D = BubbleArt.tex(kd, tr_t)
			var r := TextureRect.new()
			r.texture = tx
			r.custom_minimum_size = Vector2(BubbleArt.W, BubbleArt.H)
			r.size = Vector2(BubbleArt.W, BubbleArt.H)
			r.stretch_mode = TextureRect.STRETCH_SCALE
			r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			r.position = Vector2(30 + (gx % 14) * 130, 30 + (gx / 14) * 150)
			layer.add_child(r)
			var lb := Label.new()
			lb.text = kd
			lb.add_theme_font_size_override("font_size", 12)
			lb.position = r.position + Vector2(-6, BubbleArt.H + 2)
			layer.add_child(lb)
			gx += 1
	elif mode == "brigade151" or mode == "career151":
		# 1.51: карточка бригады (план, премия, характер, сплочённость) и вкладка «Карьера»
		var S3 := preload("res://tests/setups.gd")
		var sm3 := gm.sim
		sm3.story.enabled = false
		S3.big_shop(sm3)
		S3.offices(sm3)
		var fm3 := S3.hire(sm3, "foreman", "manage", 6)
		fm3.present = true
		for dk: Thing in sm3.things.values():
			if dk.def_id == "office_desk" and dk.cell == Vector2i(8, 7):
				fm3.desk_id = dk.id
		var ta := S3.hire(sm3, "turner", "turning", 7)
		var tb := S3.hire(sm3, "turner", "turning", 4)
		var mc3 := S3.hire(sm3, "miller", "milling", 6)
		var fc3 := S3.hire(sm3, "fitter", "fitting", 3)
		var lb3 := S3.hire(sm3, "laborer", "haul", 4)
		ta.traits = ["born_mentor"]
		mc3.traits = ["workaholic"]
		S3.complex_orders(sm3, 3)
		var b1 := sm3.crew.add_brigade("Токарный участок")
		var b2 := sm3.crew.add_brigade("Фрезерный участок")
		sm3.crew.set_member(ta, int(b1["id"]))
		sm3.crew.set_member(tb, int(b1["id"]))
		sm3.crew.set_member(mc3, int(b2["id"]))
		sm3.crew.set_member(fc3, int(b2["id"]))
		sm3.crew.set_lead(int(b1["id"]), ta.id)
		sm3.crew.set_lead(int(b2["id"]), mc3.id)
		b1["coh"] = 72.0
		b2["coh"] = 35.0
		b2["coh_pen"] = 12.0
		b1["bonus"] = 2
		b2["bonus"] = 1
		b1["plan_adj"] = 2
		sm3.crew.start_plans()
		b1["done"] = int(sm3.crew.plan_today(int(b1["id"])) * 0.7)
		b2["done"] = sm3.crew.plan_today(int(b2["id"]))
		b2["last_pct"] = 104
		for tk in sm3.things_of("machine"):
			tk.owner = ta.id if tk.process() == "turning" else (mc3.id if tk.process() == "milling" else tk.owner)
		gm.menu_paused = true
		if mode == "brigade151":
			gm.hud.open_window("crew")
		else:
			lb3.skills["turning"] = 3
			lb3.days_worked = 6
			tb.days_worked = 30
			sm3.career.exams[tb.id] = sm3.day()
			sm3.training.set_mentor(tb, ta)
			gm.hud.info.show_worker(sm3, tb)
			InfoPanel.w_tab = "career"
			gm.hud.info.show_worker(sm3, tb)
			await get_tree().create_timer(0.5).timeout
	elif mode == "checklist152" or mode == "checklist152_todo" or mode == "paper152":
		# 1.52: чек-лист инспектора (окно «События» → «Проверки», «Что делать» слева) и газета с объявлением
		var S4 := preload("res://tests/setups.gd")
		var sm4 := gm.sim
		sm4.story.enabled = false
		S4.big_shop(sm4)
		S4.offices(sm4)
		sm4.progress.stage = 4
		gm.menu_paused = true
		for w4 in sm4.workers:
			w4.present = true
		if mode != "paper152":
			sm4.minute = 20.0 * 1440.0 + 9.0 * 60.0
			sm4.inspect.queue.clear()
			sm4.inspect.schedule("fire", sm4.minute + 5.0 * 1440.0, true, "плановая")
			sm4.inspect.schedule("labor", sm4.minute + 7.0 * 1440.0, true, "плановая")
			if mode == "checklist152":
				gm.hud.open_window("events")
				if gm.hud.win:
					gm.hud.win.select_tab("insp")
			await get_tree().create_timer(0.8).timeout
		else:
			sm4.minute = 30.0 * 1440.0 + 8.0 * 60.0
			var pp4 := sm4.paper
			var pr4 := str(Defs.products.keys()[0])
			var of4 := sm4.orders.make_offer(pr4)
			of4["qty"] = 120
			of4["price"] = 2800.0
			of4["status"] = "offer"
			sm4.orders.list.append(of4)
			sm4.orders.accept(int(of4["id"]), false)
			pp4.on_crew_plan("Токарный участок", 118)
			pp4.on_iso()
			pp4.hired_w = 3
			pp4.fired_w = 2
			pp4.number = 5
			pp4.publish(true)
			pp4._make_ad("machine")
			sm4.paper.unread = false
			gm.hud.open_window("paper")
			await get_tree().create_timer(0.4).timeout
	elif mode == "settings":
		gm.hud.show_settings()
	elif mode == "finance":
		gm.hud.open_window("finance")
	if cam_arg != "":
		var cv := cam_arg.split(",")
		if cv[0] == "gate":   # вывеска у проходной
			cv = PackedStringArray([str(gm.sim.gate_x + 2.0), str(gm.sim.world.plot.end.y - 0.4), cv[1]])
		gm.menu_paused = true
		gm.hud.visible = false
		gm.cam.zoom = Vector2(float(cv[2]), float(cv[2]))
		gm.cam.position = Vector2(float(cv[0]), float(cv[1])) * World.T
		if fauna:
			var c := Cat.make(gm.sim)
			gm.sim.town.cat = c
			c.pos = Vector2(float(cv[0]) - 1.2, float(cv[1]) + 0.3)
			c.vprev = c.pos
			c.state = "walk"
			c.dir = 1
			gm.sim.fauna.pigeons.clear()
			var pc := Vector2(float(cv[0]) + 1.2, float(cv[1]) + 0.6)
			gm.sim.fauna.pigeons.append({"pos": pc, "to": pc, "st": "peck", "until": 1e9, "dir": 1, "fly_t": 0.0, "inside": false})
			var pf := Vector2(float(cv[0]) + 0.2, float(cv[1]) - 0.8)
			gm.sim.fauna.pigeons.append({"pos": pf, "from": pf - Vector2(2, 0), "to": pf + Vector2(2, 0), "st": "fly", "until": 1e9, "dir": 1, "fly_t": 0.0, "inside": false})
			var pw := Vector2(float(cv[0]) + 2.4, float(cv[1]) + 0.5)
			gm.sim.fauna.pigeons.append({"pos": pw, "to": pw, "st": "walk", "until": 1e9, "dir": -1, "fly_t": 0.0, "inside": false})
	if mode == "objbadges_tip":
		for r: Dictionary in gm.obj_badges.tracker.visible_list():
			if str(r["k"]) == "heat":
				await get_tree().create_timer(0.3).timeout
				gm.obj_badges.mouse_override = gm.obj_badges._rect(r["m"], gm.obj_badges._zoom()).get_center()
	if mode == "badges_tip":
		# наведение мыши на значок: подсказка с причиной
		var mt: Thing = null
		for r: Dictionary in gm.badges.tracker.visible_list(false):
			if str(r["k"]) == "full":
				mt = r["m"]
		if mt != null:
			await get_tree().create_timer(0.3).timeout
			gm.badges.mouse_override = gm.badges._rect(mt, gm.badges._zoom()).get_center()
	await get_tree().create_timer(0.6).timeout
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if mode == "hire":
		img = img.get_region(Rect2i(10, 70, 470, 260))
		img.resize(img.get_width() * 3, img.get_height() * 3, Image.INTERPOLATE_NEAREST)
	if crop_arg != "":
		var rv := crop_arg.split(",")
		img = img.get_region(Rect2i(int(rv[0]), int(rv[1]), int(rv[2]), int(rv[3])))
	if mode == "crop":
		img = img.get_region(Rect2i(400, 900, 1120, 180))
	img.save_png(out)
	print("saved ", out, " ", img.get_size())
	get_tree().quit(0)


## 1.55: снимки живости цеха, ночи и сезонов: sparks155 | night155 | winter155 | autumn155.
func _setup155(gm: GameMain) -> void:
	var sm := gm.sim
	var want := "winter" if mode == "winter155" else ("autumn" if mode in ["autumn155", "night155"] else "summer")
	var hour := 23.0 if mode == "night155" else 12.0
	for d in 400:
		sm.minute = float(d) * 1440.0 + hour * 60.0
		if sm.season.season_id() == want:
			break
	if mode == "winter155":
		for i in sm.season.snow.size():
			sm.season.snow[i] = 200
		sm.season.snow_rev += 1
	# сломанный станок для аварийной лампы
	var done := false
	for m in sm.things_of("machine"):
		if m.process() == "milling" and not done:
			m.broken = true
			m.working = false
			done = true
	gm.hud.close_modal()
	gm.menu_paused = false
	await get_tree().create_timer(2.0).timeout
	for m2 in sm.things_of("machine"):
		if not m2.broken:
			m2.working = true
			m2.progress = 0.6


## 1.54: «до / после» встроенных значков рядом со значками владельца (assets/ui/icons).
## Ряды сверху вниз: значок владельца (эталон того же смысла) · встроенный ДО · встроенный ПОСЛЕ (перекрашенный SVG) · что видно в игре (Tex.ui).
func _icons154(gm: Node) -> void:
	var names: Array = []
	for line in FileAccess.get_file_as_string("res://tests/icons154_names.txt").split("\n", false):
		names.append(line.strip_edges())
	var before: Dictionary = {}
	var bf := FileAccess.open("/home/claude/pz_work/icons_before/ui.json", FileAccess.READ)
	if bf:
		before = JSON.parse_string(bf.get_as_text())
	var cl := CanvasLayer.new()
	cl.layer = 100
	add_child(cl)
	var root := Control.new()
	cl.add_child(root)
	var bg := ColorRect.new()
	bg.color = Color("#23262c")
	bg.size = Vector2(1920, 1080)
	root.add_child(bg)
	var per := 14
	var cs := 84
	var row_t := ["значок владельца", "встроенный: до", "встроенный: после (SVG)", "в игре (Tex.ui)"]
	for i in names.size():
		var n: String = names[i]
		var bx := 150 + (i % per) * (cs + 16)
		var by := 20 + (i / per) * (4 * cs + 56)
		var ow := str(Tex.PNG_ALIAS.get(n, n))
		var rows: Array = [
			Tex.png(ow, 96) if ResourceLoader.exists("res://assets/ui/icons/%s.png" % ow) else null,
			Vec.raster(str(before.get(n, "")), 2.0) if before.has(n) else null,
			Vec.raster(Vec.source("ui", n), 2.0),
			Tex.ui(n)]
		for r in 4:
			var tr_ := TextureRect.new()
			tr_.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tr_.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			tr_.texture = rows[r]
			tr_.position = Vector2(bx, by + r * cs)
			tr_.size = Vector2(80, 80)
			root.add_child(tr_)
		var lb := Label.new()
		lb.text = n
		lb.position = Vector2(bx, by + 4 * cs - 4)
		lb.add_theme_font_size_override("font_size", 13)
		root.add_child(lb)
		if i % per == 0:
			for r in 4:
				var rl := Label.new()
				rl.text = str(row_t[r])
				rl.position = Vector2(8, by + r * cs + 28)
				rl.size = Vector2(138, 40)
				rl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				rl.add_theme_font_size_override("font_size", 12)
				root.add_child(rl)
	await get_tree().create_timer(0.3).timeout
