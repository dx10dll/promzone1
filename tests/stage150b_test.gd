extends Node
const S := preload("res://tests/setups.gd")
## 1.50b: клик по полу не открывает карточку; карточка объекта и окно заказов не растут; итог торга и пересчёт риска;
## значок «События» только по решениям; призраки сетей; кнопка «Пропустить» прячется при открытых окнах; поиск в «Зонах».
## xvfb-run -a -s "-screen 0 1920x1080x24" godot --path . res://tests/stage150b_test.tscn
var fails: Array[String] = []
var gm: GameMain
var toasts: Array = []


func check(cond: bool, what: String) -> void:
	print(("  ok  " if cond else "  FAIL ") + what)
	if not cond:
		fails.append(what)


func _wait(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _click(cell: Vector2i, settle: int = 6) -> void:
	var tl := gm.tool
	var scr: Vector2 = tl.get_global_transform_with_canvas() * ((Vector2(cell) + Vector2(0.5, 0.5)) * float(BuildTool.T))
	scr = get_window().get_final_transform() * scr
	var mm := InputEventMouseMotion.new()
	mm.position = scr
	mm.global_position = scr
	Input.warp_mouse(scr)
	get_viewport().push_input(mm)
	await _wait(2)
	for pr in [true, false]:
		var mb := InputEventMouseButton.new()
		mb.button_index = MOUSE_BUTTON_LEFT
		mb.pressed = pr
		mb.position = scr
		mb.global_position = scr
		get_viewport().push_input(mb)
		await _wait(1)
	await _wait(settle)


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)


func _find_label(root: Node, part: String) -> Label:
	for n in root.find_children("*", "Label", true, false):
		if (n as Label).text.contains(part):
			return n as Label
	return null


