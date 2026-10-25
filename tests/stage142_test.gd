extends Node
## 1.42: карточка человека при повторном открытии не растягивается; свой курсор.

var fails: Array[String] = []
var gm: Node


func check(cond: bool, what: String) -> void:
	print(("  ✓ " if cond else "  ✗ ") + what)
	if not cond:
		fails.append(what)


func _wait(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _ready() -> void:
	get_tree().create_timer(200.0).timeout.connect(func() -> void:
		print("РЕЗУЛЬТАТ: ОШИБКИ: тест не уложился во время")
		get_tree().quit(2))
	get_tree().root.size = Vector2i(1600, 900)
	Game.pending = "new"
	Game.pending_scn = "garage"
	Game.pending_profile = "mech"
	Game.pending_opts = {"tutorial": false}
	Game.pending_seed = 1421
	Game.settings["tutorial_done"] = true
	gm = load("res://scenes/game.tscn").instantiate()
	add_child(gm)
	await get_tree().create_timer(2.0).timeout
	var hud: Node = gm.hud
	var sim: Sim = gm.sim
	var info: Control = hud.info
	print("— карточка человека: открыть, закрыть, открыть")
	var w: Worker = sim.workers[0]
	var w2: Worker = sim.workers[1] if sim.workers.size() > 1 else w
	var sizes: Array[Vector2] = []
	for k in 4:
		info.show_worker(sim, w if k % 2 == 0 else w2)
		info.visible = true
		await _wait(4)
		sizes.append(info.size)
		info.close_request.emit()
		await _wait(2)
	# длинная вкладка «История», закрыть, открыть снова
	info.show_worker(sim, w)
	info.visible = true
	await _wait(3)
	InfoPanel.w_tab = "hist"
	info.show_worker(sim, w)
	await _wait(4)
	var hist_h: float = info.size.y
	info.close_request.emit()
	await _wait(2)
	info.show_worker(sim, w)
	info.visible = true
	await _wait(4)
	sizes.append(info.size)
	check(InfoPanel.w_tab == "main", "после закрытия карточка открывается на «Обзоре»")
	check(hist_h < 800.0, "вкладка «История» не на весь экран: %.0f px" % hist_h)
	# и сразу подряд, без закрытия (щелчки по людям)
	for k in 3:
		info.show_worker(sim, w)
		info.visible = true
	await _wait(4)
	sizes.append(info.size)
	print("    размеры: ", sizes)
	for i in range(1, sizes.size()):
		check(absf(sizes[i].y - sizes[0].y) < 40.0 and absf(sizes[i].x - sizes[0].x) < 4.0, "открытие %d того же размера, что первое: %s" % [i + 1, str(sizes[i])])
	check(sizes[0].y < 700.0, "карточка не на весь экран: %.0f px" % sizes[0].y)
	print("— карточка зоны: несколько щелчков подряд")
	var room = null
	for r in sim.rooms.list:
		if r.type == "workshop":
			room = r
	if room != null:
		var cc: Vector2i = room.rect.position + room.rect.size / 2
		var zs: Array[Vector2] = []
		for k in 6:
			info.near_screen = Vector2(600, 400)
			info.show_cell(sim, cc)
			await _wait(4)
			zs.append(info.size)
		print("    зона: ", zs)
		var rs: Array[Vector2] = []
		for k in 6:
			info.near_screen = Vector2(600, 400)
			hud.on_room_clicked(room.id)
			await _wait(4)
			rs.append(info.size)
		print("    помещение: ", rs)
		var gs: Array[Vector2] = []
		for k in 5:
			await get_tree().create_timer(1.0).timeout
			gs.append(info.size)
		print("    помещение со временем: ", gs, " vis=", info.visible)
		var mix: Array[Vector2] = []
		for k in 3:
			info.near_screen = Vector2(-1, -1)
			info.show_worker(sim, w)
			await _wait(4)
			mix.append(info.size)
			info.near_screen = Vector2(600, 400)
			hud.on_room_clicked(room.id)
			await _wait(4)
			mix.append(info.size)
			info.near_screen = Vector2(600, 400)
			info.show_cell(sim, cc)
			await _wait(4)
			mix.append(info.size)
		print("    вперемешку: ", mix)
		print("    rect: ", info.get_rect(), " anchors ", [info.anchor_left, info.anchor_right, info.anchor_top, info.anchor_bottom])
		check(absf(rs[5].y - rs[0].y) < 40.0 and rs[5].y < 760.0, "шестой щелчок по зоне цеха — та же высота: %.0f → %.0f" % [rs[0].y, rs[5].y])
		check(absf(zs[5].y - zs[0].y) < 40.0, "шестой щелчок по цеху — та же высота: %.0f → %.0f" % [zs[0].y, zs[5].y])
		check(zs[5].y < 700.0, "карточка зоны не на весь экран: %.0f" % zs[5].y)
	print("— курсор")
	check(Game.cursor_ok(), "свой курсор загружен")
	print("РЕЗУЛЬТАТ: " + ("OK" if fails.is_empty() else "ОШИБКИ: %d" % fails.size()))
	get_tree().quit(0 if fails.is_empty() else 1)
