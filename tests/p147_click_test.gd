extends Node
## 1.47: реальные клики мышью по одной зоне подряд — размер карточки не растёт.
var fails: Array[String] = []
var gm: GameMain


func check(cond: bool, what: String) -> void:
	print(("  ok  " if cond else "  FAIL ") + what)
	if not cond:
		fails.append(what)


func _wait(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _click(cell: Vector2i, settle: int = 4) -> void:
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


func _ready() -> void:
	get_tree().create_timer(120.0).timeout.connect(func() -> void: get_tree().quit(2))
	Game.pending = "new"
	Game.pending_scn = "garage"
	Game.pending_profile = "mech"
	Game.pending_opts = {"tutorial": false}
	Game.pending_seed = 1421
	Game.settings["tutorial_done"] = true
	gm = load("res://scenes/game.tscn").instantiate()
	add_child(gm)
	await get_tree().create_timer(2.0).timeout
	var room: Rooms.Room = null
	for r in gm.sim.rooms.list:
		if r.type == "workshop":
			room = r
	if room == null:
		room = gm.sim.rooms.list[0]
	var cc: Vector2i = room.rect.position + room.rect.size / 2
	gm.cam.focus_cell(cc)
	gm.set_speed(3)
	await _wait(3)
	var th: Thing = null
	for t: Thing in gm.sim.things.values():
		if t.def_id != "" and t.cell.x > 0:
			th = t
			break
	var oc: Vector2i = th.cell if th else cc
	gm.tool.set_mode("select")
	for m in ["select", "room", "fast", "object", "object_fast"]:
		if m == "room":
			gm.hud.open_rooms()
		if m == "object":
			gm.tool.set_mode("select")
		if m == "object":
			gm.cam.focus_cell(oc)
			await _wait(3)
		var sz: Array[float] = []
		for k in 8:
			await _click(oc if m.begins_with("object") else cc, 0 if m.ends_with("fast") else 30)
			sz.append(gm.hud.info.size.y)
		print(m, " kind=", gm.hud.info.kind, " id=", gm.hud.info.id, " vis=", gm.hud.info.visible, " h=", sz, " w=", gm.hud.info.size.x)
		check(sz[7] < 700.0 and absf(sz[7] - sz[1]) < 40.0, "режим %s: карточка после 8 кликов %.0f (первая %.0f)" % [m, sz[7], sz[0]])
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("/home/claude/pz_work/shots/p147_zone_after_clicks.png")
	print("РЕЗУЛЬТАТ: " + ("OK" if fails.is_empty() else "ОШИБКИ"))
	get_tree().quit(0 if fails.is_empty() else 1)
