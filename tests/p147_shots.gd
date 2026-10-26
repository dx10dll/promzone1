extends Node
## 1.47: снимки интерфейса. xvfb-run -a -s "-screen 0 1920x1080x24" godot --path . --resolution 1920x1080 res://tests/p147_shots.tscn -- --mode=full|crop|hud|card|orders --out=/файл.png [--lang=ru]

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
	var gm: GameMain = load("res://scenes/game.tscn").instantiate()
	add_child(gm)
	await get_tree().create_timer(1.5).timeout
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