func _ready() -> void:
	get_tree().create_timer(170.0).timeout.connect(func() -> void: get_tree().quit(2))
	Game.pending = "new"
	Game.pending_scn = "garage"
	Game.pending_profile = "mech"
	Game.pending_opts = {"tutorial": false}
	Game.pending_seed = 1501
	Game.settings["tutorial_done"] = true
	gm = load("res://scenes/game.tscn").instantiate()
	add_child(gm)
	await get_tree().create_timer(2.0).timeout
	var sim := gm.sim
	var hud := gm.hud
	gm.set_speed(0)
	var room: Rooms.Room = null
	for r in sim.rooms.list:
		if r.type == "workshop":
			room = r
	if room == null:
		room = sim.rooms.list[0]
	var cc: Vector2i = room.rect.position + room.rect.size / 2
	gm.cam.focus_cell(cc)
	await _wait(3)

	print("== 1. клик по полу")
	var floor_c := Vector2i(-1, -1)
	for c in room.cells:
		if sim.thing_at(c) == null and sim.world.wall[sim.world.idx(c)] == World.W_NONE:
			floor_c = c
			break
	gm.tool.set_mode("select")
	hud.info.visible = false
	await _click(floor_c, 10)
	check(not hud.info.visible, "клик по полу в помещении не открывает карточку (%s)" % str(floor_c))
	await _click(floor_c, 10)
	check(not hud.info.visible, "повторный клик по полу — тоже")

	print("== 2. карточка объекта при повторных кликах")
	var things: Array[Thing] = []
	for t: Thing in sim.things.values():
		if t.def_id != "" and t.cell.x > 0 and t.built and t.kind() != "light":
			things.append(t)
		if things.size() >= 2:
			break
	var th: Thing = things[0]
	gm.cam.focus_cell(th.cell)
	await _wait(3)
	var sizes: Array[Vector2] = []
	for k in 10:
		await _click(th.cell, 6)
		sizes.append(hud.info.size)
	check(hud.info.visible, "карточка объекта открыта")
	print("  размеры: ", sizes)
	check(sizes[9].distance_to(sizes[0]) < 3.0, "размер после 10 кликов %s = после 1 %s" % [str(sizes[9]), str(sizes[0])])
	if things.size() > 1:
		var sz2: Array[Vector2] = []
		for k in 6:
			var tt: Thing = things[k % 2]
			gm.cam.focus_cell(tt.cell)
			await _wait(2)
			await _click(tt.cell, 6)
			sz2.append(hud.info.size)
		var mx := 0.0
		for v in sz2:
			mx = maxf(mx, v.y)
		check(mx < 700.0 and hud.info.size.x < 600.0, "по разным объектам карточка не раздувается (макс. высота %.0f)" % mx)
	hud.info.visible = false

	print("== 3. доска заявок: окно не растёт")
	sim.sales.board.clear()
	sim.sales.enabled = true
	sim.sales.paused = false
	for i in 3:
		var o := sim.orders.make_offer()
		sim.sales._post(o)
	hud.open_window("orders:board")
	await _wait(10)
	var w0: Vector2 = hud.win.size
	var cw0 := hud.win.content.size.x
	var ids: Array = []
	for o2: Dictionary in sim.sales.board:
		ids.append(int(o2["id"]))
	for k in 12:
		var hs: Dictionary = OrderBoard._hg.get(ids[k % 3], {"open": false, "pk": 10, "la": 0})
		hs["open"] = not bool(hs["open"])
		hs["la"] = k % 4
		OrderBoard._hg[ids[k % 3]] = hs
		hud.win.rebuild(true)
		await _wait(2)
	await _wait(5)
	check(hud.win.size.is_equal_approx(w0), "окно заказов: размер %s после 12 перестроек = %s" % [str(hud.win.size), str(w0)])
	check(absf(hud.win.content.size.x - cw0) < 2.0, "ширина содержимого стабильна (%.0f / %.0f)" % [hud.win.content.size.x, cw0])
	check(_find_label(hud.win.content, "Станки заняты на") != null, "на карточке «Станки заняты на», а не «Загрузка»")
	check(_find_label(hud.win.content, "ЗАГРУЗКА") == null, "слова «ЗАГРУЗКА» нет")

	print("== 4. пересчёт риска по сроку")
	var found := false
	var gs := Scenario.new_game("garage", "mech", "calm", 1502)
	gs.story.enabled = false
	S.big_shop(gs, true)
	for o0: Dictionary in gs.orders.list.duplicate():
		gs.orders.list.erase(o0)
	var o3 := gs.orders.make_offer("pin")
	print("  загрузка qty=1: ", gs.office.load_info(str(o3["product"]), 1), " qty=50: ", gs.office.load_info(str(o3["product"]), 50))
	for q in range(1, 300, 2):
		for ld in range(1, 15):
			o3["qty"] = q
			o3["lead"] = ld
			var lv0 := int(OrderBoard.risk_for(gs, o3, 0)["level"])
			var lv3 := int(OrderBoard.risk_for(gs, o3, 3)["level"])
			if lv3 < lv0:
				found = true
				print("  qty=%d срок %d: +0 -> %s, +3 -> %s" % [q, ld, OrderBoard.risk_word(lv0), OrderBoard.risk_word(lv3)])
				break
		if found:
			break
	check(found, "добавленный срок понижает риск (успеем / впритык / не успеем пересчитываются)")
	check(int(OrderBoard.risk_for(gs, o3, 0)["level"]) == int(gs.sales.board_risk(o3)["level"]), "при +0 риск как на карточке")

	print("== 4б. сбыт сам берёт только «успеем»")
	gs.sales.board.clear()
	gs.sales.log.clear()
	gs.sales.queue.clear()
	gs.sales.enabled = true
	gs.sales.paused = false
	gs.sales.mode = "auto"
	var easy := gs.orders.make_offer("pin")
	easy["qty"] = 1
	easy["lead"] = 40
	easy["deadline"] = gs.orders.deadline_after(40)
	easy["price"] = 100000.0
	check(int(gs.sales.board_risk(easy)["level"]) == 0, "лёгкая заявка: риск «успеем»")
	check(gs.sales.verdict(easy)[0] == "", "…сбыт её берёт")
	var hard := gs.orders.make_offer("pin")
	hard["qty"] = 50
	for ld in range(1, 40):
		hard["lead"] = ld
		if int(gs.sales.board_risk(hard)["level"]) == 1:
			break
	hard["price"] = 100000.0
	var lvh := int(gs.sales.board_risk(hard)["level"])
	print("  «впритык»: срок %s, уровень %d" % [str(hard["lead"]), lvh])
	check(lvh == 1 and str(gs.sales.verdict(hard)[0]).begins_with("не успеваем"), "«впритык» — сбыт сам не берёт (причина: «%s»)" % str(gs.sales.verdict(hard)[0]))
	gs.sales.mode = "small"
	var n_before := gs.orders.active_count()
	gs.sales.inquiry(hard)
	check(gs.orders.active_count() == n_before and not gs.sales.board.is_empty(), "«Мелочь сам»: заявка впритык ложится на доску")
	gs.sales.mode = "auto"
	gs.sales.board.clear()
	# перегруженный завод: берём сразу много заказов, следующий уже не успеваем
	var taken := 0
	for k in 30:
		var ov := gs.orders.make_offer("pin")
		ov["qty"] = 30
		ov["lead"] = 4
		ov["deadline"] = gs.orders.deadline_after(4)
		ov["price"] = 100000.0
		if gs.sales.verdict(ov)[0] == "":
			gs.sales._take(ov)
			taken += 1
		else:
			break
	var ov2 := gs.orders.make_offer("pin")
	ov2["qty"] = 30
	ov2["lead"] = 4
	ov2["deadline"] = gs.orders.deadline_after(4)
	ov2["price"] = 100000.0
	check(taken < 30 and str(gs.sales.verdict(ov2)[0]) != "", "перегруженный завод (взято %d): сбыт больше сам не берёт — «%s»" % [taken, str(gs.sales.verdict(ov2)[0])])

	print("== 5. итог торга")
	var ok_seen := false
	var no_seen := false
	var tries := 0
	while (not ok_seen or not no_seen) and tries < 60:
		tries += 1
		var o4 := sim.orders.make_offer()
		sim.sales._post(o4)
		toasts.clear()
		var res := OrderBoard.do_haggle(sim, int(o4["id"]), 0.15 if tries % 2 == 0 else 0.0, 0 if tries % 2 == 0 else 3, func(t: String, lvl: int) -> void: toasts.append([t, lvl]))
		if res == "ok" and not ok_seen:
			ok_seen = true
			check(not toasts.is_empty() and int(toasts[0][1]) >= Sim.LVL_WARN and str(toasts[0][0]).contains("согласился"), "согласие: заметное уведомление «%s»" % str(toasts[0][0]))
			check(OrderBoard._res.has(int(o4["id"])) and bool(OrderBoard._res[int(o4["id"])]["ok"]), "плашка согласия сохранена")
			hud.win.rebuild(true)
			await _wait(4)
			check(_find_label(hud.win.content, "Заказчик согласился") != null, "зелёная плашка видна на доске")
		elif res == "no" and not no_seen:
			no_seen = true
			check(not toasts.is_empty() and int(toasts[0][1]) >= Sim.LVL_WARN and str(toasts[0][0]).contains("отказался"), "отказ: заметное уведомление")
			hud.win.rebuild(true)
			await _wait(4)
			check(_find_label(hud.win.content, "отказался и ушёл") != null, "красная плашка отказа видна на доске")
	check(ok_seen and no_seen, "получены оба исхода торга (%d попыток)" % tries)

	print("== 6. значок «События»")
	hud.close_window()
	sim.story.letters.clear()
	sim.story.fires.clear()
	sim.story.strike["active"] = false
	for i in 8:
		hud.on_notified("Привезли металл %d" % i, Sim.LVL_INFO, Vector2i(-1, -1))
	hud._refresh_top()
	check(hud.decision_count() == 0 and not hud.events_badge.visible, "рутинные записи значок не растят")
	sim.story.strike["active"] = true
	hud._refresh_top()
	check(hud.decision_count() == 1 and hud.events_badge.visible, "незавершённая тревога — значок 1")
	sim.story.strike["active"] = false
	hud._refresh_top()
	check(not hud.events_badge.visible, "тревога устранена — значок пропал")

	print("== 7. «Пропустить» и меню")
	for wk in sim.workers:
		wk.present = false
	sim.minute = float(int(sim.minute / 1440.0) * 1440 + 1380)
	gm.menu_paused = false
	hud._refresh_top()
	var can := sim.can_skip_idle()
	print("  can_skip_idle=", can, " visible=", hud.skip_btn.visible)
	check(not hud.menus_open(), "окна закрыты")
	if can:
		check(hud.skip_btn.visible, "кнопка видна, когда всё закрыто")
	hud.open_window("orders:board")
	await _wait(4)
	hud._refresh_top()
	check(hud.menus_open() and not hud.skip_btn.visible, "окно открыто — кнопка скрыта")
	hud.close_window()
	hud.toggle_sub("objects")
	await _wait(4)
	hud._refresh_top()
	check(hud.menus_open() and not hud.skip_btn.visible, "нижнее меню открыто — кнопка скрыта")

	print("== 8. поиск в «Зонах»")
	hud.close_sub()
	hud.open_rooms()
	await _wait(5)
	var le: LineEdit = null
	for n in hud.sub_panel.find_children("*", "LineEdit", true, false):
		if n.has_meta("search") and str(n.get_meta("search")) == "rooms":
			le = n as LineEdit
	check(le != null, "в меню «Зоны» есть поле поиска")
	if le:
		le.text = "склад"
		le.text_changed.emit("склад")
		await _wait(5)
		var tiles := 0
		for b in hud.sub_panel.find_children("*", "Button", true, false):
			if (b as Button).has_meta("arg") and str((b as Button).get_meta("arg")) != "":
				tiles += 1
		check(tiles > 0 and tiles < 14, "поиск «склад» оставляет плитки (%d)" % tiles)
	hud.close_sub()

	print("== 9. призраки сетей")
	var nc := cc + Vector2i(1, 0)
	var placed := 0
	for dx in range(0, 6):
		var cell := cc + Vector2i(dx, 3)
		if sim.world.passable(cell) and sim.world.net_at("cable", cell) == 0 and sim.place_cable(cell):
			placed += 1
	for dx in range(0, 6):
		var cell2 := cc + Vector2i(dx, 5)
		if sim.world.passable(cell2) and sim.world.net_at("pipe", cell2) == 0 and sim.place_pipe(cell2):
			placed += 1
	check(placed > 0 and sim.net_plans().size() >= placed, "заказанные сети — чертежи (%d)" % placed)
	var gl: NetGhostLayer = null
	for n in gm.find_children("*", "NetGhostLayer", true, false):
		gl = n as NetGhostLayer
	check(gl != null, "слой призраков сетей на карте")
	var p0: Array = sim.net_plans()[0]
	var why0 := NetGhostLayer.reason(sim, str(p0[0]), int(p0[1]))
	print("  причина для первой клетки: «%s»" % why0)
	var saved := sim.workers.duplicate()
	sim.workers.clear()
	check(NetGhostLayer.reason(sim, "pipe", int(p0[1])) != "", "некому тянуть — призрак красный, есть причина")
	sim.workers.assign(saved)
	sim.net_res["%s:%d" % [str(p0[0]), int(p0[1])]] = 0
	gm.tool.set_mode("select")
	gm.cam.focus_cell(cc + Vector2i(3, 4))
	gm.cam.zoom = Vector2(2.2, 2.2)
	hud.close_window()
	await _wait(8)
	await _shot("/home/claude/pz_work/shots/p150_ghost_nets.png")
	sim.net_res.clear()

	print("== 10. снимок доски с торгом")
	sim.sales.board.clear()
	OrderBoard._res.clear()
	var oa := sim.orders.make_offer()
	sim.sales._post(oa)
	var ob := sim.orders.make_offer()
	sim.sales._post(ob)
	var oc := sim.orders.make_offer()
	oc["qty"] = 40
	oc["lead"] = 5
	sim.sales._post(oc)
	var guard := 0
	while sim.sales.haggle(int(oa["id"]), 0.0, 0) == "" and guard < 3:
		guard += 1
	# согласие для карточки A, отказ для B
	var got_ok := false
	var got_no := false
	for k in 80:
		if got_ok and got_no:
			break
		var tmp := sim.orders.make_offer()
		sim.sales._post(tmp)
		var rs := OrderBoard.do_haggle(sim, int(tmp["id"]), 0.0, 1, func(_t: String, _l: int) -> void: pass)
		if rs == "ok" and not got_ok:
			got_ok = true
		elif rs == "ok":
			sim.sales.refuse(int(tmp["id"]))
		elif rs == "no" and not got_no:
			got_no = true
	var hs_c: Dictionary = {"open": true, "pk": 10, "la": 3}
	OrderBoard._hg[int(oc["id"])] = hs_c
	hud.open_window("orders:board")
	await _wait(10)
	await _shot("/home/claude/pz_work/shots/p150_board_haggle.png")
	print("РЕЗУЛЬТАТ: " + ("OK" if fails.is_empty() else "ОШИБКИ: " + str(fails)))
	get_tree().quit(0 if fails.is_empty() else 1)
