extends Node
## 1.40 (f1): снимки меню стройки/объектов, план, верхняя панель (под xvfb):
## xvfb-run -a -s "-screen 0 1600x900x24" godot --path . --rendering-driver opengl3 --resolution 1600x900 res://tests/p140f1_shots.tscn -- --lang=en --out=/папка

var out := "/tmp"
var pre := "p140f1"


func _wait(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(out.path_join(pre + "_" + name + ("_en" if L.is_en() else "_ru") + ".png"))
	print("saved ", name)


func _ready() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.get_slice("=", 1)
		if a.begins_with("--pre="):
			pre = a.get_slice("=", 1)
	Game.pending = "new"
	Game.pending_scn = "garage"
	Game.pending_profile = "mech"
	Game.pending_opts = {"tutorial": false}
	Game.pending_seed = 140
	Game.settings["tutorial_done"] = true
	var gm: GameMain = load("res://scenes/game.tscn").instantiate()
	add_child(gm)
	await get_tree().create_timer(2.0).timeout
	var h: Hud = gm.hud
	h.toggle_sub("objects")
	h.obj_cat = "Станки"
	h._fill_sub()
	await _wait(6)
	await _shot("obj_machines")
	h.obj_cat = "ЧПУ"
	h._fill_sub()
	await _wait(6)
	await _shot("obj_cnc")
	BuildMenu.query["objects"] = "токар" if not L.is_en() else "lathe"
	h._fill_sub()
	await _wait(6)
	await _shot("search")
	h.close_sub()
	for r: Rooms.Room in gm.sim.rooms.list:
		if r.type == "canteen":
			gm.cam.zoom = Vector2(1.8, 1.8)
			gm.cam.position = (Vector2(r.cells[r.cells.size() / 2]) + Vector2(0.5, 0.5)) * World.T
	h.obj_cat = "Быт"
	h.toggle_sub("objects")
	await get_tree().create_timer(0.6).timeout
	await _shot("canteen_need")
	h.toggle_sub("build")
	await _wait(6)
	await _shot("build")
	h.toggle_plan()
	await _wait(6)
	await _shot("plan")
	get_tree().quit(0)
