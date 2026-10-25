extends Node
## 1.40 (f5): снимки оверлея «Логистика» на «Чистом поле».
## xvfb-run -a -s "-screen 0 1600x900x24" godot --path . --rendering-driver opengl3 --resolution 1600x900 res://tests/p140f5_shots.tscn -- --lang=ru --out=/папка

const Plant := preload("res://tests/stage140f5_test.gd")
var out := "/tmp"


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out.path_join(name))


func _ready() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.get_slice("=", 1)
	Game.pending = "new"
	Game.pending_scn = "field"
	Game.pending_profile = "mech"
	Game.pending_opts = {"tutorial": false}
	Game.pending_seed = 1405
	Game.settings["tutorial_done"] = true
	var gm: GameMain = load("res://scenes/game.tscn").instantiate()
	add_child(gm)
	await get_tree().create_timer(2.0).timeout
	var sim := gm.sim
	Plant.build_plant(sim)
	var rs: Dictionary = {}
	for r in sim.rooms.list:
		var k := r.type + str(rs.get(r.type, 0))
		rs[r.type] = int(rs.get(r.type, 0)) + 1
		rs[k] = r
	var ar := sim.areas
	var w0: Rooms.Room = rs["workshop0"]
	var w1: Rooms.Room = rs["workshop1"]
	ar.set_link(w0, "locker", rs["locker0"])
	ar.set_link(w0, "wc", rs["wc0"])
	ar.set_link(w0, "canteen", rs["canteen0"])
	ar.set_link(w0, "shower", rs["shower0"])
	ar.set_link(w1, "locker", rs["locker0"])
	ar.set_link(w1, "canteen", rs["canteen1"])
	ar.set_link(w1, "restroom", rs["restroom0"])
	ar.set_link(w1, "wc", rs["wc0"])
	ar.set_itr("canteen", rs["canteen1"])
	ar.set_itr("wc", rs["wc0"])
	ar.set_itr_canteen(rs["canteen1"], true)
	gm.hud.toggle_logistics()
	gm.hud.toasts.visible = false
	gm.cam.focus_cell(Vector2i(26, 21))
	gm.cam.zoom = Vector2(1.0, 1.0)
	await get_tree().create_timer(1.5).timeout
	await _shot("p140f5_logistics1.png")
	# протягиваем новую линию из цеха №2 к душевой — снимок «в процессе»
	gm.tool.logi_press_at(w1.center * World.T)
	gm.hud.hint_panel.visible = true
	await get_tree().create_timer(0.6).timeout
	await _shot("p140f5_logistics2.png")
	get_tree().quit(0)
