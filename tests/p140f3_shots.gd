extends Node
## 1.40 (f3): снимки — директор за столом в гараже, окно «Логистика быта», контора директора в поле, улица.
## xvfb-run -a -s "-screen 0 1600x900x24" godot --path . --rendering-driver opengl3 --resolution 1600x900 res://tests/p140f3_shots.tscn -- --lang=ru --out=/папка

var out := "/tmp"


func _wait(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out.path_join(name))
	print("saved ", out.path_join(name))


func _game(scn: String) -> GameMain:
	Game.pending = "new"
	Game.pending_scn = scn
	Game.pending_profile = "mech"
	Game.pending_opts = {"tutorial": false}
	Game.pending_seed = 140
	Game.settings["tutorial_done"] = true
	var gm: GameMain = load("res://scenes/game.tscn").instantiate()
	add_child(gm)
	return gm


func _ready() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.get_slice("=", 1)
	var gm := _game("garage")
	await _wait(5)
	var d := Director.of(gm.sim)
	for i in 1200:
		gm.sim.tick(0.5)   # утро: ждём, когда директор сядет за свой стол
		if i > 300 and d.present and d.anim == "desk":
			break
	gm.focus_worker(d.id)
	gm.cam.zoom = Vector2(2.0, 2.0)
	await get_tree().create_timer(1.5).timeout
	gm.hud.info.visible = false
	gm.cam.focus_cell(Director.desk(gm.sim).cell + Vector2i(-2, 2))
	gm.cam.zoom = Vector2(1.3, 1.3)
	await get_tree().create_timer(1.5).timeout
	await _shot("p140f3_garage_office.png")
	LogisticsUI.open(gm.hud, gm.sim)
	await _wait(8)
	await _shot("p140f3_logistics.png")
	gm.hud.close_modal()
	gm.queue_free()
	await _wait(3)
	var gf := _game("field")
	await _wait(5)
	for i2 in 380:
		gf.sim.tick(0.5)
	gf.cam.focus_cell(Director.desk(gf.sim).cell)
	gf.cam.zoom = Vector2(1.2, 1.2)
	await get_tree().create_timer(1.5).timeout
	await _shot("p140f3_field_office.png")
	gf.cam.zoom = Vector2(0.45, 0.45)
	await get_tree().create_timer(3.0).timeout
	await _shot("p140f3_street.png")
	get_tree().quit(0)
